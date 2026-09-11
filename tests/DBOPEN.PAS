{ SPDX-License-Identifier: MIT }
program dbopen;
uses dos,system2,dbb,dbm;
var fixed:DBBFile; chunks:DBMFile; output:text; checks:longint;
    backend,kind,i,error:integer; fault,hits,handle:word; old21,old60:pointer;
    name:string; payload,actual:array[0..31] of byte;
    before,after:array[0..1023] of byte; before_size,after_size:word;
    root:longint; create_calls,write_calls:word; held:array[0..63] of pointer; held_count:integer;
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers; service:byte; reject:boolean;
begin
        { This DOS-only probe forwards standard calls. Explicitly report the
          unsupported LFN probe so Pascal Intr cannot change its carry input. }
        if ax=$716C then begin ax:=$7100; flags:=flags or 1; exit end;
        service:=hi(ax); reject:=false;
        if service=$3C then inc(create_calls);
        if service=$40 then inc(write_calls);
        if (fault=1) and (service=$3D) then reject:=true;
        if bx=handle then begin
                if ((fault=2) and (ax=$4202)) or ((fault=3) and (ax=$4201)) or
                   ((fault=4) and (ax=$4200)) then reject:=true;
                if (fault in [5,8]) and (service=$3F) then reject:=true;
                if (fault in [8,9]) and (service=$3E) then reject:=true;
                if (fault=6) and (service=$3F) then begin ax:=0; flags:=flags and $FFFE; inc(hits); exit end;
        end;
        if reject then begin ax:=5; flags:=flags or 1; inc(hits); exit end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        if (fault=7) and (service=$3F) and (bx=handle) and (r.cx>7) then begin r.cx:=7; inc(hits) end;
        intr($60,r);
        if (service=$3D) and (r.flags and 1=0) then handle:=r.ax;
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp; flags:=r.flags;
end;
procedure check(ok:boolean; message:string);
begin
        inc(checks);
        if not ok then begin
                SetIntVec($21,old21); SetIntVec($60,old60);
                System.Writeln(output,'FAIL backend ',backend,' kind ',kind,' fault ',fault,' assertion ',checks,' ',message);
                System.Close(output); Halt(1);
        end;
end;
procedure close_database;
begin if backend=1 then dbb_Close(fixed) else dbm_Close(chunks) end;
procedure reset_database;
begin
        if backend=1 then begin dbb_Reset(fixed,name,32); error:=fixed.f.ioresult end
        else begin dbm_Reset(chunks,name,32); error:=chunks.f.ioresult end;
end;
function opened:boolean;
begin if backend=1 then opened:=dbb_IsOpen(fixed) else opened:=dbm_IsOpen(chunks) end;
procedure snapshot(var bytes; var count:word);
var f:file;
begin
        System.Assign(f,name); System.Reset(f,1); System.BlockRead(f,bytes,1024,count); System.Close(f);
end;
procedure unchanged;
begin
        snapshot(after,after_size); check(after_size=before_size,'database length unchanged');
        for i:=0 to before_size-1 do check(before[i]=after[i],'database bytes unchanged');
end;
procedure fixture;
begin
        if backend=1 then begin
                name:='C:\FIXED.DBB'; dbb_ReWrite(fixed,name,32);
                root:=dbb_Add(fixed,payload); dbb_SetRoot(fixed,root);
        end else begin
                name:='C:\CHAIN.DBM'; dbm_ReWrite(chunks,name,32);
                root:=dbm_Add(chunks,payload,sizeof(payload)); dbm_SetRoot(chunks,root);
        end;
        check(opened and (root<>0),'fixture database ready'); close_database; snapshot(before,before_size);
end;
procedure replace_fixture;
var f:file; count:word;
begin
        System.Assign(f,name); System.Rewrite(f,1);
        System.BlockWrite(f,before,before_size,count); System.Close(f);
        check(count=before_size,'corrupted fixture written');
