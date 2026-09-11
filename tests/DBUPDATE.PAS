{ SPDX-License-Identifier: MIT }
program dbupdate;
uses cachehook,dos,system2,dbb,excache;
const length=18000;
type TWide=array[0..65534] of byte;
var f:DBBFile; output:text; checks:longint; kind,i,error:integer;
    old21,old60:pointer; handle,fault,hits,reads,writes,seeks:word;
    original,replacement,actual:array[0..length-1] of byte;
    name:string; saved:DBB_HDR; snapshot:pointer; baseline:longint;
    ok,cached:boolean; wide,wide_actual:^TWide; byteptr:^byte; index:word;
    tiny,observed:array[0..17] of byte; rec:longint;
    held:array[0..63] of pointer; sizes:array[0..63] of word;
    held_count:integer; desired:longint; amount:word;
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers; reject:boolean;
begin
        reject:=false;
        if bx=handle then begin
                if hi(ax)=$3F then inc(reads);
                if hi(ax)=$40 then inc(writes);
                if hi(ax)=$42 then inc(seeks);
                reject:=((fault in [1,9]) and (hi(ax)=$40)) or
                        ((fault=4) and (hi(ax)=$40) and (writes>=2)) or
                        ((fault=5) and (hi(ax)=$42) and (seeks>=3)) or
                        ((fault=6) and (hi(ax)=$3F) and (reads>=3)) or
                        ((fault=7) and (hi(ax)=$3F)) or
                        ((fault=9) and (hi(ax)=$3E));
                if (fault=3) and (hi(ax)=$40) then begin ax:=0; flags:=flags and $FFFE; inc(hits); exit end;
        end;
        if (fault=10) and ((ax=$7141) or (hi(ax)=$41)) then reject:=true;
        if reject then begin ax:=5; flags:=flags or 1; inc(hits); exit end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        if (bx=handle) and (fault=2) and (hi(ax)=$40) and (r.cx>0) then begin dec(r.cx); inc(hits) end;
        if (bx=handle) and (fault=8) and (hi(ax)=$3F) and (r.cx>127) then begin r.cx:=127; inc(hits) end;
        intr($60,r);
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp; flags:=r.flags;
end;
procedure check(condition:boolean; message:string);
begin
        inc(checks);
        if not condition then begin
                SetIntVec($21,old21); SetIntVec($60,old60); restore_cache_hook;
                System.Writeln(output,'FAIL kind ',kind,' fault ',fault,' assertion ',checks,' error ',f.f.ioresult,' ',message);
                System.Close(output); Halt(1);
        end;
end;
function pending:boolean;
begin
{$IFDEF LEGACY_UPDATE} pending:=false;
{$ELSE} pending:=dbb_PendingWrite(f); {$ENDIF}
end;
function update_record:boolean;
begin
{$IFDEF LEGACY_UPDATE} dbb_Put(f,2,replacement); Flush(f.f); update_record:=f.f.ioresult=0;
{$ELSE} update_record:=dbb_TryPut(f,2,replacement); {$ENDIF}
end;
procedure arm;
begin hits:=0; reads:=0; writes:=0; seeks:=0; SetIntVec($21,@intercept) end;
procedure disarm;
begin SetIntVec($21,old21) end;
procedure header_unchanged;
begin
        check((f.header.records=saved.records) and (f.header.next=saved.next) and
              (f.header.root=saved.root) and (f.header.size=saved.size),'published header unchanged');
end;
procedure expect_record(number:longint; value:byte; new_data:boolean);
begin
        check(dbb_TryGet(f,number,actual),'record readable');
        for i:=0 to length-1 do
                if new_data then check(actual[i]=replacement[i],'new record exact')
                else check(actual[i]=value,'old record exact');
end;
procedure reset_database;
begin
        deny_cache_allocation(not cached); dbb_Reset(f,name,length); deny_cache_allocation(false);
        check(dbb_IsOpen(f) and (f.f.ioresult=0),'database reopened'); handle:=f.f.f;
