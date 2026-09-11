{ MIT License

Copyright (c) 2020 Viacheslav Komenda

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. }
unit dwedutil;

interface

uses dwedtype;

type
pfast_jmp_list = ^fast_jmp_list;
fast_jmp_list = record
        text : string[80];
        line : dword;
        next : pfast_jmp_list;
end;

procedure get_sel_coord(
        var ctx : TEditorContext;
        var sb_x : integer;
        var sb_y : dword;
        var se_x : integer;
        var se_y : dword);

function norm_xy(var ctx : TEditorContext; r : integer) : integer;

procedure commit(var ctx : TEditorContext);
procedure load_ed(var ctx : TEditorContext);

function go_line_begin(var ctx : TEditorContext) : integer;
function go_line_end(var ctx : TEditorContext) : integer;
function go_line_up(var ctx : TEditorContext) : integer;
function go_line_down(var ctx : TEditorContext) : integer;
function go_char_left(var ctx : TEditorContext) : integer;
function go_char_right(var ctx : TEditorContext) : integer;
function go_word_left(var ctx : TEditorContext) : integer;
function go_word_right(var ctx : TEditorContext) : integer;
function go_page_up(var ctx : TEditorContext) : integer;
function go_page_down(var ctx : TEditorContext) : integer;

function change_indent(var ctx:TEditorContext; reverse:boolean):boolean;
function copy_selected(var ctx : TEditorContext):boolean;
function delete_selected(var ctx : TEditorContext):boolean;
function selection_fits(var ctx:TEditorContext):boolean;
function replace_text(var ctx:TEditorContext; p:pchar; capacity:word;
                      allow_empty:boolean):boolean;
function refresh_clipboard(var ctx:TEditorContext):integer;
function save_clipboard(var ctx : TEditorContext; fname:string) : integer;
function load_clipboard(var ctx : TEditorContext; fname:string) : integer;
procedure go_win_list(var ctx:TEditorContext);

function mk_short_name(fname : string) : string;

function new_file(var ctx : TEditorContext; fname : string):integer;
function load_file(var ctx : TEditorContext; fname : string; var errCode : integer; percent_proc : pointer) : integer;

procedure load_file_progress(value, total, start_time : dword);
procedure save_file_progress(value, total, start_time : dword);

procedure handle_error(var ctx : TEditorContext; errCode:integer);

function create_fast_jmp_list(var ctx:TEditorContext) : pfast_jmp_list;
function fast_jmp(var ctx:TEditorContext; fjl : pfast_jmp_list) : integer;

function get_err_msg(errCode:integer) : string;

function get_ticks : longint;

implementation

uses system2, wincb, kminput, event, cstring, scr, scrui, strs, str, dwedhl, dwedlnch, unredo, cliptext, safesave, textcell, dosread;

function get_ticks : longint;
begin
     get_ticks := meml[Seg0040:$006c];
end;

procedure commit(var ctx : TEditorContext);
begin
        with ctx.current^ do begin
                if not editor.chg then exit;
                cline := strs.put(cline, editor.line);
                if strs.is_first(cline) then rline := cline;
                if scry = 0 then scrline := cline;
                chg := true;
                editor.chg := false;
        end;
end;

procedure load_ed(var ctx : TEditorContext);
begin
        with ctx.current^ do begin
                strs.get(cline, editor.line);
        end;
end;

function norm_xy(var ctx : TEditorContext; r : integer) : integer;
var i, x, old_scrx, cell: integer;
begin
        old_scrx := ctx.current^.scrx;
        with ctx.current^ do begin
                scrline := cline;
                if scrx < 0 then scrx := 0;
                if scry < 0 then scry := 0;
                if editor.x < 1 then editor.x := 1;
                if editor.x > length(editor.line) + 1 then editor.x := length(editor.line) + 1;
                if strs.is_first(cline) then begin scrline := cline; scry := 0; end;
                if scry <> 0 then begin
                        i := scry;
                        x := 0;
                        scrline := cline;
                        while i > 0 do begin
                                if strs.is_first(scrline) then begin
                                        ctx.current^.scry := x;
                                        break;
                                end;
                                scrline := strs.go_prev(scrline);
                                inc(x);
                                dec(i);
                        end;
                end;
                cell:=cell_of(editor.line,editor.x,config^.tab_size);
                if scrx>cell then scrx:=cell;
                if cell>=scrx+config^.width then scrx:=cell-config^.width+1;
        end;
        if old_scrx <> ctx.current^.scrx then r := SCRU_FULL;
        norm_xy := r;
end;

function go_line_begin(var ctx : TEditorContext) : integer;
var r : integer;
begin
        r := SCRU_CLINE;
        with ctx.current^ do begin
                editor.x := 1;
                if scrx <> 0 then begin
                        scrx := 0;
                        r := SCRU_FULL;
                end;
        end;
        go_line_begin := r;
end;

