{ SPDX-License-Identifier: MIT }
program dbread;
uses dos,system2,dbb,dbm;
const length=18000;
var fixed:DBBFile; chunks:DBMFile; output:text; checks:longint;
    payload,actual:array[0..length-1] of byte;
    backend,kind,i,error:integer; root:longint; name:string;
    fault,hits,handle,writes:word; old21,old60:pointer;
    held:array[0..63] of pointer; held_count:integer;
    ok:boolean; raw:file; count:word;
    link:packed record next:longint; size:word end;
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers;
begin
        if bx=handle then begin
                if hi(ax)=$40 then inc(writes);
                if ((fault=1) and (hi(ax)=$3F)) or
                   ((fault=2) and (hi(ax)=$42)) or
                   ((fault=5) and (hi(ax)=$3F) and (hits>=3)) then begin
                        ax:=5; flags:=flags or 1; inc(hits); exit;
                end;
                if (fault=3) and (hi(ax)=$3F) then begin
                        ax:=0; flags:=flags and $FFFE; inc(hits); exit;
                end;
        end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        if (fault in [4,5]) and (hi(ax)=$3F) and (bx=handle) and (r.cx>7) then begin
                r.cx:=7; inc(hits);
        end;
        intr($60,r);
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp; flags:=r.flags;
end;
procedure check(condition:boolean; message:string);
begin
        inc(checks);
        if not condition then begin
                SetIntVec($21,old21); SetIntVec($60,old60);
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
        if backend=1 then begin dbb_Reset(fixed,name,length); error:=fixed.f.ioresult; handle:=fixed.f.f end
        else begin dbm_Reset(chunks,name,8192); error:=chunks.f.ioresult; handle:=chunks.f.f end;
        check(error=0,'reset database');
end;
function read_record:boolean;
begin
{$IFDEF LEGACY_READ}
        if backend=1 then begin dbb_Get(fixed,root,actual); read_record:=fixed.f.ioresult=0 end
        else begin dbm_Get(chunks,root,actual,length); read_record:=chunks.f.ioresult=0 end;
{$ELSE}
        if backend=1 then read_record:=dbb_TryGet(fixed,root,actual)
        else read_record:=dbm_TryGet(chunks,root,actual,length);
{$ENDIF}
        if backend=1 then error:=fixed.f.ioresult else error:=chunks.f.ioresult;