end;
procedure fixture(temporary:boolean);
begin
        fault:=0; deny_cache_allocation(not cached);
        name:='C:\UPDATE.DBB';
        if temporary then dbb_ReWriteTemp(f,length) else dbb_ReWrite(f,name,length);
        deny_cache_allocation(false); check(dbb_IsOpen(f),'database initialized');
        FillChar(original,sizeof(original),$11); check(dbb_Add(f,original)=1,'first record');
        FillChar(original,sizeof(original),$A5); check(dbb_Add(f,original)=2,'target record');
        FillChar(original,sizeof(original),$33); check(dbb_Add(f,original)=3,'third record');
        check(dbb_Add(f,original)=4,'free record'); dbb_Free(f,4); dbb_SetRoot(f,1);
        saved:=f.header;
        if temporary then begin
                Flush(f.f); check(f.f.ioresult=0,'temporary fixture flushed'); name:=f.f.filename;
                Seek(f.f,0); check(f.f.ioresult=0,'temporary fixture at first page'); handle:=f.f.f;
        end else begin dbb_Close(f); check(not dbb_IsOpen(f),'fixture closed'); reset_database end;
        for i:=0 to length-1 do replacement[i]:=(longint(i)*19+7) mod 256;
end;
procedure close_and_verify(new_data:boolean);
begin
        dbb_Close(f); check(not dbb_IsOpen(f) and not pending,'close releases update owner');
        reset_database; header_unchanged;
        expect_record(1,$11,false); expect_record(2,$A5,new_data); expect_record(3,$33,false);
        dbb_Close(f);
end;
{$IFNDEF LEGACY_UPDATE}
procedure blocked_mutations;
begin
        snapshot:=f.rollback_data; fault:=1; arm;
        check(not dbb_RetryRollback(f),'persistent rollback refusal');
        check(not update_record,'new checked update blocked');
        rec:=-777; check(not dbb_TryAppend(f,replacement,rec),'checked append blocked');
        check(rec=-777,'blocked append output unchanged');
        check(dbb_Add(f,replacement)=0,'legacy allocation blocked');
        dbb_Put(f,3,replacement); check(f.f.ioresult<>0,'legacy replacement blocked');
        dbb_Free(f,1); check(f.f.ioresult<>0,'free blocked');
        dbb_SetRoot(f,3); check(f.f.ioresult<>0,'root publication blocked');
        dbb_Close(f); check(dbb_IsOpen(f),'failed rollback prevents close');
        header_unchanged;
        check(pending and (f.rollback_data=snapshot) and (f.rollback_rec=2) and
              (f.rollback_size=length),'before-image owner retained');
        expect_record(2,$A5,false);
        dbb_Reset(f,'C:\OTHER.DBB',length); check(f.f.ioresult=BFILE_PENDING,'reset cannot overwrite pending owner');
        dbb_ReWrite(f,'C:\OTHER.DBB',length); check(f.f.ioresult=BFILE_PENDING,'rewrite cannot overwrite pending owner');
        dbb_ReWriteTemp(f,length); check(f.f.ioresult=BFILE_PENDING,'temporary init cannot overwrite pending owner');
        disarm; header_unchanged; check(f.rollback_data=snapshot,'initialization leaves before-image owned');
end;
procedure release_heap;
begin while held_count>0 do begin dec(held_count); FreeMem(held[held_count],sizes[held_count]) end end;
procedure limit_heap(target:longint);
begin
        held_count:=0;
        while (MaxAvail>=target+16384) and (held_count<64) do begin
                sizes[held_count]:=16384; GetMem(held[held_count],16384); inc(held_count);
        end;
        if MaxAvail>target then begin
                amount:=MaxAvail-target; sizes[held_count]:=amount; GetMem(held[held_count],amount); inc(held_count);
        end;
