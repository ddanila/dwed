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
unit dwedtbl;

interface

uses dwedtype, event;

function is_in_table(var ctx:TEditorContext; event:PEvent) : boolean;
function tbl_next_column(var ctx:TEditorContext; event:PEvent) : integer;
function tbl_prev_column(var ctx:TEditorContext; event:PEvent) : integer;
function tbl_append_row(var ctx:TEditorContext; event:PEvent) : integer;

implementation

uses kminput, scr, scrui, strs, strutil, dwedhl, dwedlnch, dwedutil;

const
tbl_column_chars  : string[2]  = '³º';
tbl_transl_chars1 : string[26] = 'ÃÅÂ´ÆÑµÚ¿ÕØ¸³ÌÎË¹ÇÒ×¶Ö·É»º';
tbl_transl_chars2 : string[26] = '³³³³³³³³³³³³³ººººººººººººº';

{ Scan only live shortstring bytes. A field needs room between two borders. }
function table_bounds(const line:string; var first,last:integer):boolean;
begin
        first:=1; last:=length(line);
        while first<=last do begin
                if line[first]<>' ' then break;
                inc(first);
        end;
        while last>first do begin
                if line[last]<>' ' then break;
                dec(last);
        end;
        table_bounds:=false;
        if first>=last then exit;
        table_bounds:=(pos(line[first],tbl_column_chars)>0) and
                      (pos(line[last],tbl_column_chars)>0);
end;

function is_in_table_str(var line:string):boolean;
var first,last:integer;
begin
        is_in_table_str:=table_bounds(line,first,last);
end;

function is_in_table(var ctx:TEditorContext; event:PEvent):boolean;
begin
        is_in_table:=is_in_table_str(ctx.current^.editor.line);
end;

{ Return a field start, or zero. Adjacent borders are not editable fields. }
function table_field(const line:string; caret:integer; backwards:boolean):integer;
var first,last,left,right,target:integer;
begin
        table_field:=0;
        if not table_bounds(line,first,last) then exit;
        left:=first; target:=0;
        for right:=first+1 to last do begin
                if pos(line[right],tbl_column_chars)>0 then begin
                        if right>left+1 then begin
                                if backwards then begin
                                        if right<=caret then target:=left+1;
                                end else if (left>=caret) and (target=0) then
                                        target:=left+1;
                        end;
                        left:=right;
                end;
        end;
        table_field:=target;
end;

function table_move(var ctx:TEditorContext; backwards:boolean):integer;
var target:integer; adjacent:EditorStr; line:string;
begin
        table_move:=SCRU_NONE;
        ctx.current^.editor.selection:=false;
        target:=table_field(ctx.current^.editor.line,
                            ctx.current^.editor.x,backwards);
        if target<>0 then begin
                ctx.current^.editor.x:=target;
                table_move:=SCRU_CLINE;
                exit;
        end;
        if backwards then adjacent:=strs.go_prev(ctx.current^.cline)
        else adjacent:=strs.go_next(ctx.current^.cline);
        if adjacent=nil then exit;
        strs.get(adjacent,line);
        if backwards then target:=table_field(line,length(line)+1,true)
        else target:=table_field(line,1,false);
        if target=0 then exit;
        commit(ctx);
        ctx.current^.cline:=adjacent;
        load_ed(ctx);
        ctx.current^.editor.x:=target;
        table_move:=SCRU_FULL;
end;

function tbl_next_column(var ctx:TEditorContext; event:PEvent):integer;
begin
        tbl_next_column:=table_move(ctx,false);
end;

function tbl_prev_column(var ctx:TEditorContext; event:PEvent):integer;
begin
        tbl_prev_column:=table_move(ctx,true);
end;

function tbl_append_row(var ctx:TEditorContext; event:PEvent) : integer;
var     r, x  : integer;
        oline : string;
        nline : string;
        i     : integer;
        c     : char;
        nl    : EditorStr;
        tail  : string;
begin
        r := SCRU_FULL;
        ctx.current^.editor.selection := false;
        oline := ctx.current^.editor.line;
        nline := oline;
        while (nline[0] <> #0) and (nline[ord(nline[0])] <= ' ') do Dec(nline[0]);
        oline := nline;
        for i:= 1 to ord(nline[0]) do begin
                x := pos(nline[i], tbl_transl_chars1);
                if x = 0 then c := ' ' else c:= tbl_transl_chars2[x];
                nline[i] := c;
        end;
        i := ctx.current^.editor.x;
        tail := '';
        while i < ord(nline[0]) do begin
                x := pos(nline[i], tbl_column_chars);
                if x > 0 then break;
                tail := tail + oline[i];
                oline[i] := ' ';
                inc(i);
        end;
        ctx.current^.editor.line := oline;
        ctx.current^.editor.chg := true;
        commit(ctx);

        x := ctx.current^.editor.x;
        while (nline[x] = ' ') and (x <> 0) do dec(x);
        inc(x);
        system.delete(nline, x, length(tail));
        insert(tail, nline, x);
        nl := strs.create(strs.go_next(ctx.current^.cline), ctx.current^.cline, nline);
        ctx.current^.total := strs.renum(ctx.current^.rline);
        ctx.current^.cline := strs.go_next(ctx.current^.cline);
        load_ed(ctx);
        ctx.current^.editor.line := nline;
        ctx.current^.editor.chg := true;
{        if ctx.current^.scry <> ctx.current^.config^.height - 2 then inc(ctx.current^.scry);}
        ctx.current^.editor.x := x;

        tbl_append_row := r;
end;

end.
