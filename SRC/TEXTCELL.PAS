{ SPDX-License-Identifier: MIT }
{$A-,F-}
unit textcell;
interface
{ Document positions are one-based byte boundaries; screen cells are zero-based. }
function tab_width(size:integer):integer;
function cell_of(const s:string; position,size:integer):integer;
function byte_at_cell(const s:string; cell,size:integer):integer;
function cell_slice(const s:string; left,width,size:integer):string;
function indent_bytes(const s:string; size:integer):integer;
implementation
function tab_width(size:integer):integer;
begin
        if (size<1) or (size>32) then size:=8;
        tab_width:=size;
end;
function next_cell(c:char; cell,size:integer):integer;
begin
        if c=#9 then next_cell:=cell+size-cell mod size
        else next_cell:=cell+1;
end;
function indent_bytes(const s:string; size:integer):integer;
var i,column:integer;
begin
        size:=tab_width(size); i:=1; column:=0;
        while (i<=length(s)) and (column<size) do begin
                if not (s[i] in [' ',#9]) then break;
                column:=next_cell(s[i],column,size); inc(i);
        end;
        indent_bytes:=i-1;
end;
function cell_of(const s:string; position,size:integer):integer;
var i,cell:integer;
begin
        size:=tab_width(size); cell:=0;
        if position>length(s)+1 then position:=length(s)+1;
        for i:=1 to position-1 do cell:=next_cell(s[i],cell,size);
        cell_of:=cell;
end;
function byte_at_cell(const s:string; cell,size:integer):integer;
var i,column,following:integer;
begin
        size:=tab_width(size); i:=1; column:=0;
        while i<=length(s) do begin
                following:=next_cell(s[i],column,size);
                if following>cell then break;
                column:=following; inc(i);
        end;
        byte_at_cell:=i;
end;
function cell_slice(const s:string; left,width,size:integer):string;
var i,column,following,j:integer; result:string; c:char;
begin
        size:=tab_width(size); result:=''; column:=0;
        if left<0 then left:=0;
        if width>255 then width:=255;
        for i:=1 to length(s) do begin
                following:=next_cell(s[i],column,size); c:=s[i];
                if c=#9 then c:=' ';
                j:=column; if j<left then j:=left;
                while (j<following) and (j<left+width) do begin
                        result:=result+c; inc(j);
                end;
                column:=following;
                if column>=left+width then break;
        end;
        cell_slice:=result;
end;
end.
