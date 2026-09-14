#Requires AutoHotkey v2.0

class F10Fingerprint {
    static Hash(text) {
        h1 := 2166136261
        h2 := 5381
        Loop Parse text {
            code := Ord(A_LoopField)
            h1 := Mod(h1 * 16777619 + code, 4294967291)
            h2 := Mod(h2 * 33 + code, 4294967279)
        }
        return Format("{:08X}-{:08X}-{}", h1, h2, StrLen(text))
    }
}
class F10UnsupportedSelectionAdapter {
    Capture() {
        return AQResult.Unsupported("No cooperating rendered-selection adapter is configured")
    }
}
class F10IniSelectionAdapter {
    __New(path) { this.Path := path }
    Capture() {
        if this.Path = "" || !FileExist(this.Path)
            return AQResult.Unsupported("Selection snapshot is unavailable")
        try {
            sessionId := Trim(IniRead(this.Path,"selection","render_session_id",""))
            startText := Trim(IniRead(this.Path,"selection","render_start",""))
            endText := Trim(IniRead(this.Path,"selection","render_end",""))
            if sessionId="" || !RegExMatch(startText,"^\d+$") || !RegExMatch(endText,"^\d+$")
                return AQResult.Invalid("Selection snapshot is malformed")
            renderStart:=startText+0, renderEnd:=endText+0
            if renderEnd<=renderStart
                return AQResult.Invalid("Selection range must be non-empty")
            return AQResult.Ok("Selection captured",Map("render_session_id",sessionId,"render_start",renderStart,"render_end",renderEnd))
        } catch as selectionError {
            return AQResult.Failed("Selection snapshot read failed: " selectionError.Message)
        }
    }
}
class F10SourceMapContract {
    __New(data) {
        this.ContractVersion:=data["contract_version"], this.RenderSessionId:=data["render_session_id"], this.SourceDocumentId:=data["source_document_id"], this.SourcePath:=data["source_path"], this.SourceHash:=data["source_hash"], this.Ranges:=data["ranges"]
    }
    Resolve(renderStart,renderEnd) {
        if renderEnd<=renderStart
            return AQResult.Invalid("Rendered selection must be non-empty")
        ranges:=this._SortedRanges(), cursor:=renderStart, sourceRanges:=[]
        for item in ranges {
            rStart:=item["render_start"], rEnd:=item["render_end"]
            if rEnd<=cursor || rStart>=renderEnd
                continue
            overlapStart:=Max(cursor,rStart), overlapEnd:=Min(renderEnd,rEnd)
            if overlapStart!=cursor
                return AQResult.Unsupported("Selection crosses an unmapped rendered region")
            if item["generated"]
                return AQResult.Unsupported("Selection includes renderer-generated content with no source range")
            renderLength:=rEnd-rStart, sourceLength:=item["source_end"]-item["source_start"]
            if renderLength!=sourceLength
                return AQResult.Unsupported("Partial selection of a non-1:1 map segment is unsupported; renderer must emit finer ranges")
            sourceRanges.Push(Map("start",item["source_start"]+overlapStart-rStart,"end",item["source_start"]+overlapEnd-rStart))
            cursor:=overlapEnd
            if cursor>=renderEnd
                break
        }
        if cursor!=renderEnd
            return AQResult.Unsupported("Selection is not fully covered by the cooperating source map")
        return AQResult.Ok("Rendered selection resolved",Map("source_ranges",this._MergeAdjacent(sourceRanges)))
    }
    _SortedRanges() {
        items:=[]
        for item in this.Ranges
            items.Push(item)
        Loop items.Length {
            i:=A_Index, j:=i+1
            while j<=items.Length {
                if items[j]["render_start"]<items[i]["render_start"] {
                    tmp:=items[i], items[i]:=items[j], items[j]:=tmp
                }
                j+=1
            }
        }
        return items
    }
    _MergeAdjacent(items) {
        output:=[]
        for item in items {
            if output.Length && output[output.Length]["end"]=item["start"]
                output[output.Length]["end"]:=item["end"]
            else
                output.Push(Map("start",item["start"],"end",item["end"]))
        }
        return output
    }
}
class F10IniMapProvider {
    __New(path) { this.Path:=path }
    Load() {
        if this.Path="" || !FileExist(this.Path)
            return AQResult.Unsupported("Cooperating renderer source map is unavailable")
        try {
            versionText:=Trim(IniRead(this.Path,"map","contract_version","")), sessionId:=Trim(IniRead(this.Path,"map","render_session_id","")), documentId:=Trim(IniRead(this.Path,"map","source_document_id","")), sourcePath:=IniRead(this.Path,"map","source_path",""), sourceHash:=Trim(IniRead(this.Path,"map","source_hash","")), countText:=Trim(IniRead(this.Path,"map","range_count",""))
            if versionText!="1"
                return AQResult.Unsupported("Unsupported F10 source-map contract version")
            if sessionId="" || documentId="" || sourcePath="" || sourceHash="" || !RegExMatch(countText,"^\d+$")
                return AQResult.Invalid("Source map header is malformed")
            ranges:=[]
            Loop countText+0 {
                section:="range." A_Index, rStart:=this._UInt(section,"render_start"), rEnd:=this._UInt(section,"render_end"), generated:=IniRead(this.Path,section,"generated","0")="1"
                if rStart<0 || rEnd<=rStart
                    return AQResult.Invalid("Source map rendered range is malformed")
                if generated {
                    sourceStart:=0, sourceFinish:=0
                } else {
                    sourceStart:=this._UInt(section,"source_start"), sourceFinish:=this._UInt(section,"source_end")
                    if sourceStart<0 || sourceFinish<=sourceStart
                        return AQResult.Invalid("Source map source range is malformed")
                }
                ranges.Push(Map("render_start",rStart,"render_end",rEnd,"source_start",sourceStart,"source_end",sourceFinish,"generated",generated))
            }
            contract:=F10SourceMapContract(Map("contract_version",1,"render_session_id",sessionId,"source_document_id",documentId,"source_path",sourcePath,"source_hash",sourceHash,"ranges",ranges))
            return AQResult.Ok("Source map loaded",Map("contract",contract))
        } catch as mapError {
            return AQResult.Failed("Source map read failed: " mapError.Message)
        }
    }
    _UInt(section,key) {
        raw:=Trim(IniRead(this.Path,section,key,""))
        return RegExMatch(raw,"^\d+$") ? raw+0 : -1
    }
}
class F10FileSourceStore {
    Snapshot(path) {
        if path="" || !FileExist(path)
            return AQResult.Invalid("Mapped source document does not exist")
        try {
            text:=FileRead(path)
            return AQResult.Ok("Source snapshot read",Map("text",text,"hash",F10Fingerprint.Hash(text),"length",StrLen(text)))
        } catch as readError {
            return AQResult.Failed("Source read failed: " readError.Message)
        }
    }
    DeleteRanges(path,expectedHash,ranges) {
        current:=this.Snapshot(path)
        if !current.IsOk()
            return current
        if current.Data["hash"]!=expectedHash
            return AQResult.Rejected("Source changed since renderer produced the map")
        normalized:=this._ValidateRanges(ranges,current.Data["length"])
        if !normalized.IsOk()
            return normalized
        text:=current.Data["text"], sorted:=normalized.Data["ranges"], i:=sorted.Length
        while i>=1 {
            item:=sorted[i]
            text:=SubStr(text,1,item["start"]) SubStr(text,item["end"]+1)
            i-=1
        }
        backupPath:=path ".ahquiver.bak", tempPath:=path ".ahquiver.tmp." A_TickCount
        try {
            FileCopy(path,backupPath,1)
            tempFile:=FileOpen(tempPath,"w","UTF-8-RAW")
            if !IsObject(tempFile)
                throw Error("Could not create temporary source file")
            tempFile.Write(text), tempFile.Close(), FileMove(tempPath,path,1)
        } catch as writeError {
            try {
                if FileExist(tempPath)
                    FileDelete(tempPath)
                if FileExist(backupPath)
                    FileCopy(backupPath,path,1)
            }
            return AQResult.Failed("Transactional source edit failed and rollback was attempted: " writeError.Message)
        }
        return AQResult.Ok("Source ranges deleted",Map("backup_path",backupPath,"old_hash",expectedHash,"new_hash",F10Fingerprint.Hash(text),"deleted_ranges",sorted.Length))
    }
    _ValidateRanges(ranges,length) {
        items:=[]
        for item in ranges {
            start:=item["start"], finish:=item["end"]
            if start<0 || finish<=start || finish>length
                return AQResult.Invalid("Mapped source range is outside the current document")
            items.Push(Map("start",start,"end",finish))
        }
        Loop items.Length {
            i:=A_Index, j:=i+1
            while j<=items.Length {
                if items[j]["start"]<items[i]["start"] {
                    tmp:=items[i], items[i]:=items[j], items[j]:=tmp
                }
                j+=1
            }
        }
        Loop Max(items.Length-1,0) {
            if items[A_Index]["end"]>items[A_Index+1]["start"]
                return AQResult.Invalid("Mapped source ranges overlap")
        }
        return AQResult.Ok("Ranges valid",Map("ranges",items))
    }
}
class F10EditService {
    __New(selectionAdapter,mapProvider,sourceStore,requireConfirmation:=true) {
        this.SelectionAdapter:=selectionAdapter, this.MapProvider:=mapProvider, this.SourceStore:=sourceStore, this.RequireConfirmation:=requireConfirmation
    }
    Preview() {
        selection:=this.SelectionAdapter.Capture()
        if !selection.IsOk()
            return selection
        loaded:=this.MapProvider.Load()
        if !loaded.IsOk()
            return loaded
        contract:=loaded.Data["contract"]
        if selection.Data["render_session_id"]!=contract.RenderSessionId
            return AQResult.Rejected("Rendered selection belongs to a stale/different render session")
        snapshot:=this.SourceStore.Snapshot(contract.SourcePath)
        if !snapshot.IsOk()
            return snapshot
        if snapshot.Data["hash"]!=contract.SourceHash
            return AQResult.Rejected("Mapped source version/hash is stale")
        resolved:=contract.Resolve(selection.Data["render_start"],selection.Data["render_end"])
        if !resolved.IsOk()
            return resolved
        token:=this._Token(contract,selection.Data,resolved.Data["source_ranges"])
        return AQResult.Ok("Source edit preview ready",Map("preview_token",token,"render_session_id",contract.RenderSessionId,"source_document_id",contract.SourceDocumentId,"source_path",contract.SourcePath,"source_hash",contract.SourceHash,"render_start",selection.Data["render_start"],"render_end",selection.Data["render_end"],"source_ranges",resolved.Data["source_ranges"]))
    }
    Delete(confirmText:="",previewToken:="") {
        preview:=this.Preview()
        if !preview.IsOk()
            return preview
        if this.RequireConfirmation && confirmText!="DELETE"
            return AQResult.Rejected("Destructive source edit requires confirm=DELETE")
        if previewToken!="" && previewToken!=preview.Data["preview_token"]
            return AQResult.Rejected("Preview token is stale")
        return this.SourceStore.DeleteRanges(preview.Data["source_path"],preview.Data["source_hash"],preview.Data["source_ranges"])
    }
    _Token(contract,selection,ranges) {
        serial:=contract.RenderSessionId "|" contract.SourceDocumentId "|" contract.SourceHash "|" selection["render_start"] "|" selection["render_end"]
        for item in ranges
            serial.="|" item["start"] "-" item["end"]
        return F10Fingerprint.Hash(serial)
    }
}
class F10SourceMapEditModule {
    Id:="F10"
    __New(selectionAdapter:=unset,mapProvider:=unset,sourceStore:=unset) {
        this.InjectedSelection:=IsSet(selectionAdapter)?selectionAdapter:"", this.InjectedMapProvider:=IsSet(mapProvider)?mapProvider:"", this.InjectedSourceStore:=IsSet(sourceStore)?sourceStore:"", this.Service:="", this.RegisteredActions:=[]
    }
    Init(app) {
        this.App:=app
        if IsObject(this.InjectedSelection)
            selection:=this.InjectedSelection
        else {
            selectionPath:=Trim(app.Config.Get("F10","selection_file",""))
            selection:=selectionPath="" ? F10UnsupportedSelectionAdapter() : F10IniSelectionAdapter(selectionPath)
        }
        if IsObject(this.InjectedMapProvider)
            provider:=this.InjectedMapProvider
        else {
            mapPath:=Trim(app.Config.Get("F10","map_file",""))
            provider:=F10IniMapProvider(mapPath)
        }
        store:=IsObject(this.InjectedSourceStore)?this.InjectedSourceStore:F10FileSourceStore(), requireConfirmation:=app.Config.GetBool("F10","require_confirmation",true)
        this.Service:=F10EditService(selection,provider,store,requireConfirmation)
        this._Register("terminal.source_edit.preview",ObjBindMethod(this,"ActionPreview"),"Preview an experimental cooperating source-map edit","S0")
        this._Register("terminal.source_edit.delete",ObjBindMethod(this,"ActionDelete"),"Delete source ranges resolved by a cooperating source map","S2")
        this._Register("terminal.source_edit.status",ObjBindMethod(this,"ActionStatus"),"Inspect F10 experimental bridge state","S0")
        status:=(selection is F10UnsupportedSelectionAdapter)?"unsupported":"degraded", detail:=status="unsupported"?"no cooperating selection adapter configured":"cooperating files configured; validity checked on each action"
        app.Capabilities.Set("terminal.source_map_edit",status,detail)
        return AQResult.Ok("F10 initialized")
    }
    Teardown(app) {
        for id in this.RegisteredActions
            app.Actions.Unregister(id)
        this.RegisteredActions:=[]
        app.Capabilities.Set("terminal.source_map_edit","unknown","F10 disabled")
        return AQResult.Ok("F10 disabled")
    }
    ActionPreview(params) {
        actionResult:=this.Service.Preview()
        if actionResult.IsOk()
            this.App.Capabilities.Set("terminal.source_map_edit","supported","current cooperating selection/map/source version validated")
        else if actionResult.Status="unsupported"
            this.App.Capabilities.Set("terminal.source_map_edit","unsupported",actionResult.Message)
        else
            this.App.Capabilities.Set("terminal.source_map_edit","degraded",actionResult.Message)
        return actionResult
    }
    ActionDelete(params) {
        confirmText:=params.Has("confirm")?params["confirm"]:"", token:=params.Has("preview_token")?params["preview_token"]:""
        return this.Service.Delete(confirmText,token)
    }
    ActionStatus(params) {
        cap:=this.App.Capabilities.Get("terminal.source_map_edit")
        return AQResult.Ok("F10 status",Map("experimental",true,"capability",cap["status"],"detail",cap["detail"]))
    }
    _Register(id,handler,description,safetyClass) {
        this.App.Actions.Register(id,handler,description,safetyClass), this.RegisteredActions.Push(id)
    }
}