function go_line_end(var ctx : TEditorContext) : integer;
begin
        with ctx.current^ do begin
                editor.x := length(editor.line) + 1;
                go_line_end := SCRU_CLINE;
        end;
end;

function go_line_up(var ctx : TEditorContext) : integer;
var r : integer;
begin
        r := SCRU_NONE;
        if ctx.current^.editor.desired_cell<0 then with ctx.current^ do
                editor.desired_cell:=cell_of(editor.line,editor.x,config^.tab_size);
        commit(ctx);
        with ctx.current^ do begin
                if not strs.is_first(cline) then begin
                        if scry <> 0 then begin
                                dec(scry);
                                r := SCRU_CLINE;
                        end else begin
                                r := SCRU_SD;
                        end;
                        cline := strs.go_prev(cline);
                        if editor.selection then r := SCRU_FULL;
                end;
        end;
        load_ed(ctx);
        with ctx.current^ do
                editor.x:=byte_at_cell(editor.line,editor.desired_cell,config^.tab_size);
        go_line_up := r;
end;

function go_line_down(var ctx : TEditorContext) : integer;
var r : integer;
begin
        r := SCRU_NONE;
        if ctx.current^.editor.desired_cell<0 then with ctx.current^ do
                editor.desired_cell:=cell_of(editor.line,editor.x,config^.tab_size);
        commit(ctx);
        with ctx.current^ do begin
                if not strs.is_last(cline) then begin
                        if config^.height - 2 > scry then begin
                                inc(scry);
                                r := SCRU_CLINE;
                        end else begin
                                r := SCRU_SU;
                        end;
                        cline := strs.go_next(cline);
                        if editor.selection then r := SCRU_FULL;
                end;
        end;
        load_ed(ctx);
        with ctx.current^ do
                editor.x:=byte_at_cell(editor.line,editor.desired_cell,config^.tab_size);
        go_line_down := r;
end;

function go_char_left(var ctx : TEditorContext) : integer;
var r, i : integer;
begin
        r := SCRU_NONE;
        if ctx.current^.editor.x <> 1 then begin
                r := SCRU_CLINE;
                dec(ctx.current^.editor.x);
        end else if not strs.is_first(ctx.current^.cline) then begin
                commit(ctx);
                r := go_line_up(ctx);
                i := go_line_end(ctx);
                load_ed(ctx);
                if r < i then r := i;
        end;
        go_char_left := r;
end;

function go_char_right(var ctx : TEditorContext) : integer;
var r, i : integer;
begin
        r := SCRU_NONE;
        if ctx.current^.editor.x <= length(ctx.current^.editor.line) then begin
                r := SCRU_CLINE;
                inc(ctx.current^.editor.x);
        end else if not strs.is_last(ctx.current^.cline) then begin
                commit(ctx);
                if ctx.current^.scrx <> 0 then r := SCRU_FULL;
                with ctx.current^ do begin
                        editor.x := 1;
                        scrx := 0;
                end;
                i := go_line_down(ctx);
                load_ed(ctx);
                if r < i then r := i;
        end;
        go_char_right := r;
end;

function is_split_chr(c : char):boolean;
begin
        is_split_chr := c in ['(', ')', '[', ']', '.', ',', ' '];
end;

function go_word_left(var ctx : TEditorContext) : integer;
var r : integer;
begin
        r := SCRU_NONE;
        if ctx.current^.editor.x = 1 then begin
                if not strs.is_first(ctx.current^.cline) then begin
                        commit(ctx);
                        ctx.current^.cline := strs.go_prev(ctx.current^.cline);
                        load_ed(ctx);
                        with ctx.current^ do begin
                                editor.x := length(editor.line) + 1;
                                if scry <> 0 then dec(scry);
                        end;
                        r := SCRU_FULL;
                end;
        end else begin
                with ctx.current^ do begin
                        if editor.x > length(editor.line) then editor.x := length(editor.line);
                        dec(editor.x);
                        if editor.x > 1 then begin
                                while (editor.x > 1)
                                        and (editor.line[editor.x] <= ' ')
                                        do begin
                                        dec(editor.x);
                                end;
                                while (editor.x > 1)
                                        and (editor.line[editor.x] > ' ')
                                        do begin
                                        if is_split_chr(editor.line[editor.x]) then break;
                                        dec(editor.x);
                                end;
                        end;
                end;
                r := SCRU_CLINE;
        end;
        go_word_left := r;
end;

function go_word_right(var ctx : TEditorContext) : integer;
var r : integer;
        state : boolean;
