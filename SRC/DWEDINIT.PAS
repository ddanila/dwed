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
unit dwedinit;
interface
uses dwedtype;
procedure process_param(var config:TConfig; key,value:string);
procedure split(var param,key,value:string);
function load_config(var ctx:TEditorContext; fname:string):integer;
function restore_session(var ctx:TEditorContext):integer;
implementation
uses system2, dos, dosread, doslines, str, strutil, ansi, strs, dwedutil, unredo;
procedure process_param(var config : TConfig; key, value : string);
begin
        if length(key) = 0 then exit;
        if key = CFG_TAB_SIZE then config.tab_size := ahtob(value)
        else if key = CFG_COLOR_TOP then config.color.top := ahtob(value)
        else if key = CFG_COLOR_TOP_HL then config.color.top_hl := ahtob(value)
        else if key = CFG_COLOR_TEXT then config.color.text := ahtob(value)
        else if key = CFG_COLOR_TEXT_HL then config.color.text_hl := ahtob(value)
        else if key = CFG_COLOR_TEXT_DL then config.color.text_dl := ahtob(value)
        else if key = CFG_COLOR_TEXT_SEL then config.color.text_sel := ahtob(value)
        else if key = CFG_COLOR_MENU then config.color.menu := ahtob(value)
        else if key = CFG_COLOR_MENU_SEL then config.color.menu_sel := ahtob(value)
        else if key = CFG_COLOR_HELP_MENU then config.color.help_menu := ahtob(value)
        else if key = CFG_COLOR_HELP_MENU_SEL then config.color.help_menu_sel := ahtob(value)
        else if key = CFG_COLOR_HELP then config.color.help := ahtob(value)
        else if key = CFG_COLOR_HELP_HL then config.color.help_hl := ahtob(value)
        else if key = CFG_USR_DEF_F5 then config.udef_f5 := value
        else if key = CFG_USR_DEF_F8 then config.udef_f8 := value
        else if key = CFG_USR_DEF_F9 then config.udef_f9 := value
        else if key = CFG_HL_ENABLE then config.hl_enable := (ahtob(value) <> 0)
        else if key = CFG_MEMORY then config.memory := value
        else begin writelnerr('Unknown parameter ' + key + '. Press Enter...'); system.readln; end;
        if (config.tab_size < 1) or (config.tab_size > 32) then config.tab_size := 8;
end;

procedure split(var param, key, value : string);
var i : integer;
begin
        key := '';
        value := '';
        for i := 1 to length(param) do begin
                if param[i] = '=' then begin
                        key := copy(param, 1, i - 1);
                        value := copy(param, i + 1, length(param) - i);
                        break;
                end;
        end;
        if (length(key) = 0) and (length(value) = 0) then key := param;
        key := trim(key);
        upstr(key);
        value := trim(value);
end;

function load_config(var ctx:TEditorContext; fname:string):integer;
var lines,item:PInputLine; error:integer; candidate:TConfig; key,value:string; f:file; attr:word;
begin
        if ctx.file_reader.opened then begin load_config:=READ_PENDING; exit end;
        System.Assign(f,fname); GetFAttr(f,attr);
        if DosError=2 then begin load_config:=0; exit end;
        error:=read_lines(ctx.file_reader,fname,lines,0);
        if error=0 then begin
                candidate:=ctx.config; item:=lines;
                while item<>nil do begin
                        split(item^.value,key,value); process_param(candidate,key,value);
                        item:=item^.next;
                end;
                ctx.config:=candidate;
        end;
        free_lines(lines); load_config:=error;
end;

function session_fields(s:string; var x,scrx,scry:integer;
                        var row:longint; var fname:string):boolean;
var i,start,field,code:integer; numbers:array[1..4] of longint; part:string;
begin
        session_fields:=false; start:=1;
        for field:=1 to 4 do begin
                i:=start;
                while (i<=length(s)) and (s[i]<>',') do begin
                        if not (s[i] in ['0'..'9']) then exit;
                        inc(i);
                end;
                if (i>length(s)) or (i=start) then exit;
                part:=copy(s,start,i-start); val(part,numbers[field],code);
                if code<>0 then exit;
                start:=i+1;
        end;
        if (numbers[1]<1) or (numbers[1]>256) or
           (numbers[2]<0) or (numbers[2]>32767) or
           (numbers[3]<0) or (numbers[3]>32767) or (numbers[4]<1) then exit;
        x:=numbers[1]; scrx:=numbers[2]; scry:=numbers[3]; row:=numbers[4];
        fname:=copy(s,start,255); session_fields:=true;
end;

function restore_session(var ctx:TEditorContext):integer;
var lines,item:PInputLine; error,x,scrx,scry:integer; row:longint;
    fname:string; f:file; attr:word;
begin
        error:=read_lines(ctx.file_reader,ctx.temp,lines,UNDO_DEFAULT_RESERVE);
        if (error=0) and (lines=nil) then error:=METADATA_INVALID;
        if error=0 then begin
                item:=lines;
                while item<>nil do begin
                        if not session_fields(item^.value,x,scrx,scry,row,fname) then begin
                                error:=METADATA_INVALID; break;
                        end;
                        item:=item^.next;
                end;
        end;
        if error=0 then begin
                item:=lines;
                while item<>nil do begin
                        session_fields(item^.value,x,scrx,scry,row,fname);
                        if fname='' then error:=new_file(ctx,'') else begin
                                { A missing resume target must not become a new empty document. }
                                System.Assign(f,fname); GetFAttr(f,attr); error:=DosError;
                                if (error=0) and (attr and $18<>0) then error:=5;
                                if error=0 then load_file(ctx,fname,error,@load_file_progress);
                        end;
                        if error<>0 then break;
                        ctx.current^.editor.x:=x; ctx.current^.scrx:=scrx; ctx.current^.scry:=scry;
                        if row>ctx.current^.total then row:=ctx.current^.total;
                        ctx.current^.cline:=strs.find_num(ctx.current^.rline,row);
                        load_ed(ctx); norm_xy(ctx,0);
                        item:=item^.next;
                end;
        end;
        free_lines(lines);
        if error=0 then begin
                System.Assign(f,ctx.temp);
                {$I-} System.Erase(f); {$I+} error:=System.IOResult;
        end;
        restore_session:=error;
end;
end.
