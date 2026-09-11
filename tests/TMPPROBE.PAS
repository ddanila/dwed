{ SPDX-License-Identifier: MIT }
program tmpprobe;
uses dos,system2,dbb,dbm;
var f:BFILE; fixed:DBBFile; chunks:DBMFile; output:text; checks:longint;
    old21,old60:pointer; fault,hits,closes,handle:word;
    saved_name,occupied,body:string; regs:registers; held:array[0..63] of pointer;
    held_count,i,backend:integer; baseline,record_number:longint;
const original='OCCUPIED FILE'#13#10;
function pending(var owner:BFILE):boolean;
begin
        {$IFDEF LEGACY_TEMP} pending:=false;
        {$ELSE} pending:=owner.delete_pending; {$ENDIF}
end;
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers;
begin
        if hi(ax)=$3E then inc(closes);
        if ((fault in [1,2]) and (hi(ax)=$5B)) or
           ((fault=3) and ((ax=$7141) or (hi(ax)=$41))) then begin
                inc(hits); if fault=2 then ax:=80 else ax:=5;
                flags:=flags or 1; exit;
        end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        intr($60,r);
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp; flags:=r.flags;
end;
procedure arm(kind:word);
begin fault:=kind; hits:=0; closes:=0; SetIntVec($21,@intercept) end;
procedure disarm;
begin SetIntVec($21,old21) end;
procedure check(ok:boolean; message:string);
begin
        inc(checks);
        if not ok then begin
                disarm; SetIntVec($60,old60);
                System.Writeln(output,'FAIL backend ',backend,' fault ',fault,' assertion ',checks,' ',message);
                System.Close(output); Halt(1);
        end;
end;
procedure expect_file(name,expected:string);
var diskfile:file; got:word; actual:string;
begin
        System.Assign(diskfile,name); System.Reset(diskfile,1);
        System.BlockRead(diskfile,actual[1],255,got); System.Close(diskfile);
        actual[0]:=chr(got); check(actual=expected,'existing file bytes preserved');
end;
procedure remove(name:string);
var diskfile:file;
begin
        System.Assign(diskfile,name); System.Erase(diskfile);
end;
procedure remember(var owner:BFILE);
begin saved_name:=owner.filename end;
procedure retained(var owner:BFILE);
begin
        check(not IsOpen(owner),'DOS handle closed before deletion failure');
        check(pending(owner),'failed deletion retains pending owner');
        check(owner.ioresult=5,'delete error preserved');
        check(owner.filename=saved_name,'cleanup filename retained');
        check(owner.buf=nil,'closed cleanup releases working buffer');
        check((owner.rcache=nil) and (owner.wcache=nil),'closed cleanup releases caches');
        check(FileExists(saved_name),'temporary not removed by refusal');
end;
procedure create_with_body;
begin
        ReWriteTemp(f); check(IsOpen(f) and (f.ioresult=0),'temporary created');
        Write(f,original); Flush(f); check(f.ioresult=0,'temporary payload flushed'); remember(f);
