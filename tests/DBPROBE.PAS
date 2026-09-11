{ SPDX-License-Identifier: MIT }
program dbprobe;
uses dos,system2,dbb,dbm;
var fixed:DBBFile; chunks:DBMFile; output:text; checks:longint;
    fault,hits,handle:word; backend:integer; armed:boolean; old21,old60:pointer;
    payload,actual:array[0..95] of byte; first,second,records:longint;
    saved_buffer,saved_read_cache,saved_write_cache:pointer; i,held_count:integer;
    held:array[0..63] of pointer; saved_name:string;
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers; service:byte; reject:boolean;
begin
        service:=hi(ax); reject:=false;
        if armed and (bx=handle) then begin
                if (fault=1) and (service=$40) then reject:=true;
                if (fault=3) and (service=$3E) then reject:=true;
                if (fault=4) and (service=$42) then reject:=true;
        end;
        if reject then begin ax:=5; flags:=flags or 1; inc(hits); exit end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp; r.flags:=flags;
        if armed and (bx=handle) and (fault=2) and (service=$40) then begin
                if r.cx>0 then dec(r.cx); inc(hits);
        end;
        intr($60,r);
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp;
        flags:=(flags and $0300) or (r.flags and $FCFF);
end;
procedure check(ok:boolean; message:string);
begin
        inc(checks);
        if not ok then begin
                armed:=false; SetIntVec($21,old21); SetIntVec($60,old60);
                System.Writeln(output,'FAIL backend ',backend,' fault ',fault,' assertion ',checks,' ',message);
                System.Close(output); Halt(1);
        end;
end;
procedure close_database;
begin
        if backend=1 then dbb_Close(fixed) else dbm_Close(chunks);
end;
procedure remember(var f:BFILE);
begin
        handle:=f.f; saved_buffer:=f.buf;
        saved_read_cache:=f.rcache; saved_write_cache:=f.wcache;
end;
procedure retained(var f:BFILE);
begin
        check(IsOpen(f),'failed close retains open owner');
        check(f.ioresult<>0,'failed close retains error');
        check(f.f=handle,'DOS handle retained');
        check(f.buf=saved_buffer,'working buffer retained');
        check(f.rcache=saved_read_cache,'read cache retained');
        check(f.wcache=saved_write_cache,'write cache retained');
end;
procedure check_payload;
begin
        for i:=0 to 95 do check(actual[i]=payload[i],'record bytes');