begin
        r := SCRU_NONE;
        if ctx.current^.editor.x = length(ctx.current^.editor.line) + 1 then begin
                if not strs.is_last(ctx.current^.cline) then begin
                        commit(ctx);
                        ctx.current^.cline := strs.go_next(ctx.current^.cline);
                        load_ed(ctx);
                        with ctx.current^ do begin
                                editor.x := 1;
                                if scry <> config^.height-2 then inc(scry);
                        end;
                        r := SCRU_FULL;
                end;
        end else begin
                with ctx.current^ do begin
                        if editor.x > length(editor.line) then editor.x := length(editor.line);
                        inc(editor.x);
                        if editor.x < length(editor.line) then begin
                                if editor.line[editor.x] <= ' ' then begin
                                        while (editor.x < length(editor.line))
                                                and (editor.line[editor.x] <= ' ')
                                                do inc(editor.x); 
                                end else begin
                                        while (editor.x < length(editor.line))
                                                and (editor.line[editor.x] > ' ')
                                                do begin
                                                if is_split_chr(editor.line[editor.x]) then break;
                                                inc(editor.x);
                                        end;
                                        while (editor.x < length(editor.line))
                                                and (editor.line[editor.x] <= ' ')
                                                do begin
                                                inc(editor.x);
                                        end;
                                end;
                        end;
                end;
                r := SCRU_CLINE;
        end;
        go_word_right := r;
end;

function go_page_up(var ctx : TEditorContext) : integer;
var i : integer;
begin
        commit(ctx);
        with ctx.current^ do begin
                if (scrx <> 0) or (scry <> 0) or (editor.x <> 1) then begin
                        i := scry;
                end else begin
                        i := config^.height - 2;
                end;
                while (i <> 0) and (not strs.is_first(cline)) do begin
                        cline := strs.go_prev(cline);
                        dec(i);
                end;
                scrx := 0;
                scry := 0;
                editor.x := 1;
        end;
        load_ed(ctx);
        go_page_up := SCRU_FULL;
end;

function go_page_down(var ctx : TEditorContext) : integer;
var i : integer;
begin
        commit(ctx);
        with ctx.current^ do begin
                if (scrx <> 0) or (scry <> config^.height-2) 
                 or (editor.x <> 1) then begin
                        i := config^.height-2 - scry;
                end else begin
                        i := config^.height - 2;
                end;
                while (i <> 0) and (not strs.is_last(cline)) do begin
                        cline := strs.go_next(cline);
                        dec(i);
                end;
                scrx := 0;
                editor.x := 1;
                scry := config^.height-2;
        end;
        load_ed(ctx);
        go_page_down := SCRU_FULL;
end;

procedure get_sel_coord(
        var ctx : TEditorContext;
        var sb_x : integer;
        var sb_y : dword;
        var se_x : integer;
        var se_y : dword);
var x : integer;
        y        : dword;
begin
        commit(ctx);
        with ctx.current^ do begin
                if not editor.selection then exit;
                sb_y := editor.sel_row;
                sb_x := editor.sel_x;
                se_y := strs.get_num(cline);
                se_x := editor.x;
        end;
        if (sb_y > se_y) or ((sb_y = se_y) and (sb_x > se_x)) then begin
                x := sb_x;
                y := sb_y;
                sb_x := se_x;
                sb_y := se_y;
                se_x := x;
                se_y := y;
        end;
end;

function save_clipboard(var ctx:TEditorContext; fname:string):integer;
var error:integer; size:word;
begin
        if save_pending_files(ctx.pending_save) then begin save_clipboard:=SAVE_PENDING; exit end;
        error:=clip_length(ctx.clipboard,CB_SIZE,size);
        if error=0 then begin
                start_save(ctx.pending_save,fname,error);
                if error=0 then begin
                        write_save(ctx.pending_save,ctx.clipboard[0],size,error);
                        finish_save(ctx.pending_save,error);
                end;
        end;
        save_clipboard:=error;
end;

function load_clipboard(var ctx:TEditorContext; fname:string):integer;
var f:file; p:pchar; size:longint; got,allocated:word;
    error,close_error:integer; previous_mode:byte; extra:byte;
begin
        p:=nil; allocated:=0; size:=0;
        System.Assign(f,fname);
        previous_mode:=System.FileMode; System.FileMode:=0;
        {$I-} System.Reset(f,1); {$I+}
        error:=System.IOResult; System.FileMode:=previous_mode;
        if error=0 then begin
                {$I-} size:=System.FileSize(f); {$I+}
                error:=System.IOResult;
                if (error=0) and (size>=CB_SIZE) then error:=CLIP_TOO_LARGE;
                if error=0 then begin
                        allocated:=size+1;
                        if MaxAvail<allocated then error:=8
                        else GetMem(p,allocated);
                end;
                if error=0 then begin
                        {$I-} System.BlockRead(f,p[0],size,got); {$I+}
                        error:=System.IOResult;
                        if (error=0) and (got<>size) then error:=CLIP_READ_CHANGED;
                end;
                if error=0 then begin
                        {$I-} System.BlockRead(f,extra,1,got); {$I+}
                        error:=System.IOResult;
                        if (error=0) and (got<>0) then error:=CLIP_READ_CHANGED;
                end;
                {$I-} System.Close(f); {$I+}
                close_error:=System.IOResult;
                if error=0 then error:=close_error;
        end;
        if error=0 then error:=clip_bytes(p,size);
        if error=0 then begin
                p[size]:=#0;
                if ctx.has_wincb then
                        if not WCB_Copy(p[0],size+1) then error:=CLIP_UNAVAILABLE;
                if error=0 then Move(p[0],ctx.clipboard[0],size+1);
        end;
        if p<>nil then FreeMem(p,allocated);
        load_clipboard:=error;
