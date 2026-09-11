{ SPDX-License-Identifier: MIT }
program dbappend;
uses cachehook,dos,system2,dbb,dbm;
const length=18000;
type TBig=array[0..65534] of byte;
var fixed:DBBFile; chunks:DBMFile; output:text; checks:longint;
    payload,actual:array[0..length-1] of byte; backend,kind,i,error:integer;
    root,spare,candidate,records,free_head:longint; name:string;
    old21,old60:pointer; fault,hits,seen,handle:word; ok,cached:boolean;
    held:array[0..63] of pointer; sizes:array[0..63] of word; held_count:integer;
    baseline:longint; amount:word;
    big,copybuf:^TBig; at:word; src,dst:^byte;
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers;
begin
        if bx=handle then begin
                if hi(ax)=$40 then inc(seen);
                if ((fault=1) and (hi(ax)=$40)) or ((fault=3) and (hi(ax)=$42)) or
                   ((fault=5) and (hi(ax)=$40) and (seen>=2)) or
                   ((fault=6) and (hi(ax)=$3F)) then begin
                        ax:=5; flags:=flags or 1; inc(hits); exit;
                end;
                if (fault=4) and (hi(ax)=$40) then begin
                        ax:=0; flags:=flags and $FFFE; inc(hits); exit;
                end;
        end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        if (fault=2) and (hi(ax)=$40) and (bx=handle) and (r.cx>0) then begin
                dec(r.cx); inc(hits);
        end;
        intr($60,r);
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp; flags:=r.flags;
end;
procedure check(condition:boolean; message:string);
begin
        inc(checks);
        if not condition then begin
                SetIntVec($21,old21); SetIntVec($60,old60); restore_cache_hook;
                System.Writeln(output,'FAIL backend ',backend,' kind ',kind,' fault ',fault,
                        ' assertion ',checks,' error ',error,' ',message);
                System.Close(output); Halt(1);
        end;
end;
procedure close_database;
begin
        if backend=1 then begin dbb_Close(fixed); error:=fixed.f.ioresult end
        else begin dbm_Close(chunks); error:=chunks.f.ioresult end;
        check(error=0,'close database');
end;
procedure reset_database;
begin
        deny_cache_allocation(not cached);
        if backend=1 then begin dbb_Reset(fixed,name,length); error:=fixed.f.ioresult; handle:=fixed.f.f end
        else begin dbm_Reset(chunks,name,8192); error:=chunks.f.ioresult; handle:=chunks.f.f end;
        deny_cache_allocation(false); check(error=0,'reset database');
end;
procedure fixture;
begin
        fault:=0; deny_cache_allocation(not cached);
        FillChar(payload,sizeof(payload),$A5);
        if backend=1 then begin
                name:='C:\APPEND.DBB'; dbb_ReWrite(fixed,name,length);
                root:=dbb_Add(fixed,payload); spare:=dbb_Add(fixed,payload); dbb_Free(fixed,spare);
                dbb_SetRoot(fixed,root); records:=fixed.header.records; free_head:=fixed.header.next;
        end else begin
                name:='C:\APPEND.DBM'; dbm_ReWrite(chunks,name,8192);
                root:=dbm_Add(chunks,payload,length); spare:=dbm_Add(chunks,payload,length); dbm_Free(chunks,spare);
                dbm_SetRoot(chunks,root); records:=chunks.header.records; free_head:=chunks.header.next;
        end;
        deny_cache_allocation(false); check((root=1) and (free_head<>0),'fixture has old record and free list');
        close_database; reset_database;
        for i:=0 to length-1 do payload[i]:=(longint(i)*17+11) mod 256;
        candidate:=-1234;
end;
procedure header_unchanged;
begin
        if backend=1 then begin
                check(fixed.header.records=records,'fixed count unchanged');
                check(fixed.header.next=free_head,'fixed free list unchanged');
                check(fixed.header.root=root,'fixed root unchanged');
        end else begin
                check(chunks.header.records=records,'chain count unchanged');
                check(chunks.header.next=free_head,'chain free list unchanged');
                check(chunks.header.root=root,'chain root unchanged');
        end;
end;
function append_record:boolean;
begin
{$IFDEF LEGACY_APPEND}
        if backend=1 then begin candidate:=dbb_Add(fixed,payload); append_record:=fixed.f.ioresult=0 end
        else begin candidate:=dbm_Add(chunks,payload,length); append_record:=chunks.f.ioresult=0 end;
{$ELSE}
        if backend=1 then append_record:=dbb_TryAppend(fixed,payload,candidate)
        else append_record:=dbm_TryAppend(chunks,payload,length,candidate);
{$ENDIF}
        if backend=1 then error:=fixed.f.ioresult else error:=chunks.f.ioresult;