end;
{$ENDIF}
begin
        System.Assign(output,'A:\DBUPDATE.LOG'); System.Rewrite(output);
        GetIntVec($21,old21); GetIntVec($60,old60); SetIntVec($60,old21);
        FillChar(f,sizeof(f),0);
        for kind:=1 to 8 do begin
                System.Writeln(output,'update fault ',kind); System.Flush(output);
                fixture(false); baseline:=MemAvail; fault:=kind; arm; ok:=update_record; error:=f.f.ioresult; disarm;
                check(hits>0,'fault reached backing DOS call');
                if kind=8 then begin
                        check(ok and (error=0) and not pending,'short reads complete update'); close_and_verify(true);
                end else begin
                        check(not ok,'update failure reported');
                        if kind in [5,6,7] then check(error=100,'read or seek failure preserved')
                        else check(error=101,'write failure preserved');
                        header_unchanged; expect_record(2,$A5,false);
{$IFNDEF LEGACY_UPDATE}
                        if kind=7 then check(not pending,'pre-image read refusal needs no rollback')
                        else begin
                                check(pending,'failed update retains before-image'); blocked_mutations;
                                check(dbb_RetryRollback(f),'rollback retry succeeds'); check(not pending,'rollback releases before-image');
                        end;
                        check(MemAvail=baseline,'temporary update staging released');
                        expect_record(1,$11,false); expect_record(3,$33,false);
                        check(update_record and not pending,'new update succeeds after rollback');
{$ENDIF}
                        close_and_verify(true);
                end;
        end;
{$IFNDEF LEGACY_UPDATE}
        kind:=9; fixture(false); fault:=1; arm; ok:=update_record; disarm;
        check((not ok) and pending,'failed update for close retry'); close_and_verify(false);
        for kind:=10 to 12 do begin
                fixture(false);
                case kind of 10:desired:=12000; 11:desired:=26000; 12:desired:=44000 end;
                limit_heap(desired); baseline:=MemAvail; ok:=update_record;
                check((not ok) and (f.f.ioresult=8) and not pending,'pre-write allocation refusal');
                check(MemAvail=baseline,'pre-write allocation failure releases staging'); header_unchanged;
                release_heap; close_and_verify(false);
        end;
        kind:=13; fixture(false); fault:=1; arm; ok:=update_record; disarm;
        check((not ok) and pending,'rollback allocation fixture'); snapshot:=f.rollback_data;
        limit_heap(12000); check(not dbb_RetryRollback(f),'rollback scratch allocation refused');
        check((f.f.ioresult=8) and (f.rollback_data=snapshot),'allocation refusal retains rollback owner');
        expect_record(2,$A5,false); release_heap;
        check(dbb_RetryRollback(f),'rollback after releasing heap'); close_and_verify(false);
        kind:=14; baseline:=MemAvail; fixture(true); fault:=9; arm; ok:=update_record;
        check((not ok) and pending,'temporary failed update'); snapshot:=f.rollback_data;
        dbb_Discard(f); disarm;
        check(dbb_IsOpen(f) and pending and (f.rollback_data=snapshot),'refused discard close retains before-image');
        fault:=10; arm; dbb_Discard(f); disarm;
        check((not dbb_IsOpen(f)) and f.f.delete_pending and not pending,'closed discard retains deletion only');
        check(f.f.ioresult=5,'discard deletion error');
        dbb_Discard(f); check(not f.f.delete_pending,'discard deletion retry');
        check(not FileExists(name),'temporary database removed'); check(MemAvail=baseline,'discard releases all heap owners');
        kind:=15; fixture(false); dbb_Discard(f); check((f.f.ioresult=5) and dbb_IsOpen(f),'persistent database cannot be discarded');
        check(not dbb_TryPut(f,0,replacement),'null record update refused');
        check((f.f.ioresult=DBB_INVALID) and not pending,'invalid record has no rollback owner'); close_and_verify(false);
        if available then begin
                kind:=16; cached:=true; fixture(false);
                check(f.f.wcache<>nil,'real XMS write cache available');
                excache_Free(PEXCACHE(f.f.rcache)); f.f.rcache:=nil;
                handle:=transfer_hits; arm_transfer(2,true); ok:=update_record;
                check(transfer_hits>handle,'dirty XMS page retrieval failed');
                check((not ok) and (f.f.ioresult=100) and pending,'XMS failure retains before-image');
                expect_record(2,$A5,false); check(dbb_RetryRollback(f),'XMS rollback retry'); close_and_verify(false);
        end;
        kind:=17; cached:=false; baseline:=MemAvail;
        GetMem(wide,65535); GetMem(wide_actual,65535); FillFarBytes(wide^,65535,$A5);
        deny_cache_allocation(true); dbb_ReWrite(f,'C:\WIDE.DBB',65535); deny_cache_allocation(false);
        check(dbb_TryAppend(f,wide^,rec) and (rec=1),'maximum record fixture');
        handle:=f.f.f; FillFarBytes(wide^,65535,$39); fault:=4; arm;
        ok:=dbb_TryPut(f,1,wide^); disarm;
        check((not ok) and (hits>0) and (f.f.ioresult=101) and pending and (f.rollback_size=65535),'maximum failed update owns before-image');
        check(dbb_TryGet(f,1,wide_actual^),'maximum before-image read');
        for index:=0 to 65534 do begin
                byteptr:=Ptr(Seg(wide_actual^)+((LONGINT(Ofs(wide_actual^))+index) SHR 4),
                             (LONGINT(Ofs(wide_actual^))+index) AND 15);
                check(byteptr^=$A5,'maximum old record exact');
        end;
        check(dbb_RetryRollback(f),'maximum rollback'); check(dbb_TryPut(f,1,wide^),'maximum update retry');
        dbb_Close(f); deny_cache_allocation(true); dbb_Reset(f,'C:\WIDE.DBB',65535); deny_cache_allocation(false);
        check(dbb_TryGet(f,1,wide_actual^),'maximum updated record reopens');
        for index:=0 to 65534 do begin
                byteptr:=Ptr(Seg(wide_actual^)+((LONGINT(Ofs(wide_actual^))+index) SHR 4),
                             (LONGINT(Ofs(wide_actual^))+index) AND 15);
                check(byteptr^=$39,'maximum new record exact');
        end;
        dbb_Close(f); FreeMem(wide,65535); FreeMem(wide_actual,65535);
        check(MemAvail=baseline,'maximum update releases heap owners');
        kind:=18; deny_cache_allocation(true); dbb_ReWrite(f,'C:\TINY.DBB',18); deny_cache_allocation(false);
        for rec:=1 to 911 do begin FillChar(tiny,sizeof(tiny),byte(rec mod 251)); check(dbb_Add(f,tiny)=rec,'tiny index fixture') end;
        dbb_Close(f); deny_cache_allocation(true); dbb_Reset(f,'C:\TINY.DBB',18); deny_cache_allocation(false);
        handle:=f.f.f; FillChar(tiny,sizeof(tiny),$77); fault:=1; arm;
        ok:=dbb_TryPut(f,910,tiny); disarm;
        check((not ok) and (hits>0) and (f.f.ioresult=101) and pending,'index-sized record straddles buffered pages');
        check(dbb_TryGet(f,910,observed),'tiny before-image readable');
        for i:=0 to 17 do check(observed[i]=byte(910 mod 251),'tiny before-image exact');
        check(dbb_RetryRollback(f),'tiny rollback'); check(dbb_TryPut(f,910,tiny),'tiny update retry');
        dbb_Close(f); deny_cache_allocation(true); dbb_Reset(f,'C:\TINY.DBB',18); deny_cache_allocation(false);
        for rec:=909 to 911 do begin
                check(dbb_TryGet(f,rec,observed),'tiny index and neighbors readable');
                for i:=0 to 17 do
                        if rec=910 then check(observed[i]=$77,'tiny new index exact')
                        else check(observed[i]=byte(rec mod 251),'tiny neighbor unchanged');
        end;
        dbb_Close(f);
{$ENDIF}
        SetIntVec($60,old60); restore_cache_hook;
        System.Writeln(output,'PASS ',checks,' assertions'); System.Close(output);
        System.Assign(output,'A:\DBUPDATE.OK'); System.Rewrite(output);
        System.Writeln(output,'RECORD UPDATE PASS'); System.Close(output);
end.