end;

function change_indent(var ctx:TEditorContext; reverse:boolean):boolean;
var first_row,last_row,number,current_row:longint;
    first_col,last_col,width,delta,i:integer; line:EditorStr; body,prefix:string;
begin
        change_indent:=true; commit(ctx);
        current_row:=strs.get_num(ctx.current^.cline);
        first_row:=current_row; last_row:=current_row;
        if ctx.current^.editor.selection then begin
                get_sel_coord(ctx,first_col,first_row,last_col,last_row);
                if last_col=1 then dec(last_row);
        end;
        width:=tab_width(ctx.current^.config^.tab_size);
        if not reverse then begin
                { Preflight the whole range before publishing any indentation. }
                line:=strs.find_num(ctx.current^.rline,first_row);
                for number:=first_row to last_row do begin
                        strs.get(line,body);
                        if length(body)+width>255 then begin
                                handle_error(ctx,CLIP_LONG_LINE); change_indent:=false; exit;
                        end;
                        line:=strs.go_next(line);
                end;
        end;
        prefix:=''; for i:=1 to width do prefix:=prefix+' ';
        for number:=first_row to last_row do begin
                line:=strs.find_num(ctx.current^.rline,number); strs.get(line,body);
                if reverse then begin
                        delta:=-indent_bytes(body,width);
                        System.delete(body,1,-delta);
                end else begin delta:=width; body:=prefix+body end;
                if delta<>0 then with ctx.current^ do begin
                        line:=strs.put(line,body);
                        if number=1 then rline:=line;
                        if number=current_row then begin
                                cline:=line; inc(editor.x,delta);
                                if editor.x<1 then editor.x:=1;
                        end;
                        if editor.selection and (number=editor.sel_row) then begin
                                inc(editor.sel_x,delta); if editor.sel_x<1 then editor.sel_x:=1;
                        end;
                        chg:=true;
                end;
        end;
        load_ed(ctx);
end;

function copy_selected(var ctx:TEditorContext):boolean;
var sb_y,se_y,number,total:longint; sb_x,se_x,first,last,pass,error:integer;
    line:EditorStr; body,part:string; position,size:word; dest:pchar;
begin
        copy_selected:=false;
        if not ctx.current^.editor.selection then exit;
        get_sel_coord(ctx,sb_x,sb_y,se_x,se_y);
        total:=0; error:=0; dest:=nil; size:=0;
        for pass:=1 to 2 do begin
                line:=strs.find_num(ctx.current^.rline,sb_y);
                number:=sb_y; position:=0;
                while number<=se_y do begin
                        strs.get(line,body); first:=1; last:=length(body);
                        if number=sb_y then first:=sb_x;
                        if number=se_y then last:=se_x-1;
                        part:=copy(body,first,last-first+1);
                        if pass=1 then begin
                                error:=clip_bytes(@part[1],length(part));
                                if error<>0 then break;
                                inc(total,length(part));
                                if number<se_y then inc(total,2);
                                if total>=CB_SIZE then begin error:=CLIP_TOO_LARGE; break end;
                        end else begin
                                Move(part[1],dest[position],length(part));
                                inc(position,length(part));
                                if number<se_y then begin
                                        dest[position]:=#13; dest[position+1]:=#10;
                                        inc(position,2);
                                end;
                        end;
                        inc(number); line:=strs.go_next(line);
                end;
                if error<>0 then break;
                if pass=1 then begin
                        size:=total+1;
                        if ctx.has_wincb then begin
                                if MaxAvail<size then begin error:=8; break end;
                                GetMem(dest,size);
                        end else dest:=ctx.clipboard;
                end;
        end;
        if error=0 then begin
                dest[total]:=#0;
                if ctx.has_wincb then begin
                        if not WCB_Copy(dest[0],total+1) then error:=CLIP_UNAVAILABLE;
                        if error=0 then Move(dest[0],ctx.clipboard[0],total+1);
                end;
        end;
        if (dest<>nil) and ctx.has_wincb then FreeMem(dest,size);
        if error<>0 then handle_error(ctx,error) else copy_selected:=true;
end;

procedure selection_edges(var ctx:TEditorContext; var first_line,last_line:longint;
                          var prefix,suffix:string);
var first_col,last_col:integer; line:EditorStr; body:string;
begin
        if ctx.current^.editor.selection then
                get_sel_coord(ctx,first_col,first_line,last_col,last_line)
        else begin
                first_col:=ctx.current^.editor.x; last_col:=first_col;
                first_line:=strs.get_num(ctx.current^.cline); last_line:=first_line;
        end;
        line:=strs.find_num(ctx.current^.rline,first_line); strs.get(line,body);
        prefix:=copy(body,1,first_col-1);
        line:=strs.find_num(ctx.current^.rline,last_line); strs.get(line,body);
        suffix:=copy(body,last_col,length(body)-last_col+1);
