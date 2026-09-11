{ SPDX-License-Identifier: MIT }
program memtest;
uses dwedtype,dwedutil,dwedrcv,strs,unredo,saveinfo,scr,dwedmenu,dwedcmd,dwedhl;
var output:text; checks:longint; ctx:TEditorContext;
    original,previous,p:PFileContext; info:TSaveRecord;
    before_heap:longint; error,i,count:integer; s:string; screen_probe,list_probe:boolean;
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
procedure list_memory;
type PLink=^pointer;
var blocks:array[0..511] of pointer; n:integer;
    tail,spare,small:pointer; tree:pfast_jmp_list;
    fragmented,total:longint; line:EditorStr;
    procedure exhaust;
    begin
        FillChar(blocks,sizeof(blocks),0); n:=0; tail:=nil;
        while (MaxAvail>=1024) and (n<512) do begin
                GetMem(blocks[n],1024); inc(n);
        end;
        check(n<512,'list probe exhausts heap within block bound');
        while MaxAvail>=8 do begin
                GetMem(small,8); PLink(small)^:=tail; tail:=small;
        end;
        check(MaxAvail<12,'list probe leaves no usable menu block');
    end;
    procedure release_heap;
    var j:integer;
    begin
        while tail<>nil do begin small:=PLink(tail)^; FreeMem(tail,8); tail:=small end;
        for j:=0 to n-1 do FreeMem(blocks[j],1024);
    end;
begin
        s:='procedure first;'; line:=strs.create(nil,ctx.current^.rline,s);
        s:='procedure second;'; line:=strs.create(nil,line,s);
        ctx.current^.st:=SRC_PAS;
        before_heap:=MemAvail;
        exhaust; fragmented:=MemAvail;
        go_win_list(ctx);
        check(MemAvail=fragmented,'failed windows list releases temporary data');
        release_heap; preserved;
        tree:=create_fast_jmp_list(ctx);
        check((tree<>nil) and (tree^.next<>nil),'source list contains both procedures');
        exhaust;
        check(fast_jmp(ctx,tree)=SCRU_NONE,'source menu refuses exhausted heap');
        release_heap; preserved;
        GetMem(spare,128); exhaust; FreeMem(spare,128);
        check(MaxAvail>=sizeof(fast_jmp_list),'partial list can allocate its first node');
        check(MaxAvail<2*sizeof(fast_jmp_list),'partial list cannot hold both nodes');
        fragmented:=MemAvail;
        tree:=create_fast_jmp_list(ctx);
        check(tree=nil,'partial source list is not published');
        check(MemAvail=fragmented,'partial source list releases all nodes');
        release_heap; preserved;
        { A successful rebuild proves refusal did not leave stale list state. }
        tree:=create_fast_jmp_list(ctx);
        check((tree<>nil) and (tree^.next<>nil),'source list retries after release');
        while tree<>nil do begin spare:=tree; tree:=tree^.next; FreeMem(spare,sizeof(fast_jmp_list)) end;
        preserved;
        tree:=nil; total:=0; s:='';
        for n:=1 to 80 do s:=s+'x';
        while total<=65535 do begin
                check(MaxAvail>=sizeof(fast_jmp_list),'oversized source-list fixture fits');
                GetMem(spare,sizeof(fast_jmp_list));
                pfast_jmp_list(spare)^.text:=s;
                pfast_jmp_list(spare)^.line:=1;
                pfast_jmp_list(spare)^.next:=tree; tree:=spare;
                inc(total,length(s)+1);
        end;
        check(fast_jmp(ctx,tree)=SCRU_NONE,'source menu rejects size before word wrap');
        preserved;
end;
procedure screen_memory;
var blocks:array[0..511] of pointer; n,j,k:integer; free_fragmented:longint;
begin
        FillChar(blocks,sizeof(blocks),0);
        scr.print(0,0,$07,'root'); check(scr.try_push,'save root screen');
        scr.print(0,0,$07,'outer'); check(scr.try_push,'save nested screen');
        scr.print(0,0,$07,'inner');
        n:=0;
        while (MaxAvail>=1024) and (n<512) do begin
                GetMem(blocks[n],1024); inc(n);
        end;
        check(n<512,'exhausted available heap within allocation bound');
        j:=0;
        while j<n do begin FreeMem(blocks[j],1024); blocks[j]:=nil; inc(j,2) end;
        check(MemAvail>scr.getwidth*scr.getheight*2,'fragmented heap has enough total bytes');
        check(MaxAvail<scr.getwidth*scr.getheight*2,'no contiguous screen buffer fits');
        free_fragmented:=MemAvail;
        for k:=1 to 3 do begin
                check(not scr.try_push,'fragmented screen save refuses allocation');
                check(scr.screen[0]='i','failed save preserves current screen');
                check(MemAvail=free_fragmented,'failed screen save leaks no heap');
        end;
        check(choose_menu(ctx,0)=CMD_NONE,'menu cancels when its snapshot cannot fit');
        check(scr.screen[0]='i','allocation-free notice restores previous row');
        check(MemAvail=free_fragmented,'cancelled menu leaks no heap');
        scr.pop; check(scr.screen[0]='o','failed saves leave nested snapshot intact');
        scr.pop; check(scr.screen[0]='r','failed saves leave root snapshot intact');
        for j:=0 to n-1 do if blocks[j]<>nil then FreeMem(blocks[j],1024);
        preserved;
        check(scr.try_push,'screen save retries after memory release'); scr.pop;
        preserved;
