#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\modules\F10_SourceMapEdit.ahk

class F10FakeSelection {
    __New(sessionId := "s1", start := 0, finish := 1, status := "ok") {
        this.SessionId := sessionId, this.Start := start, this.Finish := finish, this.Status := status
    }
    Capture() {
        if this.Status = "unsupported"
            return AQResult.Unsupported("fixture unsupported")
        return AQResult.Ok("fixture selection", Map("render_session_id",this.SessionId,"render_start",this.Start,"render_end",this.Finish))
    }
}
class F10FakeMapProvider {
    __New(contract) {
        this.Contract := contract
    }
    Load() => AQResult.Ok("fixture map", Map("contract",this.Contract))
}
class F10MemoryStore {
    __New(text, path := "memory://doc") {
        this.Text:=text
        this.Path:=path
        this.FailDelete:=false
        this.RollbackCount:=0
    }
    Snapshot(path) {
        return AQResult.Ok("memory snapshot",Map("text",this.Text,"hash",F10Fingerprint.Hash(this.Text),"length",StrLen(this.Text)))
    }
    DeleteRanges(path,expectedHash,ranges) {
        if F10Fingerprint.Hash(this.Text) != expectedHash
            return AQResult.Rejected("stale")
        before := this.Text
        if this.FailDelete {
            this.Text := "CORRUPTED"
            this.Text := before
            this.RollbackCount += 1
            return AQResult.Failed("synthetic write failed; rolled back")
        }
        i := ranges.Length
        while i >= 1 {
            item := ranges[i]
            this.Text := SubStr(this.Text,1,item["start"]) SubStr(this.Text,item["end"]+1)
            i -= 1
        }
        return AQResult.Ok("deleted",Map("new_hash",F10Fingerprint.Hash(this.Text),"backup_path","memory://backup"))
    }
}
F10Contract(text, ranges, session := "s1", doc := "d1", path := "memory://doc", hashOverride := "") {
    hash := hashOverride != "" ? hashOverride : F10Fingerprint.Hash(text)
    return F10SourceMapContract(Map("contract_version",1,"render_session_id",session,"source_document_id",doc,"source_path",path,"source_hash",hash,"ranges",ranges))
}
R10(rs,re,ss,se,generated:=false) => Map("render_start",rs,"render_end",re,"source_start",ss,"source_end",se,"generated",generated)