end;
procedure read_record(rec:longint; old:boolean);
begin
        if backend=1 then ok:=dbb_TryGet(fixed,rec,actual)
        else ok:=dbm_TryGet(chunks,rec,actual,length);
        check(ok,'record readable');
        for i:=0 to length-1 do
                if old then check(actual[i]=$A5,'old payload unchanged')
                else check(actual[i]=payload[i],'complete new payload');
end;
procedure retry_and_reopen;
begin
        read_record(root,true);
        check(append_record,'native append retry'); check(candidate=records+1,'append avoids free list');
        read_record(root,true); read_record(candidate,false);
        if backend=1 then begin
                check(fixed.header.next=free_head,'append preserves fixed free list');
                check(fixed.header.records=records+1,'fixed publication count');
        end else begin
                check(chunks.header.next=free_head,'append preserves chain free list');
                check(chunks.header.records=records+3,'chain publication count');
                check(dbm_Size(chunks,candidate)=length,'new chain exact size');
        end;
        close_database; reset_database; read_record(root,true); read_record(candidate,false); close_database;
end;
begin
        System.Assign(output,'A:\DBAPPEND.LOG'); System.Rewrite(output);
        GetIntVec($21,old21); GetIntVec($60,old60); SetIntVec($60,old21);
        FillChar(fixed,sizeof(fixed),0); FillChar(chunks,sizeof(chunks),0);
        for backend:=1 to 2 do begin
                for kind:=1 to 6 do begin
                        System.Writeln(output,'backend ',backend,' fault ',kind); System.Flush(output);
                        fixture; fault:=kind; hits:=0; seen:=0;
                        SetIntVec($21,@intercept); ok:=append_record; SetIntVec($21,old21);
                        check(hits>0,'append fault exercised');
                        check(candidate=-1234,'failed append publishes no record ID');
                        check(not ok,'append failure reported');
                        if kind in [3,6] then check(error=100,'page read or seek error preserved')
                        else check(error=101,'write or seek error preserved');
                        header_unchanged;
                        SetIntVec($21,@intercept); ok:=append_record; SetIntVec($21,old21);
                        check((not ok) and (candidate=-1234),'persistent failure remains unpublished'); header_unchanged;
                        retry_and_reopen;
                end;
                { A closed/reopened failed append retains only the old published prefix. }
                kind:=7; fixture; fault:=5; hits:=0; seen:=0;
                SetIntVec($21,@intercept); ok:=append_record; SetIntVec($21,old21);
                check((not ok) and (hits>0),'partial tail failure'); close_database; reset_database;
                header_unchanged; retry_and_reopen;
                kind:=8; fixture; held_count:=0;
                while (MaxAvail>=16384) and (held_count<64) do begin
                        sizes[held_count]:=16384; GetMem(held[held_count],16384); inc(held_count);
                end;
                baseline:=MemAvail; ok:=append_record;
                check((not ok) and (error=8) and (candidate=-1234),'allocation refusal remains unpublished');
                check(MemAvail=baseline,'failed allocation leaks no heap'); header_unchanged;
                while held_count>0 do begin dec(held_count); FreeMem(held[held_count],sizes[held_count]) end;
                retry_and_reopen;
        end;
{$IFNDEF LEGACY_APPEND}
        for backend:=1 to 2 do begin
                kind:=11; fixture;
                if backend=1 then fixed.header.next:=2147483647 else chunks.header.next:=2147483647;
                check((not append_record) and (error=1019) and (candidate=-1234),'invalid free-list head rejected');
                if backend=1 then fixed.header.next:=free_head else chunks.header.next:=free_head;
                if backend=1 then fixed.header.records:=2147483647 else chunks.header.records:=2147483647;
                check((not append_record) and (error=1019) and (candidate=-1234),'invalid extent rejected before arithmetic');
                if backend=1 then fixed.header.records:=records else chunks.header.records:=records;
                header_unchanged; read_record(root,true); close_database;
                check((not append_record) and (error=103) and (candidate=-1234),'closed append refused');
        end;
        backend:=2; kind:=9; fixture; held_count:=0;
        while (MaxAvail>=36000) and (held_count<64) do begin
                sizes[held_count]:=16384; GetMem(held[held_count],16384); inc(held_count);
        end;
        if MaxAvail>22000 then begin
                amount:=MaxAvail-22000; sizes[held_count]:=amount; GetMem(held[held_count],amount); inc(held_count);
        end;
        check((MaxAvail>=length) and (MaxAvail<26000),'heap permits payload staging only');
        baseline:=MemAvail; ok:=append_record;
        check((not ok) and (error=8) and (candidate=-1234),'block staging refusal');
        check(MemAvail=baseline,'payload staging released on second allocation refusal'); header_unchanged;
        while held_count>0 do begin dec(held_count); FreeMem(held[held_count],sizes[held_count]) end;
        retry_and_reopen;
        kind:=10; fixture;
        check(dbm_TryAppend(chunks,payload,0,candidate) and (candidate=0),'empty append'); header_unchanged;
        GetMem(big,65535); GetMem(copybuf,65535);
        for at:=0 to 65534 do begin
                src:=Ptr(Seg(big^)+((LONGINT(Ofs(big^))+at) SHR 4),(LONGINT(Ofs(big^))+at) AND 15);
                src^:=byte(at mod 251);
        end;
        check(dbm_TryAppend(chunks,big^,65535,candidate),'maximum WORD payload append');
        check(dbm_Size(chunks,candidate)=65535,'maximum payload length');
        check(dbm_TryGet(chunks,candidate,copybuf^,65535),'maximum payload read');
        for at:=0 to 65534 do begin
                dst:=Ptr(Seg(copybuf^)+((LONGINT(Ofs(copybuf^))+at) SHR 4),(LONGINT(Ofs(copybuf^))+at) AND 15);
                if dst^<>byte(at mod 251) then System.Writeln(output,'mismatch at ',at,' actual ',dst^);
                check(dst^=byte(at mod 251),'maximum payload exact');
        end;
        read_record(root,true); close_database;
        dbb_ReWrite(fixed,'C:\WIDE.DBB',65535);
        check(dbb_IsOpen(fixed),'largest fixed record initialized');
        check(dbb_TryAppend(fixed,big^,candidate),'largest fixed record append');
        dbb_SetRoot(fixed,candidate); dbb_Close(fixed); dbb_Reset(fixed,'C:\WIDE.DBB',65535);
        FillFarBytes(copybuf^,65535,$A5);
        check(dbb_TryGet(fixed,candidate,copybuf^),'largest fixed record reopened');
        for at:=0 to 65534 do begin
                dst:=Ptr(Seg(copybuf^)+((LONGINT(Ofs(copybuf^))+at) SHR 4),(LONGINT(Ofs(copybuf^))+at) AND 15);
                check(dst^=byte(at mod 251),'largest fixed record exact');
        end;
        dbb_Close(fixed);
        dbm_ReWrite(chunks,'C:\WIDE.DBM',65526);
        check(dbm_IsOpen(chunks) and (chunks.header.size=65532),'largest chained block initialized');
        check(dbm_TryAppend(chunks,big^,65535,candidate),'maximum input with largest blocks');
        check(chunks.header.records=2,'large-block chain publication');
        dbm_SetRoot(chunks,candidate); dbm_Close(chunks); dbm_Reset(chunks,'C:\WIDE.DBM',65526);
        FillFarBytes(copybuf^,65535,$A5);
        check(dbm_TryGet(chunks,candidate,copybuf^,65535),'large-block chain reopened');
        for at:=0 to 65534 do begin
                dst:=Ptr(Seg(copybuf^)+((LONGINT(Ofs(copybuf^))+at) SHR 4),(LONGINT(Ofs(copybuf^))+at) AND 15);
                check(dst^=byte(at mod 251),'large-block payload exact');
        end;
        dbm_Close(chunks); FreeMem(big,65535); FreeMem(copybuf,65535);
        if available then begin
                cached:=true;
                for backend:=1 to 2 do begin
                        kind:=12; fixture; at:=transfer_hits;
                        arm_transfer(2,true); ok:=append_record;
                        check(transfer_hits>at,'real XMS dirty-cache read failed');
                        check((not ok) and (error=100) and (candidate=-1234),'cache failure leaves append unpublished');
                        header_unchanged; retry_and_reopen;
                end;
        end;
{$ENDIF}
        SetIntVec($60,old60); restore_cache_hook;
        System.Writeln(output,'PASS ',checks,' assertions'); System.Close(output);
        System.Assign(output,'A:\DBAPPEND.OK'); System.Rewrite(output);
        System.Writeln(output,'RECORD APPEND PASS'); System.Close(output);
end.