end;
begin
        { FPC parses and retains argv on the first ParamCount/ParamStr call. }
        screen_probe:=System.ParamStr(1)='/SCREEN';
        list_probe:=System.ParamStr(1)='/LIST';
        System.Assign(output,'A:\MEM.LOG'); System.Rewrite(output); checks:=0;
        FillChar(ctx,sizeof(ctx),0); ctx.config.width:=80; ctx.config.height:=24;
        ctx.config.tab_size:=8; strs.init(MT_DOS);
        check(new_file(ctx,'C:\ORIGINAL.TXT')=0,'create original');
        original:=ctx.current; s:='unsaved text';
        ctx.current^.rline:=strs.put(ctx.current^.rline,s);
        ctx.current^.cline:=ctx.current^.rline; ctx.current^.scrline:=ctx.current^.rline;
        load_ed(ctx); ctx.current^.chg:=true;
        before_heap:=MemAvail;
        if screen_probe then screen_memory;
        if list_probe then list_memory;
        for i:=1 to 3 do begin
                load_file(ctx,'C:\HUGE.TXT',error,nil);
                check(error=8,'oversized ordinary load reports memory exhaustion'); preserved;
                FillChar(info,sizeof(info),0); info.destination:='C:\ORIGINAL.TXT';
                error:=recover_document(ctx,info,'C:\HUGE.TXT');
                check(error=8,'oversized recovery reports memory exhaustion'); preserved;
                error:=recover_record(ctx,'C:\$ER0000.REC',info,'C:\HUGE.TXT');
                check(error=8,'failed associated recovery releases origin'); preserved;
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
                error:=recover_record(ctx,'C:\$ER0000.REC',info,'C:\SAMPLE.TXT');
                check(error=8,'recovery origin refuses exhausted heap');
                load_file(ctx,'C:\SAMPLE.TXT',error,nil);
                check(error=8,'document header allocation refuses exhausted heap');
                check((ctx.current=previous) and (ctx.all=previous),'load header failure preserves list');
                check(MemAvail=before_heap,'header refusal has no heap leak');
        end;
        while ctx.all<>original do begin
                p:=ctx.all; ctx.all:=p^.next; strs.free(p^.rline);
                undo_done(p^.history);
                if p^.recovery<>nil then FreeMem(p^.recovery,sizeof(TRecoveryOrigin));
                FreeMem(p,sizeof(TFileContext));
        end;
        ctx.current:=original;
        check(new_file(ctx,'')=0,'new document succeeds after memory release');
        load_file(ctx,'C:\SAMPLE.TXT',error,nil);
        check(error=0,'load succeeds after memory release');
        check(ctx.current^.editor.line='DWED_MARKER','successful retry loads exact first line');
        check(ctx.current^.recovery=nil,'ordinary document has no recovery allocation');
        s:='DWED_MARKER'+#13#10+'second line'+#13#10;
        info.payload_size:=length(s); info.payload_crc:=crc_update($FFFFFFFF,s[1],length(s)) xor $FFFFFFFF;
        check(recover_record(ctx,'C:\$ER0000.REC',info,'C:\SAMPLE.TXT')=0,'associated recovery retries after release');
        check(ctx.current^.recovery<>nil,'recovery owns its origin');
        check(ctx.current^.recovery^.name='C:\$ER0000.REC','origin has journal path');
        check(ctx.current^.recovery^.info.payload_crc=info.payload_crc,'origin retains payload fingerprint');
        while ctx.all<>nil do begin
                p:=ctx.all; ctx.all:=p^.next; strs.free(p^.rline);
                undo_done(p^.history);
                if p^.recovery<>nil then FreeMem(p^.recovery,sizeof(TRecoveryOrigin));
                FreeMem(p,sizeof(TFileContext));
        end;
        writeln(output,'PASS ',checks,' assertions'); close(output);
        System.Assign(output,'A:\MEM.OK'); System.Rewrite(output);
        writeln(output,'MEMORY PASS'); close(output);
end.
