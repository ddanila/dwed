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

uses kminput, scr, scrui, strs, strutil, dwedhl, dwedlnch, dwedutil, textcell;

const
tbl_column_chars  : string[2]  = '³º';
tbl_transl_chars1 : string[26] = 'ÃÅÂ´ÆÑµÚ¿ÕØ¸³ÌÎË¹ÇÒ×¶Ö·É»º';
tbl_transl_chars2 : string[26] = '³³³³³³³³³³³³³ººººººººººººº';

{ Scan only live shortstring bytes. A field needs room between two borders. }
function table_bounds(const line:string; var first,last:integer):boolean;
begin
        first:=1; last:=length(line);
        while first<=last do begin
                if not (line[first] in [' ',#9]) then break;
                inc(first);
        end;
        while last>first do begin
                if not (line[last] in [' ',#9]) then break;
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

{ Preflight the complete row before changing the document. Tabs remain bytes;
  padding restores the original right border's screen column after moving text. }
function prepare_row(const original:string; caret,size:integer;
                     var oldrow,newrow:string; var destination:integer):boolean;
var first,last,left,right,i,k,column,limit,step:integer;
    skeleton,tail,prefix:string; has_tab:boolean;
begin
        prepare_row:=false;
        oldrow:=original; skeleton:=original;
        if not table_bounds(original,first,last) then exit;
        for i:=first to last do begin
                k:=pos(original[i],tbl_transl_chars1);
                if k>0 then skeleton[i]:=tbl_transl_chars2[k]
                else if original[i]<>#9 then skeleton[i]:=' ';
        end;
        newrow:=skeleton;
        destination:=table_field(skeleton,1,false);
        if destination=0 then destination:=first+1;
        left:=first;
        for right:=first+1 to last do begin
                if pos(skeleton[right],tbl_column_chars)>0 then begin
                        if (caret>left) and (caret<=right) and
                           (right>left+1) then begin
                                destination:=left+1;
                                tail:=copy(original,caret,right-caret);
                                if tail='' then begin prepare_row:=true; exit end;
                                has_tab:=false;
                                for i:=left+1 to right-1 do
                                        if original[i]=#9 then has_tab:=true;
                                for i:=caret to right-1 do
                                        if oldrow[i]<>#9 then oldrow[i]:=' ';
                                prefix:=copy(skeleton,1,left)+tail;
                                size:=tab_width(size);
                                column:=cell_of(prefix,length(prefix)+1,size);
                                limit:=cell_of(original,right,size);
                                if column>limit then exit;
                                while column<limit do begin
                                        if length(prefix)=255 then exit;
                                        step:=size-column mod size;
                                        if has_tab and (step>1) and
                                           (column+step<=limit) then begin
                                                prefix:=prefix+#9;
                                                inc(column,step);
                                        end else begin
                                                prefix:=prefix+' '; inc(column);
                                        end;
                                end;
                                if length(prefix)+length(skeleton)-right+1>255 then exit;
                                newrow:=prefix+copy(skeleton,right,255);
                                prepare_row:=true;
                                exit;
                        end;
                        left:=right;
                end;
        end;
        prepare_row:=true;
end;

function tbl_append_row(var ctx:TEditorContext; event:PEvent):integer;
var oldrow,newrow:string; destination:integer; inserted:EditorStr;
begin
        tbl_append_row:=SCRU_FULL;
        if not prepare_row(ctx.current^.editor.line,ctx.current^.editor.x,
                           ctx.current^.config^.tab_size,
                           oldrow,newrow,destination) then begin
                handle_error(ctx,1006);
                exit;
        end;
        ctx.current^.editor.selection:=false;
        if oldrow<>ctx.current^.editor.line then begin
                ctx.current^.editor.line:=oldrow;
                ctx.current^.editor.chg:=true;
                commit(ctx);
        end;
        inserted:=strs.create(strs.go_next(ctx.current^.cline),
                              ctx.current^.cline,newrow);
        ctx.current^.total:=strs.renum(ctx.current^.rline);
        ctx.current^.cline:=inserted;
        load_ed(ctx);
        ctx.current^.chg:=true;
        ctx.current^.editor.x:=destination;
end;

end.
