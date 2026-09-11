{ SPDX-License-Identifier: MIT }
program sessprob;
uses sessboot,dos,dwedtype,dwedutil,dwedhndl,dwedscru,strs,unredo,event,kminput,
     safesave,dwedsave{$IFNDEF LEGACY_SESSION},dwedsess{$ENDIF};
var output:text; checks:longint; ctx:TEditorContext; e:TEvent;
    old21,old60:pointer; armed:boolean; fault,hits,temp_handle:word;
    first,second:PFileContext; redraw,error,i:integer; observed,saved_name:string;
const previous='PREVIOUS SESSION'#13#10;
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers; service:byte; reject:boolean;
begin
        service:=hi(ax); reject:=false;
        if armed then begin
                if bx=temp_handle then begin
                        if (fault=1) and (service=$40) then reject:=true;
                        if (fault=3) and (service=$68) then reject:=true;
                        if (fault=4) and (service=$3E) then reject:=true;
                end;
                if (fault=5) and (service=$56) then reject:=true;
                if (fault=6) and (service=$5B) and
                   (mem[ds:dx+3]=ord('$')) and (mem[ds:dx+5]=ord('R')) then reject:=true;
        end;
        if reject then begin inc(hits); ax:=5; flags:=flags or 1; exit end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        if armed and (fault=2) and (service=$40) and (bx=temp_handle) then begin
                if r.cx>0 then dec(r.cx); inc(hits);
        end;
        intr($60,r);
        if armed and (r.flags and 1=0) and
           (((service=$5B) and (mem[ds:dx+3]=ord('$')) and (mem[ds:dx+5]=ord('D'))) or
            (service=$3C)) then temp_handle:=r.ax;
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp;
        flags:=(flags and $0300) or (r.flags and $FCFF);
end;
procedure check(ok:boolean; message:string);
begin
        inc(checks);
        if not ok then begin
                armed:=false; SetIntVec($21,old21); SetIntVec($60,old60);
                writeln(output,'FAIL fault ',fault,' assertion ',checks,' ',message);
                close(output); session_boot_done; halt(1);
        end;
end;
procedure fixture;
var f:file; written:word;
begin
        System.Assign(f,ctx.temp); System.Rewrite(f,1);
        System.BlockWrite(f,previous[1],length(previous),written); System.Close(f);
        check(written=length(previous),'fixture complete');
end;
procedure expect_file(expected:string);
var f:file; got:word; actual:string;
begin
        System.Assign(f,ctx.temp); System.Reset(f,1);
        System.BlockRead(f,actual[1],255,got); System.Close(f); actual[0]:=chr(got);
        check(actual=expected,'checkpoint bytes');
end;
procedure retained;
begin
        check(ctx.all=second,'document list retained');
        check(ctx.current=first,'active document retained');
        check(second^.next=first,'document links retained');
        check(first^.editor.x=2,'cursor retained');
        check(first^.editor.selection and (first^.editor.sel_x=1),'selection retained');
        strs.get(first^.rline,observed); check(observed='ONE','first document retained');
        strs.get(second^.rline,observed); check(observed='TWO','second document retained');
        check(not first^.chg and not second^.chg,'clean states retained');
end;
begin
        System.Assign(output,'A:\SESS.LOG'); System.Rewrite(output);
        GetIntVec($21,old21); GetIntVec($60,old60);
        SetIntVec($60,old21); SetIntVec($21,@intercept);
        FillChar(ctx,sizeof(ctx),0); GetMem(ctx.clipboard,CB_SIZE); ctx.clipboard[0]:=#0;
        ctx.config.width:=80; ctx.config.height:=24; ctx.config.tab_size:=8;
        ctx.config.color.text:=$17; ctx.config.color.text_sel:=$70;
        ctx.ins:=true; strs.init(MT_DOS); ctx.temp:='A:\SESSION.TMP';
        new_file(ctx,'A:\ONE.TXT'); first:=ctx.current;
        observed:='ONE'; first^.cline:=strs.put(first^.cline,observed); first^.rline:=first^.cline;
        first^.scrline:=first^.cline; load_ed(ctx);
        first^.editor.x:=2; first^.editor.selection:=true; first^.editor.sel_x:=1;
        new_file(ctx,'A:\TWO.TXT'); second:=ctx.current;
        observed:='TWO'; second^.cline:=strs.put(second^.cline,observed); second^.rline:=second^.cline;
        second^.scrline:=second^.cline; load_ed(ctx); ctx.current:=first;
        ctx.config.udef_f5:='dir';
        for fault:=1 to 6 do begin
                fixture; temp_handle:=$FFFF; hits:=0; armed:=true;
                FillChar(e,sizeof(e),0); e.etype:=KEYBOARD; e.scancode:=SCAN_F5;
                redraw:=process_event(ctx,e);
                armed:=false;
                check(hits>0,'fault reached DOS');
                check(redraw<>SCRU_QUIT,'failed checkpoint prevents external exit');
                check(ctx.exit_code=0,'external execution not requested');
                retained; expect_file(previous);
                {$IFNDEF LEGACY_SESSION}
                if fault=4 then begin
                        check(ctx.session_save.opened,'failed close retains owner');
                        saved_name:=ctx.session_save.temporary;
                        error:=store_session(ctx);
                        check(error=SAVE_PENDING,'pending checkpoint cannot be overwritten');
                        check(ctx.session_save.temporary=saved_name,'pending filename retained');
                        armed:=true;
                        check(not pending_save_dialog(ctx,true),'open checkpoint cannot be kept on exit');
                        armed:=false; retained;
                        check(pending_save_dialog(ctx,false),'dialog retries close cleanup');
                end;
                retry_save_cleanup(ctx.session_save);
                check(not save_pending_files(ctx.session_save),'cleanup can retry');
                {$ENDIF}
                expect_file(previous);
        end;
        {$IFNDEF LEGACY_SESSION}
        saved_name:=first^.fname;
        first^.fname:=''; for i:=1 to 250 do first^.fname:=first^.fname+'x';
        check(store_session(ctx)=SESSION_FORMAT,'long metadata refused'); expect_file(previous);
        first^.fname:='BAD'+#13+'NAME';
        check(store_session(ctx)=SESSION_FORMAT,'record delimiter refused'); expect_file(previous);
        first^.fname:=saved_name;
        start_save(ctx.pending_save,'A:\DOC.TXT',error);
        check(error=0,'independent document transaction starts');
        saved_name:=ctx.pending_save.temporary;
        error:=store_session(ctx); check(error=0,'checkpoint retry succeeds'); retained;
        check(ctx.pending_save.opened and (ctx.pending_save.temporary=saved_name),
              'checkpoint preserves document transaction owner');
        cancel_save(ctx.pending_save);
        check(not save_pending_files(ctx.pending_save),'document transaction cleaned');
        expect_file('2,0,0,1,A:\ONE.TXT'#13#10+'1,0,0,1,A:\TWO.TXT'#13#10);
        check(not save_pending_files(ctx.session_save),'success leaves no recovery');
        {$ENDIF}
        SetIntVec($21,old21); SetIntVec($60,old60);
        strs.free(first^.rline); undo_done(first^.history); FreeMem(first,sizeof(TFileContext));
        strs.free(second^.rline); undo_done(second^.history); FreeMem(second,sizeof(TFileContext));
        FreeMem(ctx.clipboard,CB_SIZE);
        writeln(output,'PASS ',checks,' assertions'); close(output);
        System.Assign(output,'A:\SESS.OK'); System.Rewrite(output);
        writeln(output,'SESSION PASS'); close(output); session_boot_done;
end.
