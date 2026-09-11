{ MIT License

Copyright (c) 2022 Viacheslav Komenda

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
{$I-}
unit strs;

{ proxy for string storage calls }

interface

uses safesave, dosread;

type
MemoryType = (MT_DOS, MT_SWAP, MT_SXMS);
TTextFormat = record
        newline : string[2];
end;
EditorStr = pointer;

function supports_undo:boolean;

procedure init(mType : MemoryType);
procedure done;

function new : EditorStr;
function new_checked(reserve:longint):EditorStr;

function from_file(var f:TReadFile; fname:string; checked:boolean; expected_size,expected_crc:longword; var format:TTextFormat; var errCode:integer; scrupdate:pointer):EditorStr;
procedure to_file(var f:TSaveFile; fname : string; r : EditorStr; format : TTextFormat; var errCode : integer; scrupdate : pointer);

function create(next, prev : EditorStr; var body : string) : EditorStr;
procedure free(r : EditorStr);

function put(r : EditorStr; var body : string) : EditorStr;
procedure get(r : EditorStr; var dest : string);
function delete(r : EditorStr; num_from, num_to : longint) : EditorStr;
function merge(r : EditorStr; var merged : boolean) : EditorStr;
function is_first(r : EditorStr) : boolean;
function is_last(r : EditorStr) : boolean;

function go_first(r : EditorStr) : EditorStr;
function go_last(r : EditorStr) : EditorStr;

function go_prev(r : EditorStr) : EditorStr;
function go_next(r : EditorStr) : EditorStr;

function renum(r : EditorStr) : longint;
function get_num(r : EditorStr) : longint;
function find_num(r : EditorStr; num : longint) : EditorStr;

{ Caller must preflight with clip_check before any selection mutation. }
function paste_parts(r:EditorStr; prefix,suffix:string; p:pchar; size:word;
                     var column:integer; var added:word):EditorStr;

function append(r : EditorStr; var pos : integer; p : pchar; var lnum:word) : EditorStr;
function split(r : EditorStr; pos : integer) : EditorStr;

function is_nil(r : EditorStr) : boolean;

implementation

uses system2, scr, strsdos, strssxms, strsswap, dwedtype, str, strutil, dwedutil, saveinfo, unredo;

const
memType : MemoryType = MT_DOS;

function supports_undo:boolean;
begin supports_undo:=memType=MT_DOS end;

procedure init(mType : MemoryType);
begin
        memType := mType;
        if mType = MT_SXMS then strssxms.init
        else if mType = MT_SWAP then strsswap.init
        else strsdos.init;
end;

procedure done;
begin
        if memType = MT_SXMS then strssxms.done
        else if memType = MT_SWAP then strsswap.done
        else strsdos.done;
end;

function put(r : EditorStr; var body : string) : EditorStr;
begin
        if memType = MT_SXMS then put := EditorStr(strssxms.put(dword(r), body))
        else if memType = MT_SWAP then put := EditorStr(strsswap.put(dword(r), body))
        else put := EditorStr(strsdos.put(pointer(r), body));
end;

function create(next, prev : EditorStr; var body : string) : EditorStr;
begin
        if memType = MT_SXMS then create := EditorStr(strssxms.create(dword(next), dword(prev), body))
        else if memType = MT_SWAP then create := EditorStr(strsswap.create(dword(next), dword(prev), body))
        else create := EditorStr(strsdos.create(pointer(next), pointer(prev), body));
end;

function from_file(var f:TReadFile; fname:string; checked:boolean; expected_size,expected_crc:longword; var format:TTextFormat; var errCode:integer; scrupdate:pointer):EditorStr;
var     buffer : array[0..4095] of byte;
        count, i : word;
        actual_size,actual_crc:longword;
        root, last : EditorStr;
        body : string;
        pending_cr : boolean;
        c : char;
        current,total,start_date : longint;
        scrup : TPercentUpdateProc;

        procedure emit(separator : string);
        var added:EditorStr;
        begin
                if separator <> '' then begin
                        if format.newline = '' then format.newline := separator
                        else if format.newline <> separator then begin
                                errCode := 1002;
                                exit;
                        end;
                end;
                if memType=MT_DOS then begin
                        added:=EditorStr(strsdos.create_checked(nil,last,body,UNDO_DEFAULT_RESERVE));
                        if added=nil then begin errCode:=8; exit end;
                end else added:=strs.create(nil,last,body);
                last:=added;
                if root = nil then root := last;
                body := '';
        end;

begin
        spinner_start;
        errCode := 0; root := nil; last := nil;
        body := ''; pending_cr := false; format.newline := '';
        actual_size:=0; actual_crc:=$FFFFFFFF;
        open_read(f,fname,errCode);
        if errCode = 0 then begin
                total:=f.size;
                current := 0; start_date := get_ticks;
                scrup := TPercentUpdateProc(scrupdate);
                repeat
                        count := 0;
                        if errCode = 0 then begin
                                read_bytes(f,buffer,sizeof(buffer),count,errCode);
                                if errCode=0 then begin
                                        inc(actual_size,count);
                                        if actual_size>f.size then errCode:=READ_CHANGED;
                                        if checked then actual_crc:=crc_update(actual_crc,buffer,count);
                                end;
                        end;
                        i := 0;
                        while (i < count) and (errCode = 0) do begin
                                c := chr(buffer[i]); inc(i);
                                if pending_cr then begin
                                        pending_cr := false;
                                        if c = #10 then begin
                                                emit(#13#10);
                                                c := #0;
                                        end else emit(#13);
                                end;
                                if errCode = 0 then begin
                                        if c = #13 then pending_cr := true
                                        else if c = #10 then emit(#10)
                                        else if (c <> #0) or (buffer[i-1] = 0) then begin
                                                if (ord(c) < 32) and (c <> #9) then errCode := 1003
                                                else if length(body) = 255 then errCode := 1001
                                                else body := body + c;
                                        end;
                                end;
                        end;
                        inc(current, count);
                        if (scrupdate <> nil) and (errCode = 0) then
                                scrup(current,total,start_date);
                until (count = 0) or (errCode <> 0);
                if (errCode=0) and (actual_size<>f.size) then errCode:=READ_CHANGED;
                if (errCode=0) and checked then
                        if (actual_size<>expected_size) or
                           ((actual_crc xor $FFFFFFFF)<>expected_crc) then errCode:=RECOVERY_MISMATCH;
                if (errCode = 0) and pending_cr then emit(#13);
                if errCode = 0 then emit('');
                close_read(f);
                if errCode=0 then errCode:=f.close_error;
        end;
        if format.newline = '' then format.newline := #13#10;
        if errCode <> 0 then begin
                strs.free(root);
                root := nil;
        end;
        from_file := root;
        spinner_stop;
end;

procedure to_file(var f:TSaveFile; fname : string; r : EditorStr; format : TTextFormat; var errCode : integer; scrupdate : pointer);
var     s : string;
        current,total,start_date : longint;
        scrup : TPercentUpdateProc;
begin
        if save_pending_files(f) then begin errCode:=SAVE_PENDING; exit end;
        spinner_start;
        start_save(f,fname,errCode);
        if errCode=0 then begin
                total:=renum(r); current:=0; start_date:=get_ticks;
                scrup:=TPercentUpdateProc(scrupdate);
                while not is_nil(r) and (errCode=0) do begin
                        get(r,s);
                        write_save(f,s[1],length(s),errCode);
                        if not is_last(r) then
                                write_save(f,format.newline[1],length(format.newline),errCode);
                        r:=go_next(r); inc(current);
                        if (scrupdate<>nil) and (current mod 64=0) then
                                scrup(current,total,start_date);
                end;
                finish_save(f,errCode);
        end;
        spinner_stop;
end;

function new_checked(reserve:longint):EditorStr;
begin
        if memType=MT_DOS then new_checked:=EditorStr(strsdos.create_checked(nil,nil,'',reserve))
        else new_checked:=strs.new;
end;

function new : EditorStr;
begin
        if memType = MT_SXMS then new := EditorStr(strssxms.new)
        else if memType = MT_SWAP then new := EditorStr(strsswap.new)
        else new := EditorStr(strsdos.new);
end;

procedure get(r : EditorStr; var dest : string);
begin
        if memType = MT_SXMS then strssxms.get(dword(r), dest)
        else if memType = MT_SWAP then strsswap.get(dword(r), dest)
        else strsdos.get(pointer(r), dest);
end;

function is_first(r : EditorStr) : boolean;
begin
        if memType = MT_SXMS then is_first := strssxms.is_first(dword(r))
        else if memType = MT_SWAP then is_first := strsswap.is_first(dword(r))
        else is_first := strsdos.is_first(pointer(r));
end;

function is_last(r : EditorStr) : boolean;
begin
        if memType = MT_SXMS then is_last := strssxms.is_last(dword(r))
        else if memType = MT_SWAP then is_last := strsswap.is_last(dword(r))
        else is_last := strsdos.is_last(pointer(r));
end;

function go_first(r : EditorStr) : EditorStr;
begin
        if memType = MT_SXMS then go_first := EditorStr(strssxms.go_first(dword(r)))
        else if memType = MT_SWAP then go_first := EditorStr(strsswap.go_first(dword(r)))
        else go_first := EditorStr(strsdos.go_first(pointer(r)));
end;

function go_last(r : EditorStr) : EditorStr;
begin
        if memType = MT_SXMS then go_last := EditorStr(strssxms.go_last(dword(r)))
        else if memType = MT_SWAP then go_last := EditorStr(strsswap.go_last(dword(r)))
        else go_last := EditorStr(strsdos.go_last(pointer(r)));
end;

function go_prev(r : EditorStr) : EditorStr;
begin
        if memType = MT_SXMS then go_prev := EditorStr(strssxms.go_prev(dword(r)))
        else if memType = MT_SWAP then go_prev := EditorStr(strsswap.go_prev(dword(r)))
        else go_prev := EditorStr(strsdos.go_prev(pointer(r)));
end;

function go_next(r : EditorStr) : EditorStr;
begin
        if memType = MT_SXMS then go_next := EditorStr(strssxms.go_next(dword(r)))
        else if memType = MT_SWAP then go_next := EditorStr(strsswap.go_next(dword(r)))
        else go_next := EditorStr(strsdos.go_next(pointer(r)));
end;

procedure free(r : EditorStr);
begin
        if memType = MT_SXMS then strssxms.free(dword(r))
        else if memType = MT_SWAP then strsswap.free(dword(r))
        else strsdos.free(pointer(r));
end;

function renum(r : EditorStr) : dword;
begin
        spinner_start;
        if memType = MT_SXMS then renum := strssxms.renum(dword(r))
        else if memType = MT_SWAP then renum := strsswap.renum(dword(r))
        else renum := strsdos.renum(pointer(r));
        spinner_stop;
end;

function get_num(r : EditorStr) : dword;
begin
        if memType = MT_SXMS then get_num := strssxms.get_num(dword(r))
        else if memType = MT_SWAP then get_num := strsswap.get_num(dword(r))
        else get_num := strsdos.get_num(pointer(r));
end;

function find_num(r : EditorStr; num : dword) : EditorStr;
begin
        spinner_start;
        while not is_nil(r) do begin
                if num = strs.get_num(r) then break;
                r := strs.go_next(r);
        end;
        spinner_stop;
        find_num := r;
end;

function delete(r : EditorStr; num_from, num_to : dword) : EditorStr;
begin
        spinner_start;
        if memType = MT_SXMS then delete := EditorStr(strssxms.delete(dword(r), num_from, num_to))
        else if memType = MT_SWAP then delete := EditorStr(strsswap.delete(dword(r), num_from, num_to))
        else delete := EditorStr(strsdos.delete(pointer(r), num_from, num_to));
        spinner_stop;
end;

function merge(r : EditorStr; var merged : boolean) : EditorStr;
begin
        if memType = MT_SXMS then merge := EditorStr(strssxms.merge(dword(r), merged))
        else if memType = MT_SWAP then merge := EditorStr(strsswap.merge(dword(r), merged))
        else merge := EditorStr(strsdos.merge(pointer(r), merged));
end;

function paste_parts(r:EditorStr; prefix,suffix:string; p:pchar; size:word;
                     var column:integer; var added:word):EditorStr;
var body,empty:string; i:word; c:char;
begin
        body:=prefix; empty:=''; i:=0; added:=0;
        while i<size do begin
                c:=p[i]; inc(i);
                if c in [#10,#13] then begin
                        r:=strs.put(r,body);
                        r:=strs.create(strs.go_next(r),r,empty);
                        body:=''; inc(added);
                        if (c=#13) and (i<size) then if p[i]=#10 then inc(i);
                end else body:=body+c;
        end;
        column:=length(body)+1;
        body:=body+suffix;
        paste_parts:=strs.put(r,body);
end;

function append(r : EditorStr; var pos : integer; p : pchar; var lnum:word) : EditorStr;
begin
        spinner_start;
        if memType = MT_SXMS then append := EditorStr(strssxms.append(dword(r), pos, p, lnum))
        else if memType = MT_SWAP then append := EditorStr(strsswap.append(dword(r), pos, p, lnum))
        else append := EditorStr(strsdos.append(pointer(r), pos, p, lnum));
        spinner_stop;
end;

function split(r : EditorStr; pos : integer) : EditorStr;
begin
        if memType = MT_SXMS then split := EditorStr(strssxms.split(dword(r), pos))
        else if memType = MT_SWAP then split := EditorStr(strsswap.split(dword(r), pos))
        else split := strsdos.split(pointer(r), pos);
end;

function is_nil(r : EditorStr) : boolean;
begin
        if memType = MT_SXMS then is_nil := strssxms.is_nil(dword(r))
        else if memType = MT_SWAP then is_nil := strsswap.is_nil(dword(r))
        else is_nil := strsdos.is_nil(pointer(r));
end;

end.
