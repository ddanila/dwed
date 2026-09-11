{ SPDX-License-Identifier: MIT }
program memtest;
uses dwedtype,dwedutil,dwedrcv,strs,unredo,saveinfo;
var output:text; checks:longint; ctx:TEditorContext;
    original,previous,p:PFileContext; info:TSaveRecord;
    before_heap:longint; error,i,count:integer; s:string;
procedure check(ok:boolean; message:string);
begin
        inc(checks);
        if not ok then begin writeln(output,'FAIL ',checks,' ',message); close(output); halt(1) end;
end;
procedure preserved;
begin
        check(ctx.current=original,'current document retained');
        check(ctx.all=original,'document list retained');
        check(ctx.current^.chg,'dirty state retained');
        check(ctx.current^.editor.line='unsaved text','working line retained');
        check(not ctx.file_reader.opened,'input handle closed');
        check(MemAvail=before_heap,'failed load releases all allocations');
end;
begin
        System.Assign(output,'A:\MEM.LOG'); System.Rewrite(output); checks:=0;
        FillChar(ctx,sizeof(ctx),0); ctx.config.width:=80; ctx.config.height:=24;
        ctx.config.tab_size:=8; strs.init(MT_DOS);
        check(new_file(ctx,'C:\ORIGINAL.TXT')=0,'create original');
        original:=ctx.current; s:='unsaved text';
        ctx.current^.rline:=strs.put(ctx.current^.rline,s);
        ctx.current^.cline:=ctx.current^.rline; ctx.current^.scrline:=ctx.current^.rline;
        load_ed(ctx); ctx.current^.chg:=true;
        before_heap:=MemAvail;
        for i:=1 to 3 do begin
                load_file(ctx,'C:\HUGE.TXT',error,nil);
                check(error=8,'oversized ordinary load reports memory exhaustion'); preserved;
                FillChar(info,sizeof(info),0); info.destination:='C:\ORIGINAL.TXT';
                error:=recover_document(ctx,info,'C:\HUGE.TXT');
                check(error=8,'oversized recovery reports memory exhaustion'); preserved;
        end;
        count:=0;
        repeat
                previous:=ctx.current; before_heap:=MemAvail;
                error:=new_file(ctx,'');
                if error=0 then inc(count);
        until error<>0;
        check(count>0,'filled heap with real documents');
        check(error=8,'new document refuses exhausted heap');
        check((ctx.current=previous) and (ctx.all=previous),'new failure preserves list');
        check(MemAvail=before_heap,'new failure has no heap leak');
        for i:=1 to 3 do begin
                check(new_file(ctx,'')=8,'repeat new refusal');
                load_file(ctx,'C:\SAMPLE.TXT',error,nil);
                check(error=8,'document header allocation refuses exhausted heap');
                check((ctx.current=previous) and (ctx.all=previous),'load header failure preserves list');
                check(MemAvail=before_heap,'header refusal has no heap leak');
        end;
        while ctx.all<>original do begin
                p:=ctx.all; ctx.all:=p^.next; strs.free(p^.rline);
                undo_done(p^.history); FreeMem(p,sizeof(TFileContext));
        end;
        ctx.current:=original;
        check(new_file(ctx,'')=0,'new document succeeds after memory release');
        load_file(ctx,'C:\SAMPLE.TXT',error,nil);
        check(error=0,'load succeeds after memory release');
        check(ctx.current^.editor.line='DWED_MARKER','successful retry loads exact first line');
        while ctx.all<>nil do begin
                p:=ctx.all; ctx.all:=p^.next; strs.free(p^.rline);
                undo_done(p^.history); FreeMem(p,sizeof(TFileContext));
        end;
        writeln(output,'PASS ',checks,' assertions'); close(output);
        System.Assign(output,'A:\MEM.OK'); System.Rewrite(output);
        writeln(output,'MEMORY PASS'); close(output);
end.
