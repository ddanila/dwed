{ SPDX-License-Identifier: MIT }
program tabtest;
uses dos,textcell,dwedtype,dwedutil,dwedhndl,dwedscru,strs,unredo,event,kminput,scr;
var output:text; checks:longint; ctx:TEditorContext; e:TEvent;
    body,expected,actual:string; i,j,k,width,n,column,redraw:integer;
    model:array[0..8191] of char; positions:array[1..256] of integer;
    line:EditorStr;
procedure check(ok:boolean; message:string);
begin
        inc(checks);
        if not ok then begin writeln(output,'FAIL ',checks,' ',message); close(output); halt(1) end;
end;
procedure key(scan:byte; modifiers:word);
begin
        FillChar(e,sizeof(e),0); e.etype:=KEYBOARD; e.scancode:=scan; e.ctrl_keys:=modifiers;
        redraw:=process_event(ctx,e); dwedscru.update(ctx,redraw);
end;
procedure expect_position(row:longint; byte_column,visual:integer);
begin
        check(strs.get_num(ctx.current^.cline)=row,'cursor row');
        check(ctx.current^.editor.x=byte_column,'cursor byte');
        check(cell_of(ctx.current^.editor.line,ctx.current^.editor.x,8)=visual,'cursor cell');
end;
procedure expect_body(expected:string);
begin
        check(ctx.current^.editor.line=expected,'edited bytes');
end;
procedure reset_document;
begin
        if ctx.current<>nil then begin
                strs.free(ctx.current^.rline); undo_done(ctx.current^.history);
                FreeMem(ctx.current,sizeof(TFileContext)); ctx.current:=nil; ctx.all:=nil;
        end;
        new_file(ctx,'');
end;
procedure first_line(s:string);
begin
        ctx.current^.cline:=strs.put(ctx.current^.cline,s);
        ctx.current^.rline:=ctx.current^.cline; ctx.current^.scrline:=ctx.current^.cline;
        load_ed(ctx);
end;
procedure check_enter(source,indent:string);
var position:integer; prefix,left,right,observed:string; first,second:EditorStr;
begin
        for position:=1 to length(source)+1 do begin
                reset_document; first_line(source);
                ctx.current^.editor.x:=position;
                prefix:=copy(indent,1,position-1);
                left:=copy(source,1,position-1);
                right:=prefix+copy(source,position,255);
                key(SCAN_ENTER,0);
                first:=ctx.current^.rline; second:=strs.go_next(first);
                strs.get(first,observed); check(observed=left,'Enter preserves left bytes');
                strs.get(second,observed); check(observed=right,'Enter preserves suffix and literal indentation');
                check(strs.is_last(second),'Enter inserts exactly one line');
                check(ctx.current^.editor.x=length(prefix)+1,'Enter cursor follows indentation');
                check(ctx.current^.chg,'Enter marks document dirty');
                key(SCAN_Z,key_ctrl);
                check(strs.is_last(ctx.current^.rline),'undo Enter restores line count');
                strs.get(ctx.current^.rline,observed); check(observed=source,'undo Enter restores all bytes');
                check(ctx.current^.editor.x=position,'undo Enter restores cursor');
                check(not ctx.current^.chg,'undo Enter restores clean state');
                key(SCAN_Z,key_ctrl or key_shift);
                first:=ctx.current^.rline; second:=strs.go_next(first);
                strs.get(first,observed); check(observed=left,'redo Enter restores left');
                strs.get(second,observed); check(observed=right,'redo Enter restores indentation and suffix');
                check(ctx.current^.editor.x=length(prefix)+1,'redo Enter restores cursor');
        end;
