{ SPDX-License-Identifier: MIT }
program savetest;
uses dos,safesave,saveinfo,strs,dwedtype,dwedutil,unredo;
var output:text; tests:longint; sf:TSaveFile; error,kind:integer;
    old21,old60:pointer; armed,hooked:boolean; fault,hits,renames,temp_handle:word;
    payload:string; regs:registers; journal_handle:word; journal_active:boolean;
const original='OLD_SOURCE'; older='OLDER_BACKUP';

{ FPC's interrupt stack parameters are declared in reverse stack order. }
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers; service:byte; reject:boolean;
begin
        service:=hi(ax); reject:=false;
        if armed then begin
                if (service=$5B) and (mem[ds:dx+3]=ord('$')) and
                   (mem[ds:dx+4]=ord('E')) and (mem[ds:dx+5]=ord('R')) and (fault=18) then reject:=true;
                if journal_active and (bx=journal_handle) then begin
                        if (service=$40) and (fault=19) then reject:=true;
                        if (service=$68) and (fault=21) then reject:=true;
                        if (service=$3E) and (fault=22) then reject:=true;
                end;
                if (service=$41) and (fault=24) and (mem[ds:dx+3]=ord('$')) and
                   (mem[ds:dx+4]=ord('E')) and (mem[ds:dx+5]=ord('R')) then reject:=true;
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
        if armed and journal_active and (fault=20) and (service=$40) and (bx=journal_handle) then begin
                if r.cx>0 then dec(r.cx); inc(hits);
        end;
        { The original DOS vector is invoked through a private interrupt. }
        intr($60,r);
        if armed and (fault=15) and (service=$3E) and (bx=temp_handle) and (hits=0) then begin
                r.ax:=5; r.flags:=r.flags or 1; inc(hits);
        end;
        if armed and journal_active and (fault=23) and (service=$3E) and
           (bx=journal_handle) and (hits=0) then begin
                r.ax:=5; r.flags:=r.flags or 1; inc(hits);
        end;
        if armed and (service=$5B) and (r.flags and 1=0) and
           (mem[ds:dx+3]=ord('$')) and (mem[ds:dx+4]=ord('E')) then begin
                if mem[ds:dx+5]=ord('D') then temp_handle:=r.ax;
                if mem[ds:dx+5]=ord('R') then begin journal_handle:=r.ax; journal_active:=true end;
        end;
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
        hits:=0; renames:=0; temp_handle:=$FFFF; journal_handle:=$FFFF; journal_active:=false; fault:=kind; armed:=true;
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
        expect_file('C:\$ER0000.REC','OTHER_RECOVERY_RECORD');
        if kind in [8,9,11,12] then begin
                check(save_pending_files(sf),'failed cleanup remains pending');
                retry_save_cleanup(sf);
                check(not save_pending_files(sf),'retry settles transaction');
                check((sf.cleanup_error=0) and (sf.recovery_error=0),'retry clears secondary errors');
                if kind=11 then begin
                        expect_file('C:\SAVE.TXT',payload); expect_file('C:\SAVE.BAK',original);
                end else begin
                        expect_file('C:\SAVE.TXT',original); expect_file('C:\SAVE.BAK',older);
                end;
        end;
        remove(sf.temporary); remove(sf.previous_backup);
        writeln(output,'CASE ',kind,' PASS');
end;

procedure writer_lifecycle;
var ctx:TEditorContext; body:string; clipboard:array[0..8] of char;
    retained:TSaveFile;
begin
        kind:=16; FillChar(ctx,sizeof(ctx),0); FillChar(clipboard,sizeof(clipboard),0);
        strs.init(MT_DOS); new_file(ctx,''); body:='DOC_NEW';
        ctx.current^.rline:=strs.put(ctx.current^.rline,body);
        ctx.current^.cline:=ctx.current^.rline;
        body:='CLIP_NEW'; move(body[1],clipboard[0],length(body)); ctx.clipboard:=@clipboard;
        fixture('C:\SAVE.TXT',original); fixture('C:\SAVE.BAK',older);
        fault:=13; hits:=0; renames:=0; temp_handle:=$FFFF; armed:=true;
        strs.to_file(ctx.pending_save,'C:\SAVE.TXT',ctx.current^.rline,
                     ctx.current^.format,error,nil);
        check((error=5) and ctx.pending_save.opened,'caller owns failed document close');
        retained:=ctx.pending_save;
        check(save_clipboard(ctx,'C:\OTHER.TXT')=SAVE_PENDING,'clipboard cannot replace pending document save');
        strs.to_file(ctx.pending_save,'C:\OTHER.TXT',ctx.current^.rline,
                     ctx.current^.format,error,nil);
        check(error=SAVE_PENDING,'document cannot replace pending save');
        check((ctx.pending_save.handle=retained.handle) and
              (ctx.pending_save.temporary=retained.temporary) and
              (ctx.pending_save.destination=retained.destination) and ctx.pending_save.opened,
              'blocked writers preserve transaction ownership');
        expect_absent('C:\OTHER.TXT');
        armed:=false; retry_save_cleanup(ctx.pending_save);
        check(not save_pending_files(ctx.pending_save),'retained document handle can be settled');
        expect_file('C:\SAVE.TXT',original); expect_file('C:\SAVE.BAK',older);
        fault:=13; hits:=0; armed:=true;
        error:=save_clipboard(ctx,'C:\SAVE.TXT');
        check((error=5) and ctx.pending_save.opened,'caller owns failed clipboard close');
        armed:=false; retry_save_cleanup(ctx.pending_save);
        check(not save_pending_files(ctx.pending_save),'retained clipboard handle can be settled');
        check(save_clipboard(ctx,'C:\SAVE.TXT')=0,'clipboard retry after settled close');
        expect_file('C:\SAVE.TXT','CLIP_NEW'); expect_file('C:\SAVE.BAK',original);
        strs.free(ctx.current^.rline); undo_done(ctx.current^.history);
        FreeMem(ctx.current,sizeof(TFileContext)); strs.done;
        writeln(output,'CASE ',kind,' PASS');
end;

procedure path_lifecycle;
var previous,name:string; i:integer;
        procedure change_dir(name:string);
        begin
                {$I-} ChDir(name); {$I+}
                check(System.IOResult=0,'change directory: '+name);
        end;
begin
        kind:=17; GetDir(0,previous);
        {$I-} MkDir('C:\PATHOWN'); {$I+}
        check(System.IOResult=0,'create path fixture directory'); change_dir('C:\PATHOWN');
        fixture('C:\PATHOWN\SAVE.TXT',original);
        fixture('C:\PATHOWN\SAVE.BAK',older);
        start_save(sf,'SAVE.TXT',error);
        check((error=0) and (sf.destination='C:\PATHOWN\SAVE.TXT'),'relative destination expanded');
        change_dir('C:\');
        write_save(sf,payload[1],length(payload),error); finish_save(sf,error);
        check((error=0) and not save_pending_files(sf),'save survives directory change');
        expect_file('C:\PATHOWN\SAVE.TXT',payload);
        expect_file('C:\PATHOWN\SAVE.BAK',original);
        change_dir('C:\PATHOWN');
        name:=''; for i:=1 to 120 do name:=name+'.\'; name:=name+'SAVE.TXT';
        start_save(sf,name,error);
        check((error=3) and not save_pending_files(sf),'relative path overflow rejected before creation');
        expect_file('C:\PATHOWN\SAVE.TXT',payload);
        start_save(sf,'C:SAVE.TXT',error);
        check((error=0) and (sf.destination='C:\PATHOWN\SAVE.TXT'),'drive-relative destination expanded');
        cancel_save(sf); check(not save_pending_files(sf),'drive-relative cleanup');
        name:='\'; for i:=1 to 126 do name:=name+'.\'; name:=name+'AB';
        start_save(sf,name,error);
        check((error=3) and not save_pending_files(sf),'root-relative path overflow rejected');
        { DOS retains a current directory on each drive. Leave C's fixture
          before switching back to the original drive and removing it. }
        change_dir('C:\'); change_dir(previous);
        remove('C:\PATHOWN\SAVE.TXT'); remove('C:\PATHOWN\SAVE.BAK');
        {$I-} RmDir('C:\PATHOWN'); {$I+}
        check(System.IOResult=0,'remove path fixture directory');
        writeln(output,'CASE ',kind,' PASS');
end;

procedure journal_faults;
var info:TSaveRecord; file_in:file; got:word;
begin
        for kind:=18 to 24 do begin
                fixture('C:\SAVE.TXT',original); fixture('C:\SAVE.BAK',older);
                fault:=kind; hits:=0; renames:=0; temp_handle:=$FFFF;
                journal_handle:=$FFFF; journal_active:=false; armed:=true;
                start_save(sf,'C:\SAVE.TXT',error);
                if error=0 then begin
                        write_save(sf,payload[1],length(payload),error); finish_save(sf,error);
                end;
                armed:=false;
                if kind=24 then check(error=0,'publication succeeds despite journal removal error')
                else if kind=20 then check(error=101,'short journal write detected')
                else check(error=5,'journal DOS failure reported');
                check(hits>0,'journal fault reached actual DOS operation');
                if kind<>24 then begin
                        check(renames=0,'journal failure precedes every rename');
                        expect_file('C:\SAVE.TXT',original); expect_file('C:\SAVE.BAK',older);
                end else begin
                        expect_file('C:\SAVE.TXT',payload); expect_file('C:\SAVE.BAK',original);
                end;
                if kind in [22,24] then begin
                        check(save_pending_files(sf),'journal ownership remains pending');
                        check(sf.journal_opened=(kind=22),'journal handle ownership');
                        if kind=22 then begin
                                regs.ah:=$45; regs.bx:=sf.journal_handle; intr($21,regs);
                                check(regs.flags and 1=0,'journal handle still exists');
                                regs.bx:=regs.ax; regs.ah:=$3E; intr($21,regs);
                        end;
                        System.Assign(file_in,sf.journal); System.Reset(file_in,1);
                        System.BlockRead(file_in,info,sizeof(info),got); System.Close(file_in);
                        check((got=sizeof(info)) and valid_record(info,sf.journal),'retained recovery record validates');
                        check((info.payload_size=length(payload)) and
                              (info.payload_crc=(crc_update($FFFFFFFF,payload[1],length(payload)) xor $FFFFFFFF)),
                              'recovery record identifies payload');
                        retry_save_cleanup(sf);
                end;
                check(not save_pending_files(sf),'journal cleanup finishes');
                expect_file('C:\$ER0000.REC','OTHER_RECOVERY_RECORD');
                writeln(output,'CASE ',kind,' PASS');
        end;
end;

procedure reserved_destinations;
var name,backup,body:string; i:integer;
begin
        kind:=25;
        for i:=0 to 2 do begin
                case i of
                0:name:='C:\$ED0001.TMP';
                1:name:='C:\$er0001.rec';
                2:name:='C:\$EB0001.TMP';
                end;
                remove(name); backup:=backup_name(name); remove(backup);
                start_save(sf,name,error);
                check((error=0) and not same_path(sf.temporary,name),'payload creation excludes its destination');
                write_save(sf,payload[1],length(payload),error); finish_save(sf,error);
                check((error=0) and not save_pending_files(sf),'reserved-looking destination saves');
                expect_file(name,payload); fixture(backup,older);
                body:='CHANGED'; start_save(sf,name,error);
                write_save(sf,body[1],length(body),error); finish_save(sf,error);
                check((error=0) and not save_pending_files(sf),'reserved-looking destination replaces');
                expect_file(name,body); expect_file(backup,payload);
                remove(name); remove(backup);
        end;
        expect_file('C:\$ER0000.REC','OTHER_RECOVERY_RECORD');
        writeln(output,'CASE ',kind,' PASS');
end;

begin
        System.Assign(output,'A:\SAVE.LOG'); System.Rewrite(output); tests:=0; armed:=false; hooked:=false;
        payload:='NEW'+#9#128#255;
        fixture('C:\$EB0000.TMP','OTHER_BACKUP_TRANSACTION');
        fixture('C:\$ER0000.REC','OTHER_RECOVERY_RECORD');
        GetIntVec($21,old21); GetIntVec($60,old60);
        SetIntVec($60,old21); SetIntVec($21,@intercept); hooked:=true;
        for kind:=0 to 15 do run_case;
        writer_lifecycle; path_lifecycle; journal_faults; reserved_destinations;
        SetIntVec($21,old21); SetIntVec($60,old60); hooked:=false;
        remove('C:\$EB0000.TMP'); remove('C:\$ER0000.REC'); remove('C:\SAVE.TXT'); remove('C:\SAVE.BAK');
        writeln(output,'PASS ',tests,' assertions'); close(output);
        System.Assign(output,'A:\SAVE.OK'); System.Rewrite(output);
        writeln(output,'SAVE FAULTS PASS'); close(output);
end.