end;

function selection_fits(var ctx:TEditorContext):boolean;
var first_line,last_line:longint; prefix,suffix:string;
begin
        selection_fits:=true;
        if not ctx.current^.editor.selection then exit;
        selection_edges(ctx,first_line,last_line,prefix,suffix);
        if length(prefix)+length(suffix)>255 then begin
                handle_error(ctx,CLIP_LONG_LINE); selection_fits:=false;
        end;
end;

function replace_text(var ctx:TEditorContext; p:pchar; capacity:word;
                      allow_empty:boolean):boolean;
var first_line,last_line:longint; prefix,suffix:string;
    size,added:word; error:integer; line:EditorStr;
begin
        replace_text:=false;
        error:=clip_length(p,capacity,size);
        if error<>0 then begin handle_error(ctx,error); exit end;
        if (size=0) and not allow_empty then begin replace_text:=true; exit end;
        selection_edges(ctx,first_line,last_line,prefix,suffix);
        error:=clip_check(p,capacity,length(prefix),length(suffix),size);
        if error<>0 then begin handle_error(ctx,error); exit end;
        line:=strs.find_num(ctx.current^.rline,first_line);
        if first_line<last_line then
                ctx.current^.rline:=strs.delete(ctx.current^.rline,first_line+1,last_line);
        line:=strs.paste_parts(line,prefix,suffix,p,size,ctx.current^.editor.x,added);
        with ctx.current^ do begin
                cline:=line; rline:=strs.go_first(line); total:=strs.renum(rline);
                editor.selection:=false; editor.chg:=false; chg:=true;
        end;
        load_ed(ctx); replace_text:=true;
end;

function delete_selected(var ctx:TEditorContext):boolean;
const empty:pchar='';
begin
        delete_selected:=true;
        if ctx.current^.editor.selection then
                delete_selected:=replace_text(ctx,empty,1,true);
end;

function refresh_clipboard(var ctx:TEditorContext):integer;
var p:pchar; size:word; error:integer;
begin
        error:=0;
        if ctx.has_wincb then begin
                if MaxAvail<CB_SIZE then error:=8 else begin
                        GetMem(p,CB_SIZE); FillChar(p[0],CB_SIZE,$FF);
                        if not WCB_Paste(p[0],CB_SIZE) then error:=CLIP_UNAVAILABLE
                        else begin
                                error:=clip_length(p,CB_SIZE,size);
                                if error=0 then error:=clip_bytes(p,size);
                                if error=0 then Move(p[0],ctx.clipboard[0],size+1);
                        end;
                        FreeMem(p,CB_SIZE);
                end;
        end;
        refresh_clipboard:=error;
end;

procedure go_win_list(var ctx:TEditorContext);
var r : PFileContext;
        i, sitem, cctx  : integer;
        memlen          : longint;
        p               : pchar;
        e               : TEvent;
begin
        if ctx.all=nil then exit;
        i := 0;
        memlen := 0; sitem := 0; cctx := 0;
        r := ctx.all;
        while r <> nil do begin
                if r = ctx.current then begin sitem := i; cctx := i; end;
                inc(memlen, length(r^.sfname) + 3);
                inc(i);
                r := r^.next;
        end;
        if (memlen>32767) or (MaxAvail<memlen) then begin
                scr.notice('Not enough memory for this window. Press Enter or Esc.'); exit;
        end;
        getmem(p, memlen);
        scr.cursor_off;
        i := 0;
        r := ctx.all;
        while r <> nil do begin
                if i <> 0 then begin p[i] := #$0A; inc(i); end;
                p[i] := ' '; inc(i);
                if r^.chg or r^.editor.chg then p[i] := #$03 else p[i] := ' ';
                inc(i);
                move(r^.sfname[1], p[i], length(r^.sfname));
                inc(i, length(r^.sfname));
                r := r^.next;
        end;
        p[i] := #0;

        while true do begin
                scrui.vmenu(e, 1, 2, 32, scr.getheight - 3,
                        ctx.config.color.menu,
                        ctx.config.color.menu_sel,
                        'Opened files',
                        p, sitem);
                if e.scancode = SCAN_ESC then break;
                if (e.scancode = SCAN_ENTER) or (e.scancode = SCAN_SPACE) then begin
                        if (sitem <> cctx) then begin
                                i := 0;
                                r := ctx.all;
                                while r <> nil do begin
                                        if i = sitem then begin ctx.current := r; break; end;
                                        inc(i);
                                        r := r^.next;
                                end;
                        end;
                        break;
                end;
        end;

        freemem(p, memlen);
end;

function mk_short_name(fname : string) : string;
begin
        mk_short_name := basename(fname);
end;

