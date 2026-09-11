{ SPDX-License-Identifier: MIT }
{$A-,F-}
unit cliptext;
interface
const CLIP_TOO_LARGE=1005;
      CLIP_LONG_LINE=1006;
      CLIP_BAD_TEXT=1007;
      CLIP_READ_CHANGED=1008;
      CLIP_UNAVAILABLE=1009;
function clip_length(p:pchar; capacity:word; var size:word):integer;
function clip_bytes(p:pchar; size:word):integer;
function clip_check(p:pchar; capacity:word; prefix,suffix:integer;
                    var size:word):integer;
implementation
function clip_length(p:pchar; capacity:word; var size:word):integer;
begin
        size:=0; clip_length:=0;
        if p=nil then exit;
        while size<capacity do begin
                if p[size]=#0 then exit;
                inc(size);
        end;
        clip_length:=CLIP_TOO_LARGE;
end;
function clip_bytes(p:pchar; size:word):integer;
var i:word;
begin
        clip_bytes:=0; i:=0;
        while i<size do begin
                if (p[i]<#32) and not (p[i] in [#9,#10,#13]) then begin
                        clip_bytes:=CLIP_BAD_TEXT; exit;
                end;
                inc(i);
        end;
end;
function clip_check(p:pchar; capacity:word; prefix,suffix:integer;
                    var size:word):integer;
var i:word; length_so_far:longint; error:integer; c:char;
begin
        error:=clip_length(p,capacity,size);
        if error=0 then error:=clip_bytes(p,size);
        clip_check:=error;
        if error<>0 then exit;
        length_so_far:=prefix; i:=0;
        while i<size do begin
                c:=p[i]; inc(i);
                if c in [#10,#13] then begin
                        if length_so_far>255 then begin clip_check:=CLIP_LONG_LINE; exit end;
                        length_so_far:=0;
                        if (c=#13) and (i<size) then if p[i]=#10 then inc(i);
                end else inc(length_so_far);
        end;
        if (prefix<0) or (suffix<0) or (length_so_far+suffix>255) then
                clip_check:=CLIP_LONG_LINE;
end;
end.