end;
procedure unchanged;
begin for i:=0 to length-1 do check(actual[i]=$A5,'destination unchanged') end;
procedure exact;
begin for i:=0 to length-1 do check(actual[i]=payload[i],'exact record bytes') end;
begin
        System.Assign(output,'A:\DBREAD.LOG'); System.Rewrite(output);
        GetIntVec($21,old21); GetIntVec($60,old60); SetIntVec($60,old21);
        FillChar(fixed,sizeof(fixed),0); FillChar(chunks,sizeof(chunks),0);
        for i:=0 to length-1 do payload[i]:=(longint(i)*17+11) mod 256;
        for backend:=1 to 2 do begin
                if backend=1 then begin
                        name:='C:\READ.DBB'; dbb_ReWrite(fixed,name,length);
                        root:=dbb_Add(fixed,payload); dbb_SetRoot(fixed,root);
                        error:=fixed.f.ioresult;
                end else begin
                        name:='C:\READ.DBM'; dbm_ReWrite(chunks,name,8192);
                        root:=dbm_Add(chunks,payload,length); dbm_SetRoot(chunks,root);
                        error:=chunks.f.ioresult;
                end;
                check((error=0) and (root=1),'create crossing-page fixture'); close_database;
                for fault:=1 to 5 do begin
                        System.Writeln(output,'phase backend ',backend,' kind ',kind,' fault ',fault); System.Flush(output);
                        reset_database; FillChar(actual,sizeof(actual),$A5); hits:=0; writes:=0;
                        SetIntVec($21,@intercept); ok:=read_record; SetIntVec($21,old21);
                        check(hits>0,'DOS fault exercised after buffered prefix');
                        check(writes=0,'reads issue no DOS writes');
                        if fault=4 then begin check(ok and (error=0),'positive short reads complete'); exact end
                        else begin
                                check((not ok) and (error=100),'read failure reported'); unchanged;
                                check(read_record,'retry succeeds'); exact;
                        end;
                        close_database;
                end;
                fault:=0; reset_database;
                if backend=1 then begin
                        Seek(fixed.f,49152); check(fixed.f.ioresult=0,'seek beyond fixed EOF');
                        check(FileSize(fixed.f)=length+16,'empty page does not extend fixed file');
                end else begin
                        Seek(chunks.f,49152); check(chunks.f.ioresult=0,'seek beyond chained EOF');
                        check(FileSize(chunks.f)=32800,'empty page does not extend chained file');
                end;
                check(read_record,'read after seeking beyond EOF'); exact;
                held_count:=0;
                while (MaxAvail>=16384) and (held_count<64) do begin
                        GetMem(held[held_count],16384); inc(held_count);
                end;
                FillChar(actual,sizeof(actual),$A5); ok:=read_record;
                check((not ok) and (error=8),'staging allocation refusal'); unchanged;
                while held_count>0 do begin dec(held_count); FreeMem(held[held_count],16384) end;
                check(read_record,'retry after releasing heap'); exact;
                close_database;
        end;
{$IFNDEF LEGACY_READ}
        backend:=1; name:='C:\READ.DBB'; reset_database;
        for kind:=1 to 3 do begin
                case kind of 1:root:=0; 2:root:=-1; 3:root:=2 end;
                FillChar(actual,sizeof(actual),$A5);
                check(not read_record,'invalid fixed record rejected'); check(error=DBB_INVALID,'invalid fixed status'); unchanged;
        end;
        close_database;
        backend:=2; name:='C:\READ.DBM';
        { Fresh fixtures for each corruption, including a bad tail on a prefix read. }
        for kind:=1 to 7 do begin
                System.Writeln(output,'chain case ',kind); System.Flush(output);
                dbm_ReWrite(chunks,name,8192); root:=dbm_Add(chunks,payload,length);
                dbm_SetRoot(chunks,root); close_database;
                System.Assign(raw,name); System.Reset(raw,1);
                System.Seek(raw,8200); System.BlockRead(raw,link,sizeof(link),count);
                check(count=sizeof(link),'read first link');
                case kind of
                1:link.next:=root;
                2:link.next:=-1;
                3:link.next:=99;
                4:link.size:=0;
                5:link.size:=8195;
                6:link.next:=0;
                7:begin
                        System.Seek(raw,16400); System.BlockRead(raw,link,sizeof(link),count);
                        check(count=sizeof(link),'read second link'); link.next:=root;
                  end;
                end;
                if kind=7 then System.Seek(raw,16400) else System.Seek(raw,8200);
                System.BlockWrite(raw,link,sizeof(link),count); System.Close(raw);
                check(count=sizeof(link),'write corrupt link'); reset_database;
                FillChar(actual,sizeof(actual),$A5);
                check(not read_record,'corrupt chain rejected'); check(error=DBM_INVALID,'corrupt chain status'); unchanged;
                if kind<>6 then begin
                        check(not dbm_TryGet(chunks,root,actual,1),'prefix validates full chain');
                        check(chunks.f.ioresult=DBM_INVALID,'prefix corruption status'); unchanged;
                        check(dbm_Size(chunks,root)=0,'size rejects corrupt chain');
                        check(chunks.f.ioresult=DBM_INVALID,'size corruption status');
                end else begin
                        check(dbm_Size(chunks,root)=8194,'size of valid shorter chain');
                        check(dbm_TryGet(chunks,root,actual,1),'valid prefix permitted');
                        check(actual[0]=payload[0],'valid prefix exact');
                end;
                close_database;
        end;
        kind:=0; dbm_ReWrite(chunks,name,8192); root:=dbm_Add(chunks,payload,length);
        dbm_SetRoot(chunks,root); close_database; reset_database;
        check(dbm_Size(chunks,root)=length,'complete chain size'); close_database;
        for fault:=1 to 5 do begin
                        System.Writeln(output,'phase backend ',backend,' kind ',kind,' fault ',fault); System.Flush(output);
                reset_database; hits:=0; writes:=0;
                SetIntVec($21,@intercept); root:=dbm_Size(chunks,1); SetIntVec($21,old21);
                error:=chunks.f.ioresult;
                check(hits>0,'size traverses disk pages'); check(writes=0,'size issues no DOS writes');
                if fault=4 then check((root=length) and (error=0),'size accepts short reads')
                else begin
                        check((root=0) and (error=100),'size reports page read failure');
                        check(dbm_Size(chunks,1)=length,'size retry succeeds');
                end;
                close_database;
        end;
        fault:=0; reset_database;
        check(dbm_TryGet(chunks,0,actual,0),'empty read of null root');
        check(not dbm_TryGet(chunks,0,actual,1),'nonempty read needs root');
        check(chunks.f.ioresult=DBM_INVALID,'null root status'); close_database;
{$ENDIF}
        SetIntVec($60,old60); System.Writeln(output,'PASS ',checks,' assertions'); System.Close(output);
        System.Assign(output,'A:\DBREAD.OK'); System.Rewrite(output);
        System.Writeln(output,'RECORD READ PASS'); System.Close(output);
end.
