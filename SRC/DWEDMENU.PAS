{ SPDX-License-Identifier: MIT }
unit dwedmenu;
interface
uses dwedtype,dwedcmd,event;
procedure draw_menu_bar(var ctx:TEditorContext; active:integer);
function menu_request(var e:TEvent):integer;
function choose_menu(var ctx:TEditorContext; group:integer):TEditorCommand;
implementation
uses scr,scrui,kminput;
const
MenuX:array[0..4] of integer=(0,7,14,23,34);
MenuTitle:array[0..4] of string[9]=(' File ',' Edit ',' Search ',' Options ',' Help ');
MenuCount:array[0..4] of integer=(8,3,3,2,2);
Captions:array[0..4,0..7] of string[28]=(
 ('New','Open...             F3','Save                F2','Save as...    Shift-F2',
  'Save all','Close           Alt-F4','Windows...      Alt-F6','Exit               Esc'),
 ('Cut             Ctrl-X','Copy            Ctrl-C','Paste           Ctrl-V','','','','',''),
 ('Find / Replace... Ctrl-F','Next match      Ctrl-K','Go to line...   Ctrl-L','','','','',''),
 ('Syntax highlighting...','Insert / Overwrite','','','','','',''),
 ('Contents            F1','About','','','','','',''));
Mnemonics:array[0..4] of string[8]=('NOSALCWX','TCP','FNG','SI','CA');
Commands:array[0..4,0..7] of TEditorCommand=(
 (CMD_NEW,CMD_OPEN,CMD_SAVE,CMD_SAVE_AS,CMD_SAVE_ALL,CMD_CLOSE,CMD_WINDOWS,CMD_EXIT),
 (CMD_CUT,CMD_COPY,CMD_PASTE,CMD_NONE,CMD_NONE,CMD_NONE,CMD_NONE,CMD_NONE),
 (CMD_FIND,CMD_FIND_NEXT,CMD_GOTO,CMD_NONE,CMD_NONE,CMD_NONE,CMD_NONE,CMD_NONE),
 (CMD_HIGHLIGHT,CMD_INSERT_MODE,CMD_NONE,CMD_NONE,CMD_NONE,CMD_NONE,CMD_NONE,CMD_NONE),
 (CMD_HELP,CMD_ABOUT,CMD_NONE,CMD_NONE,CMD_NONE,CMD_NONE,CMD_NONE,CMD_NONE));

procedure draw_menu_bar(var ctx:TEditorContext; active:integer);
var i:integer; color:byte;
begin
        scr.cln(0,0,ctx.config.color.menu);
        for i:=0 to 4 do begin
                color:=ctx.config.color.menu;
                if i=active then color:=ctx.config.color.menu_sel;
                scr.print(MenuX[i],0,color,MenuTitle[i]);
                if i=active then scr.chcolor(MenuX[i]+1,0,(color and $F0) or $0E,1)
                else scr.chcolor(MenuX[i]+1,0,(color and $F0) or $04,1);
        end;
end;

function mouse_group(x:integer):integer;
var i:integer;
begin
        mouse_group:=-1;
        for i:=0 to 4 do
                if (x>=MenuX[i]) and (x<MenuX[i]+length(MenuTitle[i])) then
                        mouse_group:=i;
end;

function menu_request(var e:TEvent):integer;
begin
        menu_request:=-1;
        if (e.etype=MOUSE_PRESS_B1) and (e.mouse_y=0) then
                menu_request:=mouse_group(e.mouse_x)
        else if e.etype=KEYBOARD then begin
                if (e.scancode=SCAN_F10) and (e.ctrl_keys=0) then menu_request:=0
                else if e.ctrl_keys=key_alt then case e.scancode of
                SCAN_F:menu_request:=0;
                SCAN_E:menu_request:=1;
                SCAN_S:menu_request:=2;
                SCAN_O:menu_request:=3;
                SCAN_H:menu_request:=4;
                end;
        end;
end;

function enabled(var ctx:TEditorContext; command:TEditorCommand):boolean;
begin
        enabled:=true;
        if command in [CMD_CUT,CMD_COPY] then enabled:=ctx.current^.editor.selection;
        if command=CMD_PASTE then
                enabled:=(ctx.clipboard[0]<>#0) or ctx.has_wincb;
end;

function choose_menu(var ctx:TEditorContext; group:integer):TEditorCommand;
var e:TEvent; selected,i,j,x,other:integer; color:byte;
    caption:string; command:TEditorCommand; finished:boolean;
begin
        command:=CMD_NONE; selected:=0; finished:=false;
        scr.push;
        repeat
                scr.pop; scr.push;
                draw_menu_bar(ctx,group);
                x:=MenuX[group];
                if x+30>ctx.config.width then x:=ctx.config.width-30;
                scrui.box(x,1,30,MenuCount[group]+2,ctx.config.color.menu);
                for i:=0 to MenuCount[group]-1 do begin
                        caption:=Captions[group,i];
                        while length(caption)<28 do caption:=caption+' ';
                        color:=ctx.config.color.menu;
                        if i=selected then color:=ctx.config.color.menu_sel;
                        if not enabled(ctx,Commands[group,i]) then
                                color:=(color and $F0) or $08;
                        scr.print(x+1,i+2,color,caption);
                        if enabled(ctx,Commands[group,i]) then
                                for j:=1 to length(Captions[group,i]) do
                                        if upcase(caption[j])=Mnemonics[group][i+1] then begin
                                                if i=selected then color:=(color and $F0) or $0E
                                                else color:=(color and $F0) or $04;
                                                scr.chcolor(x+j,i+2,color,1);
                                                break;
                                        end;
                end;
                scr.cursor_off; scr.show;
                wait_event(e);
                other:=menu_request(e);
                if (e.etype=KEYBOARD) and (e.scancode=SCAN_F10) then finished:=true
                else if other>=0 then begin
                        group:=other; selected:=0;
                end else if e.etype=KEYBOARD then begin
                        case e.scancode of
                        SCAN_ESC,SCAN_F10:finished:=true;
                        SCAN_LEFT:begin group:=(group+4) mod 5; selected:=0 end;
                        SCAN_RIGHT:begin group:=(group+1) mod 5; selected:=0 end;
                        SCAN_UP:selected:=(selected+MenuCount[group]-1) mod MenuCount[group];
                        SCAN_DOWN:selected:=(selected+1) mod MenuCount[group];
                        SCAN_HOME:selected:=0;
                        SCAN_END:selected:=MenuCount[group]-1;
                        SCAN_ENTER:if enabled(ctx,Commands[group,selected]) then begin
                                command:=Commands[group,selected]; finished:=true;
                        end;
                        else
                                for i:=1 to MenuCount[group] do
                                        if upcase(e.ascii)=Mnemonics[group][i] then
                                                if enabled(ctx,Commands[group,i-1]) then begin
                                                        command:=Commands[group,i-1]; finished:=true;
                                                end;
                        end;
                end else if e.etype in [MOUSE_MOVE,MOUSE_PRESS_B1] then begin
                        if (e.mouse_x>x) and (e.mouse_x<x+29) and
                           (e.mouse_y>=2) and (e.mouse_y<MenuCount[group]+2) then begin
                                selected:=e.mouse_y-2;
                                if (e.etype=MOUSE_PRESS_B1) and enabled(ctx,Commands[group,selected]) then begin
                                        command:=Commands[group,selected]; finished:=true;
                                end;
                        end else if e.etype=MOUSE_PRESS_B1 then finished:=true;
                end;
        until finished;
        scr.pop;
        choose_menu:=command;
end;
end.
