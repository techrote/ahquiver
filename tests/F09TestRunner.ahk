#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\modules\F09_ControllerBridge.ahk

class F09Cfg {
    __New() {
        this.V := Map()
        this.Path := "F09Test.ini"
    }
    Set(s,k,v) => this.V[s "|" k] := v ""
    Get(s,k,d := "") => this.V.Has(s "|" k) ? this.V[s "|" k] : d
    GetInt(s,k,d := 0) {
        v := this.Get(s,k,d "")
        return RegExMatch(v,"^-?\d+$") ? v+0 : d
    }
    GetBool(s,k,d := false) {
        v := StrLower(this.Get(s,k,d ? "1" : "0"))
        return v="1" || v="true" || v="yes" || v="on"
    }
}
class F09Log {
    Info(*) {
        return
    }
    Warn(*) {
        return
    }
    Error(*) {
        return
    }
}
class F09FakeClock {
    __New(n:=1000) {
        this.N:=n
    }
    Now() => this.N
    Advance(ms) => this.N += ms
}
class F09App {
    __New(cfg) {
        this.Config:=cfg, this.Log:=F09Log(), this.Actions:=AQActionRegistry(this.Log), this.Capabilities:=AQCapabilityRegistry(), this.Calls:=[]
    }
    Add(id) => this.Actions.Register(id,(p)=>F09Capture(this,id,p),"test","S0")
}
F09Capture(app,id,p) {
    c:=Map()
    for k,v in p
        c[k]:=v
    app.Calls.Push(Map("id",id,"params",c))
    return AQResult.Ok("captured")
}
F09Config() {
    c:=F09Cfg()
    c.Set("F09","mappings","button,encoder")
    c.Set("F09","max_events_per_second","3")
    c.Set("F09","max_events_per_poll","8")
    c.Set("F09.mapping.button","enabled","1"), c.Set("F09.mapping.button","event","button.green"), c.Set("F09.mapping.button","action","button.action")
    c.Set("F09.mapping.button","value_type","enum"), c.Set("F09.mapping.button","allowed_values","press,release"), c.Set("F09.mapping.button","value_param","state"), c.Set("F09.mapping.button","debounce_ms","100")
    c.Set("F09.mapping.encoder","enabled","1"), c.Set("F09.mapping.encoder","event","encoder.main"), c.Set("F09.mapping.encoder","action","encoder.action")
    c.Set("F09.mapping.encoder","value_type","int"), c.Set("F09.mapping.encoder","min","-4"), c.Set("F09.mapping.encoder","max","4"), c.Set("F09.mapping.encoder","value_param","delta")
    return c
}
F09Service(&app,&source,&clock) {
    cfg:=F09Config(), app:=F09App(cfg), app.Add("button.action"), app.Add("encoder.action"), source:=F09SyntheticSource(), source.Open(), clock:=F09FakeClock(), mappings:=F09MappingStore(cfg,app.Actions)
    return F09ControllerService(app,source,mappings,clock)
}

TestProtocol() {
    p:=F09Protocol()
    r:=p.Parse("AQ1|button.green|press|12")
    A9(r.IsOk()), E9("button.green",r.Data["event"]), E9(12,r.Data["sequence"])
    E9("unsupported",p.Parse("AQ2|button.green|press|13").Status)
    E9("invalid",p.Parse("AQ1|bad event|x|1").Status)
    E9("invalid",p.Parse("AQ1|x|y").Status)
}
TestValidButtonAndEncoder() {
    s:=F09Service(&a,&src,&clk)
    A9(s.ProcessLine("AQ1|button.green|press|1").IsOk())
    clk.Advance(150)
    A9(s.ProcessLine("AQ1|encoder.main|-2|1").IsOk())
    E9(2,a.Calls.Length), E9("press",a.Calls[1]["params"]["state"]), E9(-2,a.Calls[2]["params"]["delta"])
}
TestUnknownAndInvalidValues() {
    s:=F09Service(&a,&src,&clk)
    E9("rejected",s.ProcessLine("AQ1|unknown.event|x|1").Status)
    E9("invalid",s.ProcessLine("AQ1|encoder.main|99|1").Status)
    E9("invalid",s.ProcessLine("AQ1|button.green|hold|1").Status)
    E9(0,a.Calls.Length)
}
TestDebounceAndSequence() {
    s:=F09Service(&a,&src,&clk)
    A9(s.ProcessLine("AQ1|button.green|press|1").IsOk())
    clk.Advance(20)
    E9("rejected",s.ProcessLine("AQ1|button.green|release|2").Status)
    clk.Advance(100)
    E9("rejected",s.ProcessLine("AQ1|button.green|release|1").Status)
    A9(s.ProcessLine("AQ1|button.green|release|3").IsOk())
}
TestRateLimit() {
    s:=F09Service(&a,&src,&clk)
    A9(s.ProcessLine("AQ1|encoder.main|1|1").IsOk()), A9(s.ProcessLine("AQ1|encoder.main|1|2").IsOk()), A9(s.ProcessLine("AQ1|encoder.main|1|3").IsOk())
    E9("rejected",s.ProcessLine("AQ1|encoder.main|1|4").Status)
    clk.Advance(1001), A9(s.ProcessLine("AQ1|encoder.main|1|5").IsOk())
}
TestDisconnectedReconnectAndPoll() {
    s:=F09Service(&a,&src,&clk), src.Close(), src.Push("AQ1|encoder.main|2|1")
    r:=s.Poll(), A9(r.IsOk()), E9(1,a.Calls.Length), A9(src.Connected)
    src.FailReads:=true
    E9("failed",s.Poll().Status), A9(!src.Connected)
    src.FailReads:=false, A9(s.Poll().IsOk()), A9(src.Connected)
}
TestDisabled() {
    s:=F09Service(&a,&src,&clk), s.SetEnabled(false)
    E9("cancelled",s.ProcessLine("AQ1|encoder.main|1|1").Status), E9(0,a.Calls.Length)
}
TestInvalidMappingLocal() {
    c:=F09Config(), c.Set("F09","mappings","bad,encoder"), c.Set("F09.mapping.bad","event","bad.event"), c.Set("F09.mapping.bad","action","missing")
    a:=F09App(c), a.Add("encoder.action"), m:=F09MappingStore(c,a.Actions)
    E9(1,m.Items.Count), E9(1,m.Diagnostics.Length)
}

passed:=0, failed:=0, progress:=EnvGet("AQ_TEST_PROGRESS")
tests:=[TestProtocol,TestValidButtonAndEncoder,TestUnknownAndInvalidValues,TestDebounceAndSequence,TestRateLimit,TestDisconnectedReconnectAndPoll,TestDisabled,TestInvalidMappingLocal]
for fn in tests {
    try {
        fn.Call(), passed+=1, FileAppend("PASS " fn.Name "`n","*")
    } catch as testError {
        failed+=1, FileAppend("FAIL " fn.Name ": " testError.Message "`n","*")
    }
}
FileAppend("RESULT passed=" passed " failed=" failed "`n","*")
ExitApp(failed?1:0)
A9(v,m:="expected true") {
    if !v
        throw Error(m)
}
E9(e,a,m:="") {
    if e != a
        throw Error((m!=""?m ": ":"") "expected=" e " actual=" a)
}
