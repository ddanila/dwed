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
{$B-}
unit dwedscru;

interface

uses dwedtype;

procedure update(var ctx : TEditorContext; scru : integer);

implementation

uses scr, kminput, str, strutil, strs, dwedhndl, dwedutil, dwedhl, dwedmenu, textcell;

procedure paint_line(var ctx:TEditorContext; const body:string; row:integer;
                     number:longint; selected:boolean;
                     first_col,last_col:integer; first_row,last_row:longint);
var visible:string; left,width,start_cell,end_cell:integer;
begin
        with ctx.current^ do begin
                left:=scrx; width:=config^.width;
                visible:=cell_slice(body,left,width,config^.tab_size);
                scr.print(0,row,config^.color.text,visible);
                scr.cln(length(visible),row,config^.color.text);
                if selected and (number>=first_row) and (number<=last_row) then begin
                        start_cell:=left; end_cell:=left+width;
                        if number=first_row then
                                start_cell:=cell_of(body,first_col,config^.tab_size);
                        if number=last_row then
                                end_cell:=cell_of(body,last_col,config^.tab_size);
                        if start_cell<left then start_cell:=left;
                        if end_cell>left+width then end_cell:=left+width;
                        if end_cell>start_cell then
                                scr.chcolor(start_cell-left,row,config^.color.text_sel,
                                            end_cell-start_cell);
                end;
                high_light(st,width,config^.color.text_hl,config^.color.text,
                           @scr.screen[(width*row) shl 1]);
        end;
end;

procedure update_full(var ctx:TEditorContext);
var row,first_col,last_col:integer; first_row,last_row:longint;
    line:EditorStr; body:string; selected:boolean;
begin
        selected:=ctx.current^.editor.selection;
        first_col:=0; last_col:=0; first_row:=0; last_row:=0;
        if selected then get_sel_coord(ctx,first_col,first_row,last_col,last_row);
        line:=ctx.current^.scrline;
        for row:=1 to ctx.current^.config^.height-1 do begin
                strs.get(line,body);
                paint_line(ctx,body,row,strs.get_num(line),selected,
                           first_col,last_col,first_row,last_row);
                line:=strs.go_next(line);
        end;
end;

procedure update_cline(var ctx:TEditorContext);
var first_col,last_col:integer; first_row,last_row:longint; selected:boolean;
begin
        selected:=ctx.current^.editor.selection;
        first_col:=0; last_col:=0; first_row:=0; last_row:=0;
        if selected then get_sel_coord(ctx,first_col,first_row,last_col,last_row);
        with ctx.current^ do begin
                paint_line(ctx,editor.line,scry+1,strs.get_num(cline),selected,
                           first_col,last_col,first_row,last_row);
                scr.locate(cell_of(editor.line,editor.x,config^.tab_size)-scrx,scry+1);
        end;
end;

procedure update_scroll(var ctx : TEditorContext; is_up : boolean);
begin
        if is_up then scr.scroll_up(0, 1, ctx.config.width, ctx.config.height - 1, 1)
        else scr.scroll_down(0, 1, ctx.config.width, ctx.config.height - 1, 1);
end;

procedure update_top(var ctx : TEditorContext);
var     ch, i     : char;
        endline   : string;
        fname     : string;
        total     : string;
        char_code : string;
begin
        ch := ' ';
        i := 'O';
        if ctx.current^.chg or ctx.current^.editor.chg then ch := '*';
        if ctx.ins then i := 'I';
        if ctx.current^.editor.x <= length(ctx.current^.editor.line) then begin
                char_code := hexb(ord(ctx.current^.editor.line[ctx.current^.editor.x]));
        end else char_code := '';
        total := ltoa(ctx.current^.total);
        endline := concat(
                char_code, '  ',
                lpad(itoa(cell_of(ctx.current^.editor.line,ctx.current^.editor.x,
                                  ctx.current^.config^.tab_size)+1), 3), ' ',
                lpad(ltoa(strs.get_num(ctx.current^.cline)), length(total)),
                '/', total, ' ', ch, i,' ');   

        fname := ' ' + trim(ctx.current^.sfname);
        endline := lpad(endline, ctx.current^.config^.width - length(fname));

        scr.cln(0, ctx.config.height, ctx.current^.config^.color.top);
        scr.print(0, ctx.config.height, ctx.current^.config^.color.top, fname + endline);
        draw_menu_bar(ctx,-1);
end;

procedure update(var ctx : TEditorContext; scru : integer);
begin
        if scru <> SCRU_NONE then begin
                if scru >= SCRU_FULL then update_full(ctx);

                if scru = SCRU_SD then update_scroll(ctx, false)
                else if scru = SCRU_SU then update_scroll(ctx, true);

                if scru >= SCRU_CLINE then update_cline(ctx);
                if scru >= SCRU_TOP then update_top(ctx);
                if ctx.ins then scr.cursor_on else scr.cursor_big;
                scr.show;
        end;
end;

end.