TestF10MappingAndDelete() {
    text := "alpha RED omega"
    ranges := [R10(0,6,0,6),R10(6,9,6,9),R10(9,15,9,15)]
    store:=F10MemoryStore(text), service:=F10EditService(F10FakeSelection("s1",6,9),F10FakeMapProvider(F10Contract(text,ranges)),store,true)
    preview:=service.Preview(), A10(preview.IsOk()), E10(6,preview.Data["source_ranges"][1]["start"]), E10(9,preview.Data["source_ranges"][1]["end"])
    E10("rejected",service.Delete("NO").Status)
    result:=service.Delete("DELETE",preview.Data["preview_token"]), A10(result.IsOk()), E10("alpha  omega",store.Text)
}
TestF10StaleSession() {
    text:="abcdef", contract:=F10Contract(text,[R10(0,6,0,6)],"new-session")
    service:=F10EditService(F10FakeSelection("old-session",1,2),F10FakeMapProvider(contract),F10MemoryStore(text),true)
    E10("rejected",service.Preview().Status)
}
TestF10StaleSourceHash() {
    text:="abcdef", contract:=F10Contract(text,[R10(0,6,0,6)],"s1","d1","memory://doc","BAD-HASH")
    service:=F10EditService(F10FakeSelection("s1",1,2),F10FakeMapProvider(contract),F10MemoryStore(text),true)
    E10("rejected",service.Preview().Status)
}
TestF10GeneratedAndGapUnsupported() {
    text:="abcdef"
    generated:=F10Contract(text,[R10(0,2,0,2),R10(2,3,0,0,true),R10(3,7,2,6)])
    E10("unsupported",F10EditService(F10FakeSelection("s1",1,4),F10FakeMapProvider(generated),F10MemoryStore(text),true).Preview().Status)
    gap:=F10Contract(text,[R10(0,2,0,2),R10(3,7,2,6)])
    E10("unsupported",F10EditService(F10FakeSelection("s1",1,4),F10FakeMapProvider(gap),F10MemoryStore(text),true).Preview().Status)
}
TestF10UnsupportedSelection() {
    text:="abc", service:=F10EditService(F10FakeSelection("s1",0,1,"unsupported"),F10FakeMapProvider(F10Contract(text,[R10(0,3,0,3)])),F10MemoryStore(text),true)
    E10("unsupported",service.Preview().Status)
}
TestF10RollbackFixture() {
    text:="abcdef", store:=F10MemoryStore(text), store.FailDelete:=true
    service:=F10EditService(F10FakeSelection("s1",1,3),F10FakeMapProvider(F10Contract(text,[R10(0,6,0,6)])),store,true)
    result:=service.Delete("DELETE"), E10("failed",result.Status), E10(text,store.Text), E10(1,store.RollbackCount)
}
TestF10PreviewTokenStale() {
    text:="abcdef", selection:=F10FakeSelection("s1",1,2), store:=F10MemoryStore(text), service:=F10EditService(selection,F10FakeMapProvider(F10Contract(text,[R10(0,6,0,6)])),store,true)
    preview:=service.Preview(), selection.Start:=2, selection.Finish:=3
    E10("rejected",service.Delete("DELETE",preview.Data["preview_token"]).Status), E10(text,store.Text)
}
TestF10IniAnsiFixtureEndToEnd() {
    root:=A_Temp "\\ahquiver-f10-" A_TickCount, DirCreate(root)
    sourcePath:=root "\\source.txt", mapPath:=root "\\render.map.ini", selectionPath:=root "\\selection.ini"
    try {
        sourceText:="alpha RED omega"
        f:=FileOpen(sourcePath,"w","UTF-8-RAW"), f.Write(sourceText), f.Close()
        ; A cooperating ANSI renderer displayed: alpha <ESC>[31mRED<ESC>[0m omega.
        ; Render coordinates below count visible cells, not ANSI control bytes.
        IniWrite("1",mapPath,"map","contract_version"), IniWrite("ansi-session",mapPath,"map","render_session_id"), IniWrite("ansi-doc",mapPath,"map","source_document_id"), IniWrite(sourcePath,mapPath,"map","source_path"), IniWrite(F10Fingerprint.Hash(sourceText),mapPath,"map","source_hash"), IniWrite("3",mapPath,"map","range_count")
        IniWrite("0",mapPath,"range.1","render_start"), IniWrite("6",mapPath,"range.1","render_end"), IniWrite("0",mapPath,"range.1","source_start"), IniWrite("6",mapPath,"range.1","source_end"), IniWrite("0",mapPath,"range.1","generated")
        IniWrite("6",mapPath,"range.2","render_start"), IniWrite("9",mapPath,"range.2","render_end"), IniWrite("6",mapPath,"range.2","source_start"), IniWrite("9",mapPath,"range.2","source_end"), IniWrite("0",mapPath,"range.2","generated")
        IniWrite("9",mapPath,"range.3","render_start"), IniWrite("15",mapPath,"range.3","render_end"), IniWrite("9",mapPath,"range.3","source_start"), IniWrite("15",mapPath,"range.3","source_end"), IniWrite("0",mapPath,"range.3","generated")
        IniWrite("ansi-session",selectionPath,"selection","render_session_id"), IniWrite("6",selectionPath,"selection","render_start"), IniWrite("9",selectionPath,"selection","render_end")
        service:=F10EditService(F10IniSelectionAdapter(selectionPath),F10IniMapProvider(mapPath),F10FileSourceStore(),true)
        preview:=service.Preview(), A10(preview.IsOk())
        result:=service.Delete("DELETE",preview.Data["preview_token"]), A10(result.IsOk()), E10("alpha  omega",FileRead(sourcePath)), A10(FileExist(sourcePath ".ahquiver.bak"))
    } finally {
        try DirDelete(root,1)
    }
}

passed:=0,failed:=0
tests:=[TestF10MappingAndDelete,TestF10StaleSession,TestF10StaleSourceHash,TestF10GeneratedAndGapUnsupported,TestF10UnsupportedSelection,TestF10RollbackFixture,TestF10PreviewTokenStale,TestF10IniAnsiFixtureEndToEnd]
for fn in tests {
    try {
        fn.Call()
        passed += 1
        FileAppend("PASS " fn.Name "`n","*")
    } catch as testError {
        failed += 1
        FileAppend("FAIL " fn.Name ": " testError.Message "`n","*")
    }
}
FileAppend("RESULT passed=" passed " failed=" failed "`n","*")
ExitApp(failed?1:0)
A10(v,m:="expected true") {
    if !v
        throw Error(m)
}
E10(e,a,m:="") {
    if e != a
        throw Error((m!=""?m ": ":"") "expected=" e " actual=" a)
}