procedure reset_file(p : PFileContext);
begin
        p^.recovery:=nil;
        undo_init(p^.history,UNDO_DEFAULT_LIMIT,UNDO_DEFAULT_RESERVE);
        with p^ do begin
                sfname := mk_short_name(fname);
                if fname='' then sfname:='Untitled';
                if config^.hl_enable then st := find_SourceType_by_ext(get_filename_ext(sfname)) 
                else st := SRC_DISABLE;
                chg := false;
                cline := rline;
                scrline := rline;
                editor.chg := false;
                editor.x := 1;
                editor.desired_cell := -1;
                editor.selection := false;
                scrline := rline;
                scrx := 0;
                scry := 0;
                total := strs.renum(rline);
                next := nil;
        end;
end;

function new_file(var ctx : TEditorContext; fname : string):integer;
var p : PFileContext;
begin
        new_file:=8;
        if (MaxAvail<sizeof(TFileContext)) or
           (MemAvail-sizeof(TFileContext)<UNDO_DEFAULT_RESERVE) then exit;
        getmem(p, sizeof(TFileContext));
        p^.fname := fname;
        p^.rline := strs.new_checked(UNDO_DEFAULT_RESERVE);
        if strs.is_nil(p^.rline) then begin FreeMem(p,sizeof(TFileContext)); exit end;
        p^.format.newline := #13#10;
        p^.config := @ctx.config;
        reset_file(p);
        p^.next := ctx.all;
        ctx.all := p;
        ctx.current := p;
        load_ed(ctx);
        new_file:=0;
end;

function load_file(var ctx : TEditorContext; fname : string; var errCode : integer; percent_proc : pointer) : integer;
var p : PFileContext;
        r : integer;
begin
        r := SCRU_FULL; load_file:=r; errCode:=8;
        if (MaxAvail<sizeof(TFileContext)) or
           (MemAvail-sizeof(TFileContext)<UNDO_DEFAULT_RESERVE) then exit;
        getmem(p, sizeof(TFileContext));
        p^.fname := fname;
        p^.rline := strs.from_file(ctx.file_reader,fname,false,0,0,p^.format,errCode,percent_proc);
        if errCode = 2 then begin
                freemem(p, sizeof(TFileContext));
                errCode:=new_file(ctx, fname);
                load_file := SCRU_FULL;
                exit;
        end;
        if errCode <> 0 then begin
                freemem(p, sizeof(TFileContext));
                { A failed load must not install a truncated document. }
                if ctx.current = nil then new_file(ctx, DEFAULT_FILE_NAME);
                load_file := SCRU_FULL;
                exit;
        end;
        p^.config := @ctx.config;
        reset_file(p);
        p^.next := ctx.all;
        ctx.all := p;
        ctx.current := p;
        load_ed(ctx);
        load_file := r;
end;

function get_err_msg(errCode:integer) : string;
var     errMsg : string;
begin
        case errCode of
        SAVE_PENDING: errMsg := 'Resolve the previous save before saving again';
        READ_PENDING: errMsg := 'A previous read handle is still open';
        READ_CHANGED: errMsg := 'File changed during read';
        RECORD_INVALID: errMsg := 'Invalid recovery record';
        RECOVERY_MISMATCH: errMsg := 'Recovery contents do not match the record';
        1016: errMsg := 'Search and replacement must be single-line text';
        1017: errMsg := 'Session entry cannot be represented';
        1018: errMsg := 'Invalid configuration or resume record';
        1005: errMsg := 'Text exceeds clipboard capacity';
        1006: errMsg := 'Resulting line exceeds 255 bytes';
        1007: errMsg := 'Unsupported control byte in inserted text';
        1008: errMsg := 'Clipboard file changed during read';
        1009: errMsg := 'Host clipboard is unavailable';
        1004: errMsg := 'Cannot record edit; document unchanged';
        1001: errMsg := 'Line exceeds 255 bytes; file was not opened';
        1002: errMsg := 'Mixed line endings; file was not opened';
        1003: errMsg := 'Unsupported control byte; file was not opened';
        1: errMsg := 'Invalid function number';
        2: errMsg := 'File not found';
        3: errMsg := 'Path not found';
        4: errMsg := 'Too many open files';
        5: errMsg := 'File access denied';
        8: errMsg := 'Not enough memory';
        6: errMsg := 'Invalid file handle';
        12: errMsg := 'Invalid file access code';
        15: errMsg := 'Invalid drive number';
        16: errMsg := 'Cannot remove current directory';
        17: errMsg := 'Cannot rename across drives';
        18: errMsg := 'No more files';
        100: errMsg := 'Disk read error';
        101: errMsg := 'Disk write error';
        102: errMsg := 'File not assigned';
        103: errMsg := 'File not open';
        104: errMsg := 'File not open for input';
        105: errMsg := 'File not open for output';
        106: errMsg := 'Invalid numeric format';
        150: errMsg := 'Disk is write-protected';
        151: errMsg := 'Bad drive request struct length';
        152: errMsg := 'Drive not ready';
        154: errMsg := 'CRC error in data';
        156: errMsg := 'Disk seek error';
        157: errMsg := 'Unknown media type';
        158: errMsg := 'Sector Not Found';
        159: errMsg := 'Printer out of paper';
        160: errMsg := 'Device write fault';
        161: errMsg := 'Device read fault';
        162: errMsg := 'Hardware failure';
        200: errMsg := 'Division by zero';
        201: errMsg := 'Range check error';
        202: errMsg := 'Stack overflow error';
        203: errMsg := 'Heap overflow error';
        204: errMsg := 'Invalid pointer operation';
        205: errMsg := 'Floating point overflow';
        206: errMsg := 'Floating point underflow';
        207: errMsg := 'Invalid floating point operation';
        208: errMsg := 'Overlay manager not installed';
        209: errMsg := 'Overlay file read error';
        210: errMsg := 'Object not initialized';
        211: errMsg := 'Call to abstract method';
        212: errMsg := 'Stream registration error';
        213: errMsg := 'Collection index out of range';
        214: errMsg := 'Collection overflow error';
        215: errMsg := 'Arithmetic overflow error';
        216: errMsg := 'General Protection fault';
        else errMsg := 'Unknown error code';
        end;
        get_err_msg := concat('#', itoa(errCode), ': ', errMsg)