end;
begin
        System.Assign(output,'A:\DB.LOG'); System.Rewrite(output);
        GetIntVec($21,old21); GetIntVec($60,old60);
        SetIntVec($60,old21);
        for i:=0 to 95 do payload[i]:=(i*37+19) mod 256;
        for backend:=1 to 2 do for fault:=1 to 4 do begin
                if backend=1 then begin
                        dbb_ReWrite(fixed,'C:\BLOCK.DBB',sizeof(payload));
                        check(dbb_IsOpen(fixed),'fixed database opened');
                        first:=dbb_Add(fixed,payload); check(first<>0,'fixed record allocated');
                        dbb_SetRoot(fixed,first); records:=fixed.header.records; remember(fixed.f);
                end else begin
                        dbm_ReWrite(chunks,'C:\CHUNK.DBM',32);
                        check(dbm_IsOpen(chunks),'chunk database opened');
                        first:=dbm_Add(chunks,payload,sizeof(payload)); check(first<>0,'chunk record allocated');
                        dbm_SetRoot(chunks,first); records:=chunks.header.records; remember(chunks.f);
                end;
                hits:=0; SetIntVec($21,@intercept); armed:=true; close_database; armed:=false; SetIntVec($21,old21);
                check(hits>0,'fault reached real DOS call');
                if backend=1 then begin
                        retained(fixed.f);
                        check(fixed.header.records=records,'fixed record count retained');
                        check(dbb_GetRoot(fixed)=first,'fixed root retained');
                end else begin
                        retained(chunks.f);
                        check(chunks.header.records=records,'chunk record count retained');
                        check(dbm_GetRoot(chunks)=first,'chunk root retained');
                        check(chunks.rblk_size<>0,'chunk geometry retained');
                end;
                { A persistent refusal must not turn the next close into success. }
                SetIntVec($21,@intercept); armed:=true; close_database; armed:=false; SetIntVec($21,old21);
                if backend=1 then retained(fixed.f) else retained(chunks.f);
                FillChar(actual,sizeof(actual),0);
                if backend=1 then begin
                        dbb_Get(fixed,first,actual); check_payload;
                        second:=dbb_Add(fixed,payload); check(second>first,'fixed database remains usable');
                end else begin
                        dbm_Get(chunks,first,actual,sizeof(actual)); check_payload;
                        second:=dbm_Add(chunks,payload,sizeof(payload)); check(second>first,'chunk database remains usable');
                end;
                close_database;
                if backend=1 then begin
                        check(not dbb_IsOpen(fixed),'fixed close retries');
                        check(fixed.f.buf=nil,'fixed successful close releases buffer');
                        dbb_Reset(fixed,'C:\BLOCK.DBB',sizeof(payload));
                        check(dbb_GetRoot(fixed)=first,'fixed root persisted');
                        FillChar(actual,sizeof(actual),0); dbb_Get(fixed,first,actual); check_payload;
                        FillChar(actual,sizeof(actual),0); dbb_Get(fixed,second,actual); check_payload;
                end else begin
                        check(not dbm_IsOpen(chunks),'chunk close retries');
                        check(chunks.f.buf=nil,'chunk successful close releases buffer');
                        dbm_Reset(chunks,'C:\CHUNK.DBM',32);
                        check(dbm_GetRoot(chunks)=first,'chunk root persisted');
                        FillChar(actual,sizeof(actual),0); dbm_Get(chunks,first,actual,sizeof(actual)); check_payload;
                        FillChar(actual,sizeof(actual),0); dbm_Get(chunks,second,actual,sizeof(actual)); check_payload;
                end;
                close_database;
        end;
        for backend:=1 to 2 do begin
                fault:=5;
                if backend=1 then begin
                        dbb_ReWrite(fixed,'C:\BLOCK.DBB',sizeof(payload));
                        first:=dbb_Add(fixed,payload); dbb_SetRoot(fixed,first);
                        Seek(fixed.f,16384); check(fixed.f.ioresult=0,'fixed header page staged'); remember(fixed.f);
                end else begin
                        dbm_ReWrite(chunks,'C:\CHUNK.DBM',32);
                        first:=dbm_Add(chunks,payload,sizeof(payload)); dbm_SetRoot(chunks,first);
                        Seek(chunks.f,16384); check(chunks.f.ioresult=0,'chunk header page staged'); remember(chunks.f);
                end;
                held_count:=0;
                while (MaxAvail>=16384) and (held_count<64) do begin
                        GetMem(held[held_count],16384); inc(held_count);
                end;
                check(MaxAvail<16384,'header-seek scratch allocation exhausted');
                close_database;
                if backend=1 then begin retained(fixed.f); check(fixed.f.ioresult=8,'fixed header seek error retained') end
                else begin retained(chunks.f); check(chunks.f.ioresult=8,'chunk header seek error retained') end;
                while held_count>0 do begin dec(held_count); FreeMem(held[held_count],16384) end;
                FillChar(actual,sizeof(actual),0);
                if backend=1 then dbb_Get(fixed,first,actual)
                else dbm_Get(chunks,first,actual,sizeof(actual));
                check_payload; close_database;
                if backend=1 then check(not dbb_IsOpen(fixed),'fixed allocation retry closes')
                else check(not dbm_IsOpen(chunks),'chunk allocation retry closes');

                { Temporary backing stores skip flush on final discard, but a
                  refused handle close must still retain their cleanup owner. }
                fault:=3;
                if backend=1 then begin
                        dbb_ReWriteTemp(fixed,sizeof(payload)); check(dbb_IsOpen(fixed),'fixed temporary opened');
                        first:=dbb_Add(fixed,payload); remember(fixed.f); saved_name:=fixed.f.filename;
                end else begin
                        dbm_ReWriteTemp(chunks,32); check(dbm_IsOpen(chunks),'chunk temporary opened');
                        first:=dbm_Add(chunks,payload,sizeof(payload)); remember(chunks.f); saved_name:=chunks.f.filename;
                end;
                hits:=0; SetIntVec($21,@intercept); armed:=true; close_database; armed:=false; SetIntVec($21,old21);
                check(hits>0,'temporary close fault reached DOS');
                FillChar(actual,sizeof(actual),0);
                if backend=1 then begin
                        retained(fixed.f); check(fixed.f.filename=saved_name,'fixed temporary name retained');
                        dbb_Get(fixed,first,actual);
                end else begin
                        retained(chunks.f); check(chunks.f.filename=saved_name,'chunk temporary name retained');
                        dbm_Get(chunks,first,actual,sizeof(actual));
                end;
                check_payload; check(FileExists(saved_name),'temporary still exists during refusal');
                close_database; check(not FileExists(saved_name),'temporary removed after retry');
        end;
        SetIntVec($21,old21); SetIntVec($60,old60);
        System.Writeln(output,'PASS ',checks,' assertions'); System.Close(output);
        System.Assign(output,'A:\DB.OK'); System.Rewrite(output);
        System.Writeln(output,'DATABASE CLOSE PASS'); System.Close(output);
end.