end;
begin
        System.Assign(output,'A:\TAB.LOG'); System.Rewrite(output); checks:=0;
        { Compare bounded rendering and mappings with an independently expanded
          array. Include long visual lines which cannot fit a Pascal string. }
        for width:=1 to 32 do begin
                body:='A'+#9+'B'+#9#9+#128#255+' end';
                n:=0;
                for i:=1 to length(body) do begin
                        positions[i]:=n;
                        if body[i]=#9 then begin
                                repeat model[n]:=' '; inc(n) until n mod width=0;
                        end else begin model[n]:=body[i]; inc(n) end;
                end;
                positions[length(body)+1]:=n;
                for i:=1 to length(body)+1 do
                        check(cell_of(body,i,width)=positions[i],'byte to expanded model');
                for column:=0 to n+2 do begin
                        k:=1;
                        for i:=1 to length(body)+1 do if positions[i]<=column then k:=i;
                        check(byte_at_cell(body,column,width)=k,'cell to expanded model');
                        expected:='';
                        for j:=column to column+7 do if j<n then expected:=expected+model[j];
                        check(cell_slice(body,column,8,width)=expected,'clipped expanded model');
                end;
        end;
        body:=''; for i:=1 to 255 do body:=body+#9;
        check(cell_of(body,256,32)=8160,'maximum visual width');
        check(length(cell_slice(body,8000,80,32))=80,'far horizontal slice');
        check(byte_at_cell(body,8159,32)=255,'last tab interior');
        check(byte_at_cell(body,8160,32)=256,'last tab end');
        check(cell_of(#9,2,0)=8,'zero tab width normalized');
        check(cell_of(#9,2,33)=8,'large tab width normalized');
        check(indent_bytes('  '+#9+'A',8)=3,'mixed indentation prefix');
        check(indent_bytes(#9+'  A',8)=1,'one tab indent level');
        check(indent_bytes('          A',8)=8,'space indent level');
        check(indent_bytes('A',8)=0,'text is not indentation');

        FillChar(ctx,sizeof(ctx),0); GetMem(ctx.clipboard,CB_SIZE); ctx.clipboard[0]:=#0;
        ctx.config.width:=80; ctx.config.height:=24; ctx.config.tab_size:=8;
        ctx.config.color.text:=$17; ctx.config.color.text_sel:=$70;
        ctx.ins:=true; strs.init(MT_DOS); reset_document;
        first_line('A'+#9+'B'); line:=ctx.current^.cline;
        body:='0123456789ABC'; line:=strs.create(nil,line,body);
        body:='xy'; line:=strs.create(nil,line,body);
        body:=#9#9+'Z'; line:=strs.create(nil,line,body);
        ctx.current^.total:=strs.renum(ctx.current^.rline);
        key(SCAN_RIGHT,0); key(SCAN_RIGHT,0); expect_position(1,3,8);
        key(SCAN_DOWN,0); expect_position(2,9,8);
        key(SCAN_DOWN,0); expect_position(3,3,2);
        key(SCAN_DOWN,0); expect_position(4,2,8);
        key(SCAN_UP,0); key(SCAN_UP,0); key(SCAN_UP,0); expect_position(1,3,8);
        key(SCAN_HOME,0); key(SCAN_RIGHT,0);
        key(SCAN_RIGHT,key_shift);
        for i:=1 to 7 do check(ord(scr.screen[(80+i)*2+1])=$70,'whole tab selected');
        check(ord(scr.screen[(80+8)*2+1])=$17,'next byte not selected');
        key(SCAN_C,key_ctrl);
        check((ctx.clipboard[0]=#9) and (ctx.clipboard[1]=#0),'tab copy remains one byte');
        key(SCAN_HOME,0); key(SCAN_RIGHT,0);
        key(SCAN_TAB,0); expect_body('A'+#9#9+'B'); expect_position(1,3,8);
        key(SCAN_Z,key_ctrl); expect_body('A'+#9+'B');
        key(SCAN_Z,key_ctrl or key_shift); expect_body('A'+#9#9+'B');
        key(SCAN_Z,key_ctrl);
        { Direct event injection checks the editor mapping, not a DOS driver. }
        FillChar(e,sizeof(e),0); e.etype:=MOUSE_PRESS_B1; e.mouse_x:=6; e.mouse_y:=1;
        redraw:=process_event(ctx,e); expect_position(1,2,1);
        FillChar(e,sizeof(e),0); e.etype:=MOUSE_MOVE; e.mouse_left:=true;
        e.mouse_x:=8; e.mouse_y:=1; redraw:=process_event(ctx,e); dwedscru.update(ctx,redraw);
        expect_position(1,3,8); check(ctx.current^.editor.selection,'single move starts drag');
        for i:=1 to 7 do check(ord(scr.screen[(80+i)*2+1])=$70,'mouse selects tab cells');
        reset_document; body:=''; for i:=1 to 40 do body:=body+#9;
        body:=body+'Z'; first_line(body); key(SCAN_END,0);
        expect_position(1,42,321); check(ctx.current^.scrx=242,'scroll uses visual cells');
        check(scr.screen[(80+78)*2]='Z','clipped long visual line');
        FillChar(e,sizeof(e),0); e.etype:=MOUSE_PRESS_B1; e.mouse_x:=78; e.mouse_y:=1;
        redraw:=process_event(ctx,e); expect_position(1,41,320);
        key(SCAN_HOME,0); check(ctx.current^.scrx=0,'home restores viewport');
        reset_document; first_line(#9+'A'); key(SCAN_RIGHT,0);
        key(SCAN_TAB,key_shift); expect_body('A'); expect_position(1,1,0);
        key(SCAN_Z,key_ctrl); expect_body(#9+'A'); expect_position(1,2,8);
        key(SCAN_HOME,0); key(SCAN_END,key_shift); key(SCAN_TAB,0);
        expect_body('        '+#9+'A');
        check(ctx.current^.editor.sel_x=9,'indent retains selected original bytes');
        key(SCAN_TAB,key_shift); expect_body(#9+'A');
        check(ctx.current^.editor.sel_x=1,'unindent restores selection boundary');
        key(SCAN_Z,key_ctrl); expect_body('        '+#9+'A');
        key(SCAN_Z,key_ctrl); expect_body(#9+'A');
        { Known prefixes provide an independent expected split for every byte
          boundary, including boundaries inside indentation and full lines. }
        check_enter('','');
        check_enter('A  B','');
        check_enter('  A  B','  ');
        check_enter(#9+'A  B',#9);
        check_enter(' '+#9+' A '+#128#255,' '+#9+' ');
        check_enter(' '+#9+' ',' '+#9+' ');
        body:=''; for i:=1 to 255 do body:=body+' ';
        check_enter(body,body);
        body:=' '+#9; for i:=3 to 255 do body:=body+'x';
        check_enter(body,' '+#9);
        strs.free(ctx.current^.rline); undo_done(ctx.current^.history);
        FreeMem(ctx.current,sizeof(TFileContext)); FreeMem(ctx.clipboard,CB_SIZE);
        writeln(output,'PASS ',checks,' assertions'); close(output);
        System.Assign(output,'A:\TAB.OK'); System.Rewrite(output);
        writeln(output,'TAB DISPLAY PASS'); close(output);
end.