end;

procedure handle_error(var ctx : TEditorContext; errCode:integer);
var errMsg : string;
begin
        errMsg := get_err_msg(errCode);
        if not scr.try_push then begin scr.notice(errMsg); exit end;
        scrui.msg_box(ctx.config.color.top_hl, 'Error', errMsg, '[ OK ]');
        scr.show;
        kbd_reset;
        while true do begin
                case hi(kbd_getkey) of
                SCAN_ESC: break;
                SCAN_ENTER: break;
                end;
        end;
        scr.pop;
end;

procedure free_fast_jmp_list(var root:pfast_jmp_list);
var p:pfast_jmp_list;
begin
        while root<>nil do begin
                p:=root; root:=p^.next; FreeMem(p,sizeof(fast_jmp_list));
        end;
end;

function create_fast_jmp_list(var ctx:TEditorContext) : pfast_jmp_list;
var     r, l, c  : pfast_jmp_list;
        rline    : EditorStr;
        line     : string;
        uline    : string;
        lnum     : dword;
        i        : integer;
        t        : string;
        name     : string;
        need_add : boolean;
begin
        r := nil; l := nil;
        rline := ctx.current^.rline;
        if ctx.current^.st = SRC_PAS then begin
                while true do begin
                        need_add := false;
                        lnum := strs.get_num(rline);
                        strs.get(rline, line);
                        uline := trim(line);
                        upstr(uline);
                        if starts_with(uline, 'PROCEDURE ') then begin
                                line := copy(line, 11, length(line) - 10);
                                i := 1;
                                while i < ord(line[0]) do begin
                                        if not(line[i] in ['a'..'z','A'..'Z','0'..'9','_'])
                                                then break;
                                        inc(i);
                                end;
                                name := copy(line, 1, i - 1);
                                system.delete(line, 1, i - 1);
                                while length(name) < 16 do name := name + ' ';
                                line := 'P: ' + name + ' ' + line;
                                need_add := true
                        end else if starts_with(uline, 'FUNCTION ') then begin
                                line := copy(line, 10, length(line) - 9);
                                i := 1;
                                while i < ord(line[0]) do begin
                                        if not(line[i] in ['a'..'z','A'..'Z','0'..'9','_'])
                                                then break;
                                        inc(i);
                                end;
                                name := copy(line, 1, i - 1);
                                system.delete(line, 1, i - 1);
                                while length(name) < 16 do name := name + ' ';
                                line := 'F: ' + name + ' ' + line;
                                need_add := true
                        end else if starts_with(uline, 'INTERFACE') then begin
                                upstr(line);
                                line := '    ' + line;
                                need_add := true
                        end else if starts_with(uline, 'IMPLEMENTATION') then begin
                                upstr(line);
                                line := '    ' + line;
                                need_add := true;
                        end;
                        if need_add then begin
                                if MaxAvail<sizeof(fast_jmp_list) then begin
                                        free_fast_jmp_list(r);
                                        create_fast_jmp_list:=nil;
                                        scr.notice('Not enough memory for this window. Press Enter or Esc.');
                                        exit;
                                end;
                                getmem(c, sizeof(fast_jmp_list));
                                t := ltoa(lnum);
                                while length(t) < 6 do t := ' ' + t;
                                c^.line := lnum;
{                                c^.text := t + ':' + line;}
                                c^.text := line;
                                c^.next := nil;
                                if l <> nil then l^.next := c;
                                if r = nil then r := c;
                                l := c;
                        end;
                        if strs.is_last(rline) then break;
                        rline := strs.go_next(rline);
                end;
        end;
        create_fast_jmp_list := r;
end;

