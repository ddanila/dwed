{ SPDX-License-Identifier: MIT }
program cachetest;
uses cachehook,system2,excache,exms,dos;
var output:text; checks:longint; a,b:array[0..16383] of byte;
    f:BFILE; diskfile:file; c:PEXCACHE; count,i,j:word;
    old21,old60:pointer; hooked:boolean; target:word; fault:byte; hits:word;
    held:array[0..63] of pointer; held_count:integer;
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:Registers;
begin
        if (bx=target) and (((fault=1) and (Hi(ax)=$40)) or
           ((fault=3) and (Hi(ax)=$42)) or ((fault=4) and (Hi(ax)=$3e))) then begin
                ax:=5; flags:=flags or 1; Inc(hits); fault:=0; exit;
        end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        if (fault=2) and (bx=target) and (Hi(ax)=$40) then begin
                r.cx:=cx div 2; fault:=0; Inc(hits);
        end;
        Intr($60,r);
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp; flags:=r.flags;
end;
{$IFDEF LEGACY_CACHE}
function excache_Peek(cache:PEXCACHE; record_number:longint; var data; var size:word):integer;
begin
        if excache_Get(cache,record_number,data,size) then excache_Peek:=0 else excache_Peek:=-1;
end;
{$ENDIF}
procedure restore;
begin
        if hooked then begin SetIntVec($21,old21); SetIntVec($60,old60) end;
        hooked:=false; restore_cache_hook;
end;
procedure check(ok:boolean; message:string);
begin
        Inc(checks);
        if not ok then begin
                System.Writeln(output,'FAIL ',checks,' ',message,' io=',f.ioresult);
                System.Close(output); restore; Halt(1);
        end;
end;
procedure fill(value:byte);
begin FillChar(a,sizeof(a),value) end;
procedure check_buffer(var data; value:byte; message:string);
var p:^byte; k:word;
begin
        p:=@data;
        for k:=0 to 16383 do begin check(p^=value,message); Inc(p) end;
end;
procedure seed;
begin
        System.Assign(diskfile,'A:\CACHE.DAT'); System.Rewrite(diskfile,1);
        fill(0); System.BlockWrite(diskfile,a,sizeof(a)); System.BlockWrite(diskfile,a,sizeof(a));
        System.Close(diskfile);
        system2.Assign(f,'A:\CACHE.DAT'); system2.Reset(f);
        check(f.is_open and (f.ioresult=0),'open buffered file');
        check((f.wcache<>nil) and (f.rcache<>nil),'real XMS caches available');
        target:=f.f;
end;
procedure dirty_pair;
begin
        seed; fill($a5); system2.BlockWrite(f,a,sizeof(a));
        system2.Seek(f,16384); check(f.ioresult=0,'cache first dirty page');
        fill($5a); system2.BlockWrite(f,a,sizeof(a));
        check(PEXCACHE(f.wcache)^.allocated=1,'first dirty page has cache owner');
end;
procedure verify_pair;
begin
        system2.Close(f); check(not f.is_open,'successful close');
        System.Assign(diskfile,'A:\CACHE.DAT'); System.Reset(diskfile,1);
        System.BlockRead(diskfile,b,sizeof(b),count); check(count=16384,'first saved page length');
        check_buffer(b,$a5,'first saved page bytes');
        System.BlockRead(diskfile,b,sizeof(b),count); check(count=16384,'second saved page length');
        check_buffer(b,$5a,'second saved page bytes'); System.Close(diskfile);
