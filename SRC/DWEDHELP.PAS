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
unit dwedhelp;

interface

procedure dwed_help(var topic_id:integer;
        help_menu_clr,
        help_menu_sel_clr,
        help_clr,
        help_hl_clr : byte);

implementation

uses kminput, event, scr, scrui, str, help, startmem;

{$IFDEF FPC}
{$I helpdata.inc}
{$ELSE}
procedure helpbin;external;
{$L dwedhelp.obj}
{$ENDIF}

var     topic_list : PHelpTopicList;
        topic_menu : pchar;
        width      : integer;

function get_name(t : PHelpTopicList):string;
var     s : string;
        i : integer;
begin
        s := '';
        for i := 1 to 12 do s := s + t^.topic.name[i];
        get_name := trim(s);
end;

procedure draw_topic(r:PHelpTopicList; scroll:integer; var rows:integer; clr,hlclr:byte);
var p:pchar; remaining:integer; source:string; columns,visible:integer;
        procedure source_line(value:string);
        var part:string; i,cells:integer; highlighted:boolean;
                procedure flush;
                begin
                        if (rows>=scroll) and (rows<scroll+visible) then
                                scr.printhl(width+5,4+rows-scroll,clr,hlclr,part);
                        inc(rows); part:=''; cells:=0;
                        if highlighted then part:='~';
                end;
        begin
                if copy(value,1,3)='///' then exit;
                part:=''; cells:=0; highlighted:=false;
                for i:=1 to length(value) do begin
                        if ((cells=columns) and (value[i]<>'~')) or (length(part)>=253) then flush;
                        part:=part+value[i];
                        if value[i]='~' then highlighted:=not highlighted else inc(cells);
                end;
                flush;
        end;
begin
        columns:=scr.getwidth-width-5; visible:=scr.getheight-5; rows:=0;
        if (columns<1) or (visible<1) then exit;
        p:=r^.htext; remaining:=r^.hlen; source:='';
        while remaining>0 do begin
                case p[0] of
                #10:begin source_line(source); source:='' end;
                #13:;
                else source:=source+p[0];
                end;
                inc(p); dec(remaining);
        end;
        if source<>'' then source_line(source);
end;

procedure dwed_help(var topic_id:integer;
        help_menu_clr,
        help_menu_sel_clr,
        help_clr,
        help_hl_clr : byte);

var     r : PHelpTopicList;
        i,scroll,rows : integer;
        selItem   : integer;
        e         : TEvent;
begin
        scr.cursor_off;
        r := nil;
        selItem := topic_id; scroll:=0; rows:=0;
        while true do begin
                r := topic_list;
                i := topic_id;
                while (i <> 0) and (r <> nil) do begin
                        dec(i);
                        r := r^.next;
                end;
                if r <> nil then begin
                        for i := 1 to scr.getheight - 1 do scr.cln(width + 4, i, help_clr);
                        scr.printhl(width + 5, 2, help_clr, help_hl_clr, copy('~' + #$9 + '~ Help topic - ~' + get_name(r) + '~',1,scr.getwidth-width-5));
                        draw_topic(r,scroll,rows,help_clr,help_hl_clr);
                        scr.print(width+5,scr.getheight-1,help_clr,
                                copy('Left/Right: text pages   Esc: back',1,scr.getwidth-width-5));
                end;
                while true do begin
                        scrui.vmenu(e, 0, 1, width + 4, scr.getheight - 1,
                                help_menu_clr, help_menu_sel_clr,
                                'Help', topic_menu, selItem);
                        if e.etype = KEYBOARD then break;
                end;
                case e.scancode of
                SCAN_ESC: break;
                SCAN_BS: break;
                SCAN_ENTER,SCAN_SPACE:begin topic_id:=selItem; scroll:=0 end;
                SCAN_LEFT:begin dec(scroll,scr.getheight-5); if scroll<0 then scroll:=0 end;
                SCAN_RIGHT:if scroll+scr.getheight-5<rows then inc(scroll,scr.getheight-5);
                end;
        end;
        kbd_reset;
end;

procedure init;
var     t           : PHelpTopicList;
        len, maxlen : integer;
        totallen    : integer;
        i, pos      : integer;
        topicname   : string;
begin
        topic_list := from_memory(Pointer(@helpbin));
        maxlen := 0;
        totallen := 0;
        t := topic_list;
        while t <> nil do begin
                topicname := get_name(t);
                len := t^.topic.lvl * 2 + length(topicname);
                if maxlen < len then maxlen := len;
                inc(totallen, len + 1);
                t := t^.next;
        end;
        topic_menu:=startup_alloc(totallen,'help menu');
        pos := 0;
        t := topic_list;
        while t <> nil do begin
                topicname := get_name(t);
                if topicname = '$' then break;
                if pos <> 0 then begin
                        topic_menu[pos] := #$0A;
                        inc(pos);
                end;
                topicname := lpad(topicname, length(topicname) + t^.topic.lvl * 2);
                for i := 1 to length(topicname) do begin
                        topic_menu[pos] := topicname[i];
                        inc(pos);
                end;
                t := t^.next;
        end;
        topic_menu[pos] := #0;
        width := maxlen;
end;

begin
        init;
end.
