{ SPDX-License-Identifier: MIT }
program strput;
uses cachehook,dos,strs,dwedtype,dwedutil,system2,dwedhndl,dwedcmd;
const lines=1100; target_number=910;
      commands:array[1..9] of TEditorCommand=(CMD_SAVE,CMD_SAVE_AS,CMD_SAVE_ALL,CMD_CLOSE,CMD_EXIT,
          CMD_NEW,CMD_OPEN,CMD_WINDOWS,CMD_NEXT_WINDOW);
var output:text; checks:longint; backend,kind,i,j,error:integer;
    old21,old60,old16:pointer; collect:boolean; handles:word; source_handles:array[1..2] of word;
    selected,fault,hits,reads,writes,payload_writes,payload_closes:word;
    root,last,target,added,n,p,other:EditorStr; body,oldbody,actual:string;
    ctx:TEditorContext; filectx,snapshot,secondctx,second_snapshot:TFileContext; ok:boolean; baseline:longint;
    held:array[0..63] of pointer; held_count:integer; amount:word; command_index,command_fault,result_code,key_reads:integer;
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers; service:byte; matching,reject:boolean;
begin
        service:=hi(ax); matching:=bx=source_handles[selected]; reject:=false;
        if (service=$40) and (bx=source_handles[1]) then inc(payload_writes);
        if (service=$3E) and (bx=source_handles[1]) then inc(payload_closes);
        if matching then begin
                if service=$3F then inc(reads);
                if service=$40 then inc(writes);
                reject:=((fault in [1,3,10]) and (service=$40)) or
                        ((fault=5) and (service=$42)) or
                        ((fault in [6,7]) and (service=$3F)) or
                        ((fault=9) and (service=$40) and (writes>=2)) or
                        ((fault=11) and (service=$3E));
        end;
        if (fault=12) and ((ax=$7141) or (service=$41)) then reject:=true;
        if reject then begin ax:=5; flags:=flags or 1; inc(hits); exit end;
        { These kernels do not implement LFN calls. Pascal Intr must not
          accidentally turn the incoming carry bit into LFN success. }
        if service=$71 then begin ax:=$7100; flags:=flags or 1; exit end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        if matching and (fault in [2,4]) and (service=$40) and (r.cx>0) then begin dec(r.cx); inc(hits) end;
        if matching and (fault=8) and (service=$3F) and (r.cx>127) then begin r.cx:=127; inc(hits) end;
        intr($60,r);
        if collect and (service=$5B) and (r.flags and 1=0) then begin
                inc(handles); if handles<=2 then source_handles[handles]:=r.ax;
        end;
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp; flags:=r.flags;
end;
{ Error dialogs drain pending keys, then read one acknowledgement. }
procedure acknowledge(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
begin
        if hi(ax) in [$00,$10,$20] then begin ax:=$1C0D; inc(key_reads) end
        else flags:=flags or $40;
end;
procedure check(condition:boolean; message:string);
begin
        inc(checks);
        if not condition then begin
                SetIntVec($21,old21); SetIntVec($60,old60); SetIntVec($16,old16); restore_cache_hook;
                System.Writeln(output,'FAIL backend ',backend,' kind ',kind,' fault ',fault,
                               ' assertion ',checks,' error ',error,' ',message);
                System.Close(output); Halt(1);
        end;
end;
procedure arm;
begin hits:=0; reads:=0; writes:=0; payload_writes:=0; payload_closes:=0; SetIntVec($21,@intercept) end;
procedure disarm;
begin SetIntVec($21,old21) end;
function checked_commit:boolean;
begin
{$IFDEF LEGACY_LINE} commit(ctx); checked_commit:=true;
{$ELSE} checked_commit:=try_commit(ctx,error); {$ENDIF}
end;
procedure prepare_context;
begin
        FillChar(filectx,sizeof(filectx),0); ctx.current:=@filectx;
        filectx.rline:=root; filectx.cline:=target; filectx.scrline:=target;
        filectx.editor.line:=body; filectx.editor.chg:=true;
        filectx.editor.x:=3; filectx.editor.sel_x:=2; filectx.editor.sel_row:=909;
        filectx.editor.selection:=true; filectx.total:=lines;
        filectx.format.newline:=#13#10; snapshot:=filectx;
end;
procedure unchanged;
begin
        for i:=0 to sizeof(filectx)-1 do
                check(Mem[Seg(filectx):Ofs(filectx)+i]=Mem[Seg(snapshot):Ofs(snapshot)+i],'failed commit preserves editor state');
end;
procedure expect_target(expected:string);
begin
        check(strs.try_read(target,actual,n,p,error),'target remains readable');
        check(actual=expected,'target text exact');
        check((longint(n)=911) and (longint(p)=909),'target links preserved');
        check(strs.get_num(target)=target_number,'target number preserved');
end;
procedure evict;
{ Replacements append at the tail, which can share the last fixture's page.
  Reading the root evicts that payload page even after repeated replacements. }
begin check(strs.try_read(root,actual,n,p,error),'root line readable') end;
procedure neighbors;
begin
        other:=strs.find_num(root,909); check(strs.try_read(other,actual,n,p,error),'previous line readable');
        check((length(actual)=255) and (actual[1]=chr(65+909 mod 26)) and (n=target),'previous line retained');
        other:=strs.find_num(root,911); check(strs.try_read(other,actual,n,p,error),'next line readable');
        check((length(actual)=255) and (actual[1]=chr(65+911 mod 26)) and (p=target),'next line retained');
end;
begin
        System.Assign(output,'A:\STRPUT.LOG'); System.Rewrite(output);
        GetIntVec($16,old16); GetIntVec($21,old21); GetIntVec($60,old60); SetIntVec($60,old21);
        FillChar(ctx,sizeof(ctx),0); selected:=1;
        for backend:=1 to 2 do begin
                System.Writeln(output,'backend ',backend,' fixtures'); System.Flush(output);
                baseline:=MemAvail; fault:=0; handles:=0; collect:=true;
                deny_cache_allocation(true); SetIntVec($21,@intercept);
                if backend=1 then strs.init(MT_SWAP) else strs.init(MT_SXMS);
                disarm; deny_cache_allocation(false); collect:=false;
                check(handles=2,'capture index and payload handles'); root:=nil; last:=nil;
                for i:=1 to lines do begin
                        body[0]:=chr(255); FillChar(body[1],255,65+i mod 26);
                        added:=strs.create(nil,last,body); check(added<>nil,'fixture line');
                        if root=nil then root:=added; last:=added;
                        if i=target_number then begin target:=added; oldbody:=body end;
                end;
                check(strs.renum(root)=lines,'fixture line numbers');
                for kind:=1 to 10 do begin
                        System.Writeln(output,'backend ',backend,' commit case ',kind); System.Flush(output);
{$IFNDEF LEGACY_LINE}
                        check(strs.retry_update(error),'settle previous update');
                        check(strs.try_put(target,oldbody,error),'restore target fixture');
{$ENDIF}
                        evict; body:='replacement text'; if kind=10 then body:=''; prepare_context;
                        selected:=2; if kind in [1,2,7,8] then selected:=1;
                        fault:=kind; arm; ok:=checked_commit; disarm;
                        check(hits>0,'commit fault exercised');
                        if kind=8 then begin
                                check(ok and (error=0),'short reads complete commit'); expect_target(body);
                        end else begin
                                unchanged;
{$IFNDEF LEGACY_LINE}
                                check(not ok,'commit reports failure');
                                if kind in [5,6,7] then check(error=100,'read failure propagated')
                                else check(error=101,'write failure propagated');
{$ENDIF}
                                expect_target(oldbody); neighbors;
{$IFNDEF LEGACY_LINE}
                                if kind in [3,4,9,10] then begin
                                        check(strs.pending_update,'index rollback retained');
                                        selected:=2; fault:=3; arm;
                                        other:=root; actual:='blocked replacement';
                                        check(not strs.try_put(other,actual,error),'other line cannot bypass pending rollback');
                                        check((other=root) and (payload_writes=0),'blocked replacement publishes no payload');
                                        check(not strs.retry_update(error),'persistent rollback refusal');
                                        disarm; expect_target(oldbody);
                                end;
                                check(checked_commit,'native commit retry'); expect_target(body);
{$ENDIF}
                        end;
                        check(filectx.chg and not filectx.editor.chg,'successful commit publishes dirty flags');
                        check((filectx.cline=target) and (filectx.rline=root) and (filectx.scrline=target),'successful commit retains pointers');
                        check(filectx.editor.selection and (filectx.editor.x=3),'selection and cursor retained');
                        neighbors;
                end;
{$IFNDEF LEGACY_LINE}
                for command_fault:=1 to 2 do
                for command_index:=1 to 9 do begin
                        kind:=20+command_index;
                        check(strs.retry_update(error),'settle previous command rollback');
                        check(strs.try_put(target,oldbody,error),'restore command fixture'); evict;
                        body:='unsaved command text'; prepare_context; ctx.all:=@filectx;
                        FillChar(secondctx,sizeof(secondctx),0); secondctx.rline:=last;
                        secondctx.cline:=last; secondctx.scrline:=last; second_snapshot:=secondctx;
                        filectx.next:=@secondctx; snapshot:=filectx;
                        selected:=1; fault:=1;
                        if command_fault=2 then begin selected:=2; fault:=4 end;
                        key_reads:=0; SetIntVec($16,@acknowledge); arm;
                        result_code:=execute_command(ctx,commands[command_index]); disarm; SetIntVec($16,old16);
                        check((hits>0) and (key_reads=1),'command reports commit refusal in one error dialog');
                        check(result_code=SCRU_FULL,'failed command returns to editor');
                        check((ctx.current=@filectx) and (ctx.all=@filectx),'failed command retains document ownership');
                        unchanged; expect_target(oldbody);
                        for i:=0 to sizeof(secondctx)-1 do
                                check(Mem[Seg(secondctx):Ofs(secondctx)+i]=Mem[Seg(second_snapshot):Ofs(second_snapshot)+i],
                                      'failed command preserves other document');
                        if command_fault=2 then check(strs.pending_update,'failed command retains index rollback');
                end;
                { A successful retry publishes the pending line before switching. }
                result_code:=execute_command(ctx,CMD_NEXT_WINDOW);
                check((result_code=SCRU_FULL) and (ctx.current=@secondctx),'window switch retries after failure');
                check(filectx.chg and not filectx.editor.chg,'window switch commits source line');
                expect_target(body); ctx.current:=@filectx;
                kind:=11; check(strs.retry_update(error),'settle before discard test');
                check(strs.try_put(target,oldbody,error),'discard fixture'); evict;
                body:='unsaved replacement'; prepare_context; selected:=2; fault:=3; arm;
                ok:=checked_commit; disarm; check((not ok) and strs.pending_update,'pending commit for discard'); unchanged;
                fault:=11; arm; ok:=strs.try_done(error); disarm;
                check((not ok) and (error=5) and (payload_closes=0),'refused index discard retains payload owner');
                expect_target(oldbody);
                fault:=12; arm; ok:=strs.try_done(error); disarm;
                check((not ok) and (error=5),'discard retains pending deletion');
                check(strs.try_done(error),'discard cleanup retry');
                check(MemAvail=baseline,'discard releases both stores and rollback data');
                kind:=13; fault:=0; handles:=0; collect:=true; deny_cache_allocation(true); arm;
                if backend=1 then strs.init(MT_SWAP) else strs.init(MT_SXMS);
                disarm; deny_cache_allocation(false); collect:=false;
                check(handles=2,'capture dirty discard handles'); last:=nil;
                for i:=1 to 70 do last:=strs.create(nil,last,oldbody);
                selected:=1; fault:=1; arm; ok:=strs.try_done(error); disarm;
                check(ok and (error=0) and (payload_writes=0),'dirty payload discard needs no writeback');
                check(MemAvail=baseline,'dirty discard releases both stores');
{$ELSE}
                strs.done;
{$ENDIF}
        end;
{$IFNDEF LEGACY_LINE}
        backend:=0; kind:=12; strs.init(MT_DOS); oldbody:='old'; root:=strs.create(nil,nil,oldbody);
        body:='neighbor'; last:=strs.create(nil,root,body); target:=root;
        check(strs.renum(root)=2,'DOS fixture'); body[0]:=chr(200); FillChar(body[1],200,ord('N')); prepare_context;
        held_count:=0;
        while (MaxAvail>=17000) and (held_count<64) do begin GetMem(held[held_count],16384); inc(held_count) end;
        amount:=MaxAvail-512; GetMem(other,amount);
        check(not checked_commit,'DOS growth allocation refusal'); check(error=8,'DOS allocation status'); unchanged;
        for command_index:=1 to 9 do begin
                key_reads:=0; SetIntVec($16,@acknowledge);
                result_code:=execute_command(ctx,commands[command_index]); SetIntVec($16,old16);
                check((result_code=SCRU_FULL) and (key_reads=1),'command reports DOS growth allocation refusal');
                check((ctx.current=@filectx) and (ctx.all=@filectx),'DOS command retains document ownership'); unchanged;
        end;
        FreeMem(other,amount); while held_count>0 do begin dec(held_count); FreeMem(held[held_count],16384) end;
        check(checked_commit,'DOS growth retry'); target:=filectx.cline; root:=filectx.rline;
        check((root=target) and (filectx.scrline=target),'DOS relocation updates root and scroll aliases');
        check(strs.try_read(target,actual,n,p,error) and (actual=body) and (n=last) and (p=nil),'DOS grown line exact');
        check(strs.go_prev(last)=target,'DOS neighbor points to relocated line');
        strs.free(root); check(strs.try_done(error),'DOS store cleanup');
{$ENDIF}
        SetIntVec($60,old60); restore_cache_hook;
        System.Writeln(output,'PASS ',checks,' assertions'); System.Close(output);
        System.Assign(output,'A:\STRPUT.OK'); System.Rewrite(output);
        System.Writeln(output,'LINE UPDATE PASS'); System.Close(output);
end.
