{ SPDX-License-Identifier: MIT }
unit doslines;
interface
uses dosread;
const METADATA_INVALID=1018;
type PInputLine=^TInputLine;
     TInputLine=record next:PInputLine; value:string end;
function read_lines(var reader:TReadFile; name:string; var lines:PInputLine;
                    reserve:longint):integer;
procedure free_lines(var lines:PInputLine);
implementation
procedure free_lines(var lines:PInputLine);
var item:PInputLine;
begin
        while lines<>nil do begin
                item:=lines; lines:=item^.next; FreeMem(item,sizeof(TInputLine));
        end;
end;
function read_lines(var reader:TReadFile; name:string; var lines:PInputLine;
                    reserve:longint):integer;
var buffer:array[0..511] of char; count,i:word; error:integer;
    total:longword; value:string; last:PInputLine; after_cr:boolean;
        procedure append;
        var item:PInputLine;
        begin
                if error<>0 then exit;
                if (MaxAvail<sizeof(TInputLine)) or
                   (MemAvail-sizeof(TInputLine)<reserve) then begin error:=8; exit end;
                GetMem(item,sizeof(TInputLine)); item^.next:=nil; item^.value:=value;
                if last=nil then lines:=item else last^.next:=item;
                last:=item; value:='';
        end;
begin
        lines:=nil; last:=nil; value:=''; total:=0; after_cr:=false;
        open_read(reader,name,error);
        if error<>0 then begin read_lines:=error; exit end;
        repeat
                read_bytes(reader,buffer,sizeof(buffer),count,error);
                if error<>0 then break;
                if (total>reader.size) or (longword(count)>reader.size-total) then begin
                        error:=READ_CHANGED; break;
                end;
                inc(total,count);
                if count=0 then begin
                        if total<>reader.size then error:=READ_CHANGED;
                        break;
                end;
                for i:=0 to count-1 do begin
                        if buffer[i]=#10 then begin
                                if not after_cr then append;
                                after_cr:=false;
                        end else if buffer[i]=#13 then begin
                                append; after_cr:=true;
                        end else begin
                                after_cr:=false;
                                if (buffer[i]<#32) and (buffer[i]<>#9) then error:=METADATA_INVALID
                                else if length(value)=255 then error:=METADATA_INVALID
                                else value:=value+buffer[i];
                        end;
                        if error<>0 then break;
                end;
        until error<>0;
        if (error=0) and (value<>'') then append;
        close_read(reader);
        if (error=0) and reader.opened then error:=reader.close_error;
        if error<>0 then free_lines(lines);
        read_lines:=error;
end;
end.