end;
procedure arm;
begin handle:=$FFFF; hits:=0; create_calls:=0; write_calls:=0; SetIntVec($21,@intercept) end;
procedure disarm;
begin SetIntVec($21,old21) end;
begin
        System.Assign(output,'A:\DBOPEN.LOG'); System.Rewrite(output);
        GetIntVec($21,old21); GetIntVec($60,old60); SetIntVec($60,old21);
        FillChar(fixed,sizeof(fixed),0); FillChar(chunks,sizeof(chunks),0);
        for i:=0 to 31 do payload[i]:=(i*17+11) mod 256;
        for backend:=1 to 2 do begin
                { A malformed existing database must never turn into a new one. }
                for kind:=1 to 7 do begin
                        fixture;
                        case kind of
                        1:before[0]:=0;
                        2:before_size:=7;
                        3:before[14]:=0;
                        4:begin before[6]:=$FF; before[7]:=$FF; before[8]:=$FF; before[9]:=$7F end;
                        5:before[2]:=99;
                        6:before[10]:=99;
                        7:dec(before_size);
                        end;
                        replace_fixture; fault:=0; arm; reset_database; disarm;
                        check(error=1019,'invalid header refused'); check(not opened,'invalid database not exposed');
                        check(create_calls=0,'reset never recreates invalid file'); unchanged; close_database; unchanged;
                end;
                kind:=8;
                for fault:=1 to 8 do begin
                        fixture; arm; reset_database; disarm;
                        check(hits>0,'open/read fault reached DOS'); check(create_calls=0,'failed open never recreates file');
                        if fault=7 then begin
                                check((error=0) and opened,'positive short reads complete');
                                FillChar(actual,sizeof(actual),0);
                                if backend=1 then dbb_Get(fixed,root,actual) else dbm_Get(chunks,root,actual,sizeof(actual));
                                for i:=0 to 31 do check(actual[i]=payload[i],'short-read payload complete');
                        end else begin
                                check(error<>0,'initialization failure reported'); check(not opened,'failed initialization not exposed');
                                if fault<>6 then check(error=5,'DOS failure code preserved');
                        end;
                        unchanged;
                        if fault=8 then begin
                                if backend=1 then begin
                                        check(IsOpen(fixed.f),'fixed failed close retains raw owner');
                                        check(fixed.header.sign=0,'fixed candidate header not published');
                                        check(dbb_Add(fixed,payload)=0,'fixed failed owner rejects mutation');
                                end else begin
                                        check(IsOpen(chunks.f),'chunk failed close retains raw owner');
                                        check(chunks.header.sign=0,'chunk candidate header not published');
                                        check(dbm_Add(chunks,payload,sizeof(payload))=0,'chunk failed owner rejects mutation');
                                end;
                        end;
                        close_database; unchanged;
                        reset_database; check((error=0) and opened,'initialization retries'); close_database;
                end;
                kind:=9; fixture; before[0]:=0; replace_fixture;
                fault:=9; arm; reset_database; disarm;
                check((error=1019) and not opened,'invalid header with close refusal not exposed');
                check((hits>0) and (write_calls=0),'invalid header cleanup never writes');
                if backend=1 then check(IsOpen(fixed.f),'invalid fixed header retains raw owner')
                else check(IsOpen(chunks.f),'invalid chunk header retains raw owner');
                unchanged;
                arm; if backend=1 then handle:=fixed.f.f else handle:=chunks.f.f;
                close_database; disarm;
                check((hits>0) and (write_calls=0),'repeated cleanup never writes invalid header');
                close_database; unchanged;
                kind:=10; fault:=0; fixture;
                held_count:=0;
                while (MaxAvail>=16384) and (held_count<64) do begin
                        GetMem(held[held_count],16384); inc(held_count);
                end;
                check(MaxAvail<16384,'open buffer exhaustion established');
                arm; reset_database; disarm;
                check((error=8) and not opened,'open allocation failure reported');
                check(create_calls=0,'allocation failure never recreates file');
                while held_count>0 do begin dec(held_count); FreeMem(held[held_count],16384) end;
                unchanged; close_database;
                kind:=11; name:='C:\ABSENT.DB'; arm; reset_database; disarm;
                check((error=2) and not opened,'missing database remains missing');
                check(create_calls=0,'missing database not implicitly created');
                check(not FileExists(name),'missing database has no new directory entry');
                close_database;
        end;
        backend:=2; kind:=12; fault:=0; fixture;
        dbm_ReWrite(chunks,name,65535);
        check(not dbm_IsOpen(chunks) and (chunks.f.ioresult=1019),'overflowing block geometry refused'); unchanged;
        kind:=13;
        dbm_ReWrite(chunks,name,65526);
        check(dbm_IsOpen(chunks) and (chunks.header.size=65532),'largest representable block initialized');
        root:=dbm_Add(chunks,payload,sizeof(payload)); check(root=1,'large block record allocated');
        dbm_SetRoot(chunks,root); dbm_Close(chunks);
        dbm_Reset(chunks,name,65526);
        check(dbm_IsOpen(chunks) and (chunks.header.size=65532),'large block reopens with full header padding');
        check(dbm_GetRoot(chunks)=root,'large block root persisted');
        FillChar(actual,sizeof(actual),0); dbm_Get(chunks,root,actual,sizeof(actual));
        for i:=0 to 31 do check(actual[i]=payload[i],'large block payload crosses page boundary');
        dbm_Close(chunks);
        SetIntVec($60,old60); System.Writeln(output,'PASS ',checks,' assertions'); System.Close(output);
        System.Assign(output,'A:\DBOPEN.OK'); System.Rewrite(output);
        System.Writeln(output,'DATABASE OPEN PASS'); System.Close(output);
end.
