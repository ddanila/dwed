{ SPDX-License-Identifier: MIT }
program savetest;
uses dos,safesave;
var output:text; tests:longint; sf:TSaveFile; error,kind:integer;
    old21,old60:pointer; armed,hooked:boolean; fault,hits,renames,temp_handle:word;
    payload:string; regs:registers;
const original='OLD_SOURCE'; older='OLDER_BACKUP';

{ FPC's interrupt stack parameters are declared in reverse stack order. }
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers; service:byte; reject:boolean;
begin
        service:=hi(ax); reject:=false;
        if armed then begin
                if (service=$40) and (bx=temp_handle) and (fault in [1,12]) then reject:=true;
                if (service=$68) and (bx=temp_handle) and (fault=3) then reject:=true;
                if (service=$3E) and (bx=temp_handle) and
                   (((fault=4) and (hits=0)) or (fault=13)) then reject:=true;
                if service=$56 then begin
                        inc(renames);
                        reject:=((fault=5) and (renames=1)) or
                                ((fault=6) and (renames=2)) or
                                ((fault in [7,8,9]) and (renames=3)) or
                                ((fault=8) and (renames=4)) or
                                ((fault=9) and (renames=5)) or
                                ((fault=14) and (renames=1));
                end;
                if service=$41 then
                        if (mem[ds:dx+3]=ord('$')) and (mem[ds:dx+4]=ord('E')) then
                                if ((fault=11) and (mem[ds:dx+5]=ord('B'))) or
                                   ((fault=12) and (mem[ds:dx+5]=ord('D'))) then reject:=true;
        end;
        if reject then begin ax:=5; flags:=flags or 1; inc(hits); exit end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        if armed and (fault=2) and (service=$40) and (bx=temp_handle) then begin
                if r.cx>0 then dec(r.cx); inc(hits);
        end;
        { The original DOS vector is invoked through a private interrupt. }
        intr($60,r);
        if armed and (fault=15) and (service=$3E) and (bx=temp_handle) and (hits=0) then begin
                r.ax:=5; r.flags:=r.flags or 1; inc(hits);
        end;
        if armed and (service=$5B) and (r.flags and 1=0) then temp_handle:=r.ax;
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp;
        flags:=(flags and $0300) or (r.flags and $FCFF);
end;

procedure check(ok:boolean; message:string);
begin
        inc(tests);
        if not ok then begin
                if hooked then begin SetIntVec($21,old21); SetIntVec($60,old60); hooked:=false end;
                writeln(output,'FAIL case ',kind,' assertion ',tests,' ',message);
                close(output); halt(1);
        end;
end;

procedure remove(name:string);
var f:file;
begin
        if name='' then exit;
        System.Assign(f,name); SetFAttr(f,0);
        {$I-} System.Erase(f); {$I+}
        if System.IOResult<>0 then;
end;

procedure fixture(name,body:string);
var f:file; written:word;
begin
        remove(name); System.Assign(f,name); System.Rewrite(f,1);
        System.BlockWrite(f,body[1],length(body),written); System.Close(f);
        check(written=length(body),'fixture complete');
end;

procedure expect_file(name,body:string);
var f:file; actual:string; got:word; previous_mode:byte;
begin
        System.Assign(f,name); previous_mode:=System.FileMode; System.FileMode:=0;
        {$I-} System.Reset(f,1); {$I+}
        System.FileMode:=previous_mode;
        check(System.IOResult=0,'expected file exists: '+name);
        System.BlockRead(f,actual[1],255,got); System.Close(f); actual[0]:=chr(got);
        check(actual=body,'file bytes: '+name);
end;

procedure expect_absent(name:string);
var f:file; attr:word;
begin
        System.Assign(f,name); GetFAttr(f,attr);
        check(DosError=2,'file absent: '+name);
end;

procedure run_case;
var f:file; duplicate:word;
begin
        fixture('C:\SAVE.TXT',original); fixture('C:\SAVE.BAK',older);
        if kind=10 then begin System.Assign(f,'C:\SAVE.BAK'); SetFAttr(f,1) end;
        if kind=14 then remove('C:\SAVE.TXT');
        hits:=0; renames:=0; temp_handle:=$FFFF; fault:=kind; armed:=true;
        start_save(sf,'C:\SAVE.TXT',error);
        if error=0 then begin
                write_save(sf,payload[1],length(payload),error); finish_save(sf,error);
        end;
        armed:=false;
        if kind in [0,11] then check(error=0,'save published')
        else if kind=2 then check(error=101,'short write detected')
        else check(error=5,'DOS failure propagated');
        if not (kind in [0,10]) then check(hits>0,'fault reached actual DOS call');
        FillChar(regs,sizeof(regs),0); regs.ah:=$45; regs.bx:=temp_handle;
        intr($21,regs);
        if kind=13 then begin
                check((regs.flags and 1=0) and sf.opened,'persistent close failure retains ownership');
                duplicate:=regs.ax; regs.ah:=$3E; regs.bx:=duplicate; intr($21,regs);
                cancel_save(sf); check(not sf.opened,'retry can close after fault removed');
        end else check(regs.flags and 1<>0,'temporary handle closed');
        if kind in [0,11] then begin
                expect_file('C:\SAVE.TXT',payload); expect_file('C:\SAVE.BAK',original);
        end else if kind=8 then begin
                expect_absent('C:\SAVE.TXT'); expect_file('C:\SAVE.BAK',original);
                expect_file(sf.temporary,payload); expect_file(sf.previous_backup,older);
                check(sf.recovery_error=5,'failed original rollback reported');
        end else if kind=9 then begin
                expect_file('C:\SAVE.TXT',original); expect_absent('C:\SAVE.BAK');
                expect_file(sf.temporary,payload); expect_file(sf.previous_backup,older);
                check(sf.recovery_error=5,'failed backup rollback reported');
        end else begin
                if kind=14 then expect_absent('C:\SAVE.TXT') else expect_file('C:\SAVE.TXT',original);
                expect_file('C:\SAVE.BAK',older);
        end;
        if kind=11 then begin
                check(sf.cleanup_error=5,'post-publication cleanup failure recorded');
                expect_file(sf.previous_backup,older);
        end;
        if kind=12 then begin
                check(sf.cleanup_error=5,'failed temporary removal recorded');
                expect_file(sf.temporary,'');
        end;
        if not (kind in [8,9,11,12]) then
                check((sf.temporary='') and (sf.previous_backup=''),'completed cleanup');
        expect_file('C:\$EB0000.TMP','OTHER_BACKUP_TRANSACTION');
        remove(sf.temporary); remove(sf.previous_backup);
        writeln(output,'CASE ',kind,' PASS');
end;

begin
        System.Assign(output,'A:\SAVE.LOG'); System.Rewrite(output); tests:=0; armed:=false; hooked:=false;
        payload:='NEW'+#9#128#255;
        fixture('C:\$EB0000.TMP','OTHER_BACKUP_TRANSACTION');
        GetIntVec($21,old21); GetIntVec($60,old60);
        SetIntVec($60,old21); SetIntVec($21,@intercept); hooked:=true;
        for kind:=0 to 15 do run_case;
        SetIntVec($21,old21); SetIntVec($60,old60); hooked:=false;
        remove('C:\$EB0000.TMP'); remove('C:\SAVE.TXT'); remove('C:\SAVE.BAK');
        writeln(output,'PASS ',tests,' assertions'); close(output);
        System.Assign(output,'A:\SAVE.OK'); System.Rewrite(output);
        writeln(output,'SAVE FAULTS PASS'); close(output);
end.