function fast_jmp(var ctx:TEditorContext; fjl : pfast_jmp_list) : integer;
var     r         : integer;
        f         : pfast_jmp_list;
        size      : longint;
        ofs       : word;
        p         : pchar;
        i, sitem  : integer;
        rline     : EditorStr;
        e         : TEvent;
        clnum     : dword;
begin
        r := SCRU_NONE; fast_jmp:=r;
        if fjl=nil then exit;
        f := fjl; size := 0;
        clnum := strs.get_num(ctx.current^.cline);
        while f <> nil do begin
                inc(size, length(f^.text) + 1);
                f := f^.next;
        end;
        if (size>32767) or (MaxAvail<size) then begin
                free_fast_jmp_list(fjl);
                scr.notice('Not enough memory for this window. Press Enter or Esc.'); exit;
        end;
        getmem(p, size);
        scr.cursor_off;
        f := fjl; ofs := 0; sitem := 0; i := 0;
        while f <> nil do begin
                if f^.line <= clnum  then sitem := i;
                move(f^.text[1], p[ofs], length(f^.text));
                inc(ofs, length(f^.text));
                if f^.next <> nil then p[ofs] := #$0a else p[ofs] := #0;
                inc(ofs);
                inc(i);
                f := f^.next;
        end;
        while true do begin
                scrui.vmenu(e, 1, 2, scr.getwidth - 2, scr.getheight - 3,
                        ctx.config.color.menu,
                        ctx.config.color.menu_sel,
                        'Source tree',
                        p, sitem);
                if e.scancode = SCAN_ESC then break;
                if (e.scancode = SCAN_ENTER) or (e.scancode = SCAN_SPACE) then begin
                        i := 0;
                        f := fjl;
                        while f <> nil do begin
                                if i = sitem then begin
                                        rline := strs.find_num(ctx.current^.rline, f^.line);
                                        if rline <> nil then begin
                                                commit(ctx);
                                                ctx.current^.cline := rline;
                                                load_ed(ctx);
                                                ctx.current^.editor.x := 1;
                                        end;
                                        break;
                                end;
                                inc(i);
                                f := f^.next;
                        end;
                        break;
                end;
        end;
        r := SCRU_FULL;
        freemem(p, size);
        scr.cursor_on;
        free_fast_jmp_list(fjl);
        fast_jmp := r;
end;

{$F-}

function get_time_diff(start_time : dword) : string;
var     ctime : longint;
        h, m, s: integer;
        t, r : string;
begin
        ctime := get_ticks;
        dec(ctime, start_time);
        ctime := ctime div 18;
        h := 0;
        m := 0;
        s := ctime mod 60;
        ctime := ctime div 60;
        m := ctime mod 60;
        ctime := ctime div 60;
        h := ctime;
        r := '';
        t := itoa(h);
        if t[0] = #1 then t := '0' + t;
        r := t + ':';
        t := itoa(m);
        if t[0] = #1 then t := '0' + t;
        r := r + t + ':';
        t := itoa(s);
        if t[0] = #1 then t := '0' + t;
        r := r + t;
        get_time_diff := r;
end;

{$F+}
procedure load_file_progress(value, total, start_time : dword);
var     w, scry    : integer;
        msg        : string;
        percent    : longint;
begin
        if (value > 1000000) and (total > 1000000) then begin
                value := value div 1000;
                total := total div 1000;
        end;
        percent := 0;
        if total <> 0 then percent := (value * 100) div total;
        if percent < 0 then percent := 0;
        if percent > 100 then percent := 100;
        scry := (scr.getheight div 2) - 1;
        box(1, scry, scr.getwidth - 2, 3, $70);
        scr.hprint(2, scry + 1, $70, #$B0, scr.getwidth - 4);
        if percent = 0 then w := 0 else w := ((scr.getwidth - 4) * percent) div 100;
        scr.hprint(2, scry + 1, $70, #$DB,  w);
        msg := '[ Load ' + lpad(itoa(percent), 3) + '%  '
                + get_time_diff(start_time) + ' ]';
        scr.print(3, scry, $70, msg);
        scr.show;
end;

procedure save_file_progress(value, total, start_time : dword);
var     w, scry    : integer;
        msg        : string;
        percent    : longint;
begin
        if (value > 1000000) and (total > 1000000) then begin
                value := value div 1000;
                total := total div 1000;
        end;
        percent := 0;
        if total <> 0 then percent := (value * 100) div total;
        if percent < 0 then percent := 0;
        if percent > 100 then percent := 100;
        scry := (scr.getheight div 2) - 1;
        box(1, scry, scr.getwidth - 2, 3, $70);
        scr.hprint(2, scry + 1, $70, #$B0, scr.getwidth - 4);
        if percent = 0 then w := 0 else w := ((scr.getwidth - 4) * percent) div 100;
        scr.hprint(2, scry + 1, $70, #$DB,  w);
        msg := '[ Save ' + lpad(itoa(percent), 3) + '%  '
                + get_time_diff(start_time) + ' ]';
        scr.print(3, scry, $70, msg);
        scr.show;
end;

end.