end;
begin
        hooked:=false; checks:=0; FillChar(f,sizeof(f),0);
        System.Assign(output,'A:\CACHE.LOG'); System.Rewrite(output);
        check(available,'XMS driver installed');
        GetIntVec($21,old21); GetIntVec($60,old60); SetIntVec($60,old21);
        SetIntVec($21,@intercept); hooked:=true; fault:=0; hits:=0;
        if ParamStr(1)<>'/WRITEBACK' then begin
        c:=excache_Create(1); check(c<>nil,'create single-item cache');
        fill($a5); check(excache_Put(c,7,a,16384),'cache initial page');
        fill($5a); arm_transfer(1,true);
        check(not excache_Put(c,7,a,16384),'refuse partial same-record replacement');
        check(c^.allocated=1,'replacement failure retains count');
        check(excache_Get(c,7,b,count),'old replacement target retained');
        check_buffer(b,$a5,'partial replacement preserves old bytes');
        fill($a5); check(excache_Put(c,7,a,16384),'restore cache item');
        fill($5a); arm_transfer(1,true);
        check(not excache_Put(c,8,a,16384),'refuse partial eviction');
        check(excache_Get(c,7,b,count),'eviction victim retained');
        check_buffer(b,$a5,'partial eviction preserves old bytes');
        check(excache_Put(c,7,a,16384),'store replacement');
        check(excache_Put(c,7,a,16384),'same-record overwrite');
        check(c^.allocated=1,'no duplicate record');
        count:=123; arm_transfer(2,true);
        check(excache_Peek(c,7,b,count)>0,'partial read reports error');
        check((count=123) and (c^.allocated=1),'failed read retains metadata');
        check(excache_Get(c,7,b,count),'retry cached read'); check_buffer(b,$5a,'retry has complete data');
        excache_Free(c);
        end;

        dirty_pair; arm_transfer(2,true); system2.Seek(f,0);
        check(f.ioresult=100,'dirty-cache read failure does not fall back to disk');
        check((f.buf_page=1) and (f.buf_pos=16384) and f.buf_update,'failed seek preserves current dirty buffer');
        check_buffer(f.buf^,$5a,'failed seek preserves current bytes');
        check(PEXCACHE(f.wcache)^.allocated=1,'failed seek retains cached dirty page');
        arm_transfer(2,true); system2.Close(f);
        check((f.ioresult=100) and f.is_open,'failed flush keeps file open');
        check(f.buf_update and (PEXCACHE(f.wcache)^.allocated=1),'failed close retains both dirty owners');
        verify_pair;

        dirty_pair; fault:=2; system2.Flush(f);
        check((f.ioresult=101) and (PEXCACHE(f.wcache)^.allocated=1),'short disk write retains cached page');
        check(f.buf_update and (f.buf_page=1) and (f.buf_pos=16384),'short write preserves working buffer');
        system2.Flush(f); check(f.ioresult=0,'retry short write');
        fault:=4; system2.Close(f); check(f.is_open and (f.ioresult=5),'failed close retains ownership');
        verify_pair;

        seed; fill($a5); system2.BlockWrite(f,a,sizeof(a));
        arm_transfer(1,true); system2.Seek(f,16384);
        check(f.ioresult=0,'failed cache write falls back to checked disk write');
        check(PEXCACHE(f.wcache)^.allocated=0,'failed cache write publishes no item');
        fill($5a); system2.BlockWrite(f,a,sizeof(a)); verify_pair;

        dirty_pair; system2.Seek(f,0); check(f.ioresult=0,'load first dirty page');
        f.buf_pos:=f.buf_count; arm_transfer(2,true);
        count:=system2.BlockRead(f,b,1);
        check((count=0) and (f.ioresult=100),'boundary read propagates cache failure');
        check((f.buf_page=0) and (f.buf_pos=16384),'boundary read retains cursor');
        count:=system2.BlockRead(f,b,1);
        check((count=1) and (b[0]=$5a) and (f.ioresult=0),'boundary read retries'); verify_pair;

        seed; fill($a5); system2.BlockWrite(f,a,sizeof(a));
        arm_transfer(1,true); fault:=1; system2.Seek(f,16384);
        check(f.ioresult=101,'cache and disk write failure propagates');
        check((f.buf_page=0) and (f.buf_pos=16384) and f.buf_update,'combined failure retains dirty owner');
        check_buffer(f.buf^,$a5,'combined failure retains complete data');
        check(PEXCACHE(f.wcache)^.allocated=0,'combined failure publishes no cache item');
        system2.Seek(f,16384); check(f.ioresult=0,'retry combined failure');
        fill($5a); system2.BlockWrite(f,a,sizeof(a)); verify_pair;

        seed; system2.Seek(f,16384); arm_transfer(2,true); system2.Seek(f,0);
        check(f.ioresult=0,'clean cache read failure falls back to disk');
        check_buffer(f.buf^,0,'clean fallback loads complete disk page');
        system2.Close(f); check(not f.is_open,'close clean fallback file');

        dirty_pair; fault:=3; system2.Flush(f);
        check((f.ioresult=101) and (PEXCACHE(f.wcache)^.allocated=1),'failed writeback seek retains cache item');
        verify_pair;

        dirty_pair; held_count:=0;
        while (MaxAvail>=16384) and (held_count<64) do begin
                GetMem(held[held_count],16384); Inc(held_count);
        end;
        check(MaxAvail<16384,'fragmented/exhausted scratch allocation fixture');
        system2.Seek(f,0); check((f.ioresult=8) and (f.buf_page=1),'scratch refusal retains buffer');
        system2.Close(f); check((f.ioresult=8) and f.is_open,'scratch refusal retains open file');
        check(f.buf_update and (PEXCACHE(f.wcache)^.allocated=1),'scratch refusal retains dirty owners');
        while held_count>0 do begin Dec(held_count); FreeMem(held[held_count],16384) end;
        verify_pair;

        seed; fault:=3; system2.Seek(f,16384);
        check((f.ioresult=100) and (f.buf_page=0) and (f.buf_pos=0),'disk seek failure retains buffer position');
        system2.Close(f); check(not f.is_open,'close after failed clean seek');

        system2.Assign(f,'A:\CACHE.DAT'); system2.ReWrite(f);
        for j:=1 to 12 do begin fill(j); system2.BlockWrite(f,a,sizeof(a)); check(f.ioresult=0,'write beyond cache capacity') end;
        system2.Close(f); check(not f.is_open,'flush full cache');
        System.Assign(diskfile,'A:\CACHE.DAT'); System.Reset(diskfile,1);
        for j:=1 to 12 do begin
                System.BlockRead(diskfile,b,sizeof(b),count); check(count=16384,'full-cache page length');
                check_buffer(b,j,'full-cache ordered bytes');
        end;
        System.Close(diskfile); check(hits=5,'all DOS fault cases triggered');
        if ParamStr(1)='/WRITEBACK' then check(transfer_hits=6,'writeback transfer faults triggered')
        else check(transfer_hits=9,'all transfer fault cases triggered');
        restore;
        System.Writeln(output,'PASS ',checks,' assertions'); System.Close(output);
        System.Assign(output,'A:\CACHE.OK'); System.Rewrite(output);
        System.Writeln(output,'CACHE SAFETY PASS'); System.Close(output);
end.