end;
begin
        System.Assign(output,'A:\TEMP.LOG'); System.Rewrite(output);
        GetIntVec($21,old21); GetIntVec($60,old60); SetIntVec($60,old21);
        FillChar(f,sizeof(f),0); FillChar(fixed,sizeof(fixed),0); FillChar(chunks,sizeof(chunks),0);
        if System.ParamStr(1)<>'/DELETE' then begin
                RandSeed:=13579; create_with_body; occupied:=f.filename;
                SetDeleteOnClose(f,false); Close(f);
                RandSeed:=13579; ReWriteTemp(f);
                check(IsOpen(f),'collision retries creation');
                expect_file(occupied,original);
                check(f.filename<>occupied,'collision chooses another name');
                remember(f); ReWriteTemp(f);
                check((f.ioresult=1010) and IsOpen(f) and (f.filename=saved_name),'live owner cannot be reinitialized');
                Close(f); check(not FileExists(saved_name),'new temporary removed'); remove(occupied);
                for i:=1 to 2 do begin
                        baseline:=MemAvail; arm(i); ReWriteTemp(f); disarm;
                        check(hits>0,'creation fault reached DOS');
                        if i=1 then check(f.ioresult=5,'create error preserved')
                        else begin check(f.ioresult=80,'collision exhaustion reported'); check(hits=256,'collision retry bounded') end;
                        check(not IsOpen(f) and (f.buf=nil),'failed creation releases buffer');
                        check(not pending(f),'failed creation has no deletion owner');
                        check(MemAvail=baseline,'failed creation leaks no heap');
                end;
                held_count:=0;
                while (MaxAvail>=16384) and (held_count<64) do begin
                        GetMem(held[held_count],16384); inc(held_count);
                end;
                check(MaxAvail<16384,'creation buffer exhaustion established');
                ReWriteTemp(f); check((f.ioresult=8) and not IsOpen(f) and (f.buf=nil),'creation allocation failure safe');
                while held_count>0 do begin dec(held_count); FreeMem(held[held_count],16384) end;
        end;
        baseline:=MemAvail; create_with_body; arm(3); Close(f); disarm;
        check(MemAvail=baseline,'closed cleanup leaks no heap');
        check(hits>0,'delete fault reached DOS'); check(closes=1,'initial close releases one handle'); retained(f);
        expect_file(saved_name,original);
        { Deliberately reuse the released handle before retrying deletion. }
        body:='C:\REUSED.TXT'+#0; FillChar(regs,sizeof(regs),0);
        regs.ah:=$3C; regs.ds:=seg(body); regs.dx:=ofs(body)+1; intr($21,regs);
        check(regs.flags and 1=0,'unrelated handle opened'); handle:=regs.ax;
        check(handle=f.f,'released DOS handle reused');
        arm(3); Close(f); disarm;
        check(closes=0,'delete retry never closes an unrelated handle'); retained(f);
        ReWriteTemp(f); check((f.ioresult=1010) and pending(f) and (f.filename=saved_name),'pending deletion blocks recreation');
        Close(f); check(not pending(f) and (f.buf=nil) and (f.ioresult=0),'delete retry clears owner');
        check(not FileExists(saved_name),'retry removes temporary');
        FillChar(regs,sizeof(regs),0); regs.ah:=$40; regs.bx:=handle;
        body:=original; regs.cx:=length(body); regs.ds:=seg(body); regs.dx:=ofs(body)+1; intr($21,regs);
        check((regs.flags and 1=0) and (regs.ax=length(original)),'reused handle remains writable');
        regs.ah:=$3E; regs.bx:=handle; intr($21,regs); expect_file('C:\REUSED.TXT',original);
        create_with_body; arm(3); Close(f); disarm; retained(f);
        remove(saved_name); Close(f);
        check(not pending(f) and (f.buf=nil) and (f.ioresult=0),'already removed temporary completes cleanup');
        for backend:=1 to 2 do begin
                if backend=1 then begin
                        dbb_ReWriteTemp(fixed,32); check(dbb_IsOpen(fixed),'fixed temporary created');
                        body:=original; record_number:=dbb_Add(fixed,body); dbb_SetRoot(fixed,record_number); remember(fixed.f);
                        arm(3); dbb_Close(fixed); disarm; retained(fixed.f);
                        check(dbb_GetRoot(fixed)=record_number,'fixed root retained during delete failure');
                        dbb_ReWriteTemp(fixed,32); check(fixed.f.ioresult=1010,'fixed recreation blocked');
                        dbb_Reset(fixed,'C:\OTHER.DBB',32); check(fixed.f.ioresult=1010,'fixed reset blocked');
                        dbb_ReWrite(fixed,'C:\OTHER.DBB',32); check(fixed.f.ioresult=1010,'fixed rewrite blocked');
                        check(pending(fixed.f) and (fixed.f.filename=saved_name),'fixed owner survives attempted replacement');
                        dbb_Close(fixed); check(not pending(fixed.f) and (fixed.f.buf=nil),'fixed delete retry releases owner');
                end else begin
                        dbm_ReWriteTemp(chunks,32); check(dbm_IsOpen(chunks),'chunk temporary created');
                        body:=original; record_number:=dbm_Add(chunks,body,length(body)+1); dbm_SetRoot(chunks,record_number); remember(chunks.f);
                        arm(3); dbm_Close(chunks); disarm; retained(chunks.f);
                        check(dbm_GetRoot(chunks)=record_number,'chunk root retained during delete failure');
                        dbm_ReWriteTemp(chunks,32); check(chunks.f.ioresult=1010,'chunk recreation blocked');
                        dbm_Reset(chunks,'C:\OTHER.DBM',32); check(chunks.f.ioresult=1010,'chunk reset blocked');
                        dbm_ReWrite(chunks,'C:\OTHER.DBM',32); check(chunks.f.ioresult=1010,'chunk rewrite blocked');
                        check(pending(chunks.f) and (chunks.f.filename=saved_name),'chunk owner survives attempted replacement');
                        dbm_Close(chunks); check(not pending(chunks.f) and (chunks.f.buf=nil),'chunk delete retry releases owner');
                end;
                check(not FileExists(saved_name),'database temporary removed on retry');
        end;
        create_with_body; SetDeleteOnClose(f,false); Close(f); Assign(f,saved_name);
        Erase(f); check(f.ioresult=0,'explicit erase reports success');
        Erase(f); check(f.ioresult=2,'explicit erase reports missing file');
        SetIntVec($60,old60); System.Writeln(output,'PASS ',checks,' assertions'); System.Close(output);
        System.Assign(output,'A:\TEMP.OK'); System.Rewrite(output);
        System.Writeln(output,'TEMPORARY OWNER PASS'); System.Close(output);
end.
