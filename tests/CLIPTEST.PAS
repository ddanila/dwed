{ SPDX-License-Identifier: MIT }
program cliptest;
uses dos,cliptext,dwedtype,dwedutil,strs,strsdos,unredo,dwedundo,wincb;
var output:text; tests:longint; ctx:TEditorContext;
    buffer,guard:pchar; size,got:word; i,error:integer;
    body,suffix:string; f:file; old_vector:pointer;
    reported,fetched,copied,closed,copy_result,clear_result:word; nul_at:integer;

procedure check(ok:boolean; message:string);
begin
        inc(tests);
        if not ok then begin
                writeln(output,'FAIL ',tests,' ',message); close(output); halt(1);
        end;
end;

procedure put_text(s:string);
begin
        Move(s[1],buffer[0],length(s)); buffer[length(s)]:=#0;
end;

procedure write_input(count:word);
begin
        System.Assign(f,'C:\CLIPIN.TXT'); System.Rewrite(f,1);
        System.BlockWrite(f,buffer[0],count,got); System.Close(f);
        check(got=count,'fixture complete write');
end;

{ FPC 3.2.2 passes these stack slots in reverse declaration order. }
procedure fake_clipboard(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var j:word;
begin
        case ax of
        $1700:ax:=$0300;
        $1701:ax:=1;
        $1702:ax:=clear_result;
        $1703:begin copied:=cx; ax:=copy_result end;
        $1708:begin inc(closed); ax:=1 end;
        $1704:begin ax:=reported; dx:=0 end;
        $1705:begin
                inc(fetched);
                j:=0;
                while j<reported do begin mem[es:bx+j]:=ord('A'); inc(j) end;
                if (nul_at>=0) and (nul_at<reported) then mem[es:bx+nul_at]:=0;
                ax:=1;
        end;
        end;
end;

procedure host_case(count:word; terminator:integer; expected:boolean; transfers:word);
var ok:boolean;
begin
        reported:=count; nul_at:=terminator; fetched:=0; closed:=0;
        FillChar(guard[0],34,$CC);
        GetIntVec($2f,old_vector); SetIntVec($2f,@fake_clipboard);
        ok:=WCB_Paste(guard[1],32);
        SetIntVec($2f,old_vector);
        check(ok=expected,'host result'); check(fetched=transfers,'host transfer bound');
        check(closed=1,'host paste closes clipboard');
        check((ord(guard[0])=$CC) and (ord(guard[33])=$CC),'host buffer guards');
end;

procedure copy_case(count,result_code,clear_code:word; expected:boolean);
var ok:boolean;
begin
        copied:=0; closed:=0; copy_result:=result_code; clear_result:=clear_code;
        GetIntVec($2f,old_vector); SetIntVec($2f,@fake_clipboard);
        ok:=WCB_Copy(guard[1],count);
        SetIntVec($2f,old_vector);
        check(ok=expected,'host copy result');
        if clear_code<>0 then check(copied=count,'host copy exact transfer length')
        else check(copied=0,'host failed clear skips transfer');
        check(closed=1,'host copy closes clipboard');
end;

procedure refresh_case(terminator:integer; expected_error:integer);
begin
        ctx.clipboard[0]:='O'; ctx.clipboard[1]:=#0;
        reported:=32; nul_at:=terminator; ctx.has_wincb:=true;
        GetIntVec($2f,old_vector); SetIntVec($2f,@fake_clipboard);
        error:=refresh_clipboard(ctx);
        SetIntVec($2f,old_vector); ctx.has_wincb:=false;
        check(error=expected_error,'host refresh result');
        if error<>0 then check((ctx.clipboard[0]='O') and (ctx.clipboard[1]=#0),
                               'host failed refresh retains internal clipboard')
        else check((ctx.clipboard[0]='A') and (ctx.clipboard[31]=#0),
                   'host refresh publishes validated text');
end;

procedure expect_line(number:longint; expected:string);
var line:EditorStr; actual:string;
begin
        line:=strs.find_num(ctx.current^.rline,number);
        check(line<>nil,'result line exists'); strs.get(line,actual);
        check(actual=expected,'result line bytes');
end;

procedure apply;
var ok:boolean;
begin
        check(start_edit(ctx),'start edit');
        if setjmp(transaction_jump)=0 then begin
                ok:=replace_text(ctx,buffer,CB_SIZE,false);
                check(ok,'paste accepted'); finish_edit(ctx);
        end else begin transaction_cancel; check(false,'unexpected paste abort') end;
end;

begin
        System.Assign(output,'A:\CLIP.LOG'); System.Rewrite(output); tests:=0;
        GetMem(buffer,CB_SIZE+2); GetMem(guard,CB_SIZE+2);
        FillChar(ctx,sizeof(ctx),0); ctx.clipboard:=@guard[1];
        ctx.config.width:=80; ctx.config.height:=24;
        strs.init(MT_DOS);
        body:=''; for i:=1 to 255 do body:=body+'A'; put_text(body);
        check(clip_check(buffer,CB_SIZE,0,0,size)=0,'maximum line');
        check(clip_check(buffer,CB_SIZE,1,0,size)=CLIP_LONG_LINE,'prefix overflow');
        check(clip_check(buffer,CB_SIZE,0,1,size)=CLIP_LONG_LINE,'suffix overflow');
        put_text(#13#10);
        check(clip_check(buffer,CB_SIZE,255,255,size)=0,'newline separates long edges');
        put_text('a'+#13#10+'b'+#13+'c'+#10+#9#128#255);
        check(clip_check(buffer,CB_SIZE,1,1,size)=0,'newline and codepage forms');
        buffer[2]:=#0;
        check(clip_bytes(buffer,10)=CLIP_BAD_TEXT,'embedded NUL rejected');
        FillChar(buffer[0],CB_SIZE,'X');
        check(clip_length(buffer,CB_SIZE,size)=CLIP_TOO_LARGE,'unterminated bound');
        host_case(0,-1,false,0); host_case(33,-1,false,0);
        host_case(32,31,true,1); host_case(32,-1,false,1); host_case(32,2,true,1);
        copy_case(4,1,1,true); copy_case(32,$100,1,true);
        copy_case(4,0,1,false); copy_case(4,1,0,false);
        refresh_case(-1,CLIP_UNAVAILABLE); refresh_case(31,0);

        { Import accepts read-only and empty sources and never publishes a
          partial or invalid read. The clipboard itself has guard bytes. }
        FillChar(guard[0],CB_SIZE+2,$CC);
        ctx.clipboard[0]:='O'; ctx.clipboard[1]:='L'; ctx.clipboard[2]:='D'; ctx.clipboard[3]:=#0;
        FillChar(buffer[0],CB_SIZE,'X'); write_input(CB_SIZE);
        check(load_clipboard(ctx,'C:\CLIPIN.TXT')=CLIP_TOO_LARGE,'large import rejected');
        check((ctx.clipboard[0]='O') and (ctx.clipboard[3]=#0),'large import keeps clipboard');
        buffer[2]:=#0; write_input(5);
        check(load_clipboard(ctx,'C:\CLIPIN.TXT')=CLIP_BAD_TEXT,'binary import rejected');
        check(ctx.clipboard[0]='O','binary import keeps clipboard');
        write_input(0); SetFAttr(f,1); System.FileMode:=2;
        check(load_clipboard(ctx,'C:\CLIPIN.TXT')=0,'empty read-only import');
        check((ctx.clipboard[0]=#0) and (System.FileMode=2),'empty and file mode semantics');
        SetFAttr(f,0); FillChar(buffer[0],CB_SIZE-1,'X'); write_input(CB_SIZE-1);
        check(load_clipboard(ctx,'C:\CLIPIN.TXT')=0,'maximum clipboard import');
        check((ctx.clipboard[CB_SIZE-2]='X') and (ctx.clipboard[CB_SIZE-1]=#0),'maximum import bytes');
        check((ord(guard[0])=$CC) and (ord(guard[CB_SIZE+1])=$CC),'import guards');

        { Export uses the same replacement writer as document save. }
        ctx.clipboard[0]:='1'; ctx.clipboard[1]:=#9; ctx.clipboard[2]:=#255; ctx.clipboard[3]:=#0;
        check(save_clipboard(ctx,'C:\CBOUT.TXT')=0,'first export');
        ctx.clipboard[0]:='2';
        check(save_clipboard(ctx,'C:\CBOUT.TXT')=0,'replacement export');
        System.Assign(f,'C:\CBOUT.BAK'); System.Reset(f,1);
        System.BlockRead(f,buffer[0],CB_SIZE,got); System.Close(f);
        check((got=3) and (buffer[0]='1') and (buffer[1]=#9) and (buffer[2]=#255),'export backup bytes');
        System.Assign(f,'C:\CBOUT.TXT'); System.Reset(f,1);
        System.BlockRead(f,buffer[0],CB_SIZE,got); System.Close(f);
        check((got=3) and (buffer[0]='2') and (buffer[1]=#9) and (buffer[2]=#255),'export destination bytes');

        { Real paste, undo and redo retain every logical line and raw byte. }
        new_file(ctx,''); body:='HEADTAIL'; ctx.current^.cline:=strs.put(ctx.current^.cline,body);
        ctx.current^.rline:=ctx.current^.cline; ctx.current^.total:=strs.renum(ctx.current^.rline);
        load_ed(ctx); ctx.current^.editor.x:=5;
        put_text('a'+#13#10+'b'+#13+'c'+#10+#9#128#255); apply;
        check(ctx.current^.total=4,'mixed separator line count');
        expect_line(1,'HEADa'); expect_line(2,'b'); expect_line(3,'c'); expect_line(4,#9#128#255+'TAIL');
        error:=replay_edit(ctx,false); expect_line(1,'HEADTAIL');
        check(ctx.current^.total=1,'paste undo line count');
        error:=replay_edit(ctx,true); expect_line(4,#9#128#255+'TAIL');
        strs.free(ctx.current^.rline); undo_done(ctx.current^.history);
        FreeMem(ctx.current,sizeof(TFileContext)); ctx.current:=nil; ctx.all:=nil;
        new_file(ctx,''); body:=''; for i:=1 to 200 do body:=body+'A';
        ctx.current^.cline:=strs.put(ctx.current^.cline,body); ctx.current^.rline:=ctx.current^.cline;
        suffix:=''; for i:=1 to 200 do suffix:=suffix+'B';
        ctx.current^.cline:=strs.create(nil,ctx.current^.cline,suffix);
        ctx.current^.total:=strs.renum(ctx.current^.rline); load_ed(ctx);
        ctx.current^.editor.x:=1; ctx.current^.editor.selection:=true;
        ctx.current^.editor.sel_row:=1; ctx.current^.editor.sel_x:=201;
        put_text('');
        check(replace_text(ctx,buffer,CB_SIZE,false),'empty paste accepted');
        check(ctx.current^.editor.selection,'empty paste retains selection');
        expect_line(1,body); expect_line(2,suffix);
        put_text(#13#10); apply;
        expect_line(1,body); expect_line(2,suffix);
        check(ctx.current^.total=2,'valid replacement avoids oversized intermediate join');
        strs.free(ctx.current^.rline); undo_done(ctx.current^.history);
        FreeMem(ctx.current,sizeof(TFileContext));
        FreeMem(buffer,CB_SIZE+2); FreeMem(guard,CB_SIZE+2);
        writeln(output,'PASS ',tests,' assertions'); close(output);
        System.Assign(output,'A:\CLIP.OK'); System.Rewrite(output);
        writeln(output,'CLIPBOARD PASS'); close(output);
end.
