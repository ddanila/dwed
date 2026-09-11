{ SPDX-License-Identifier: MIT }
{$F-}
unit dwedsave;
interface
uses dwedtype;

{ The transaction belongs to the editor, even after its document is closed.
  Leaving closed recovery files requires an explicit choice at editor exit. }
function pending_save_dialog(var ctx:TEditorContext; leaving:boolean):boolean;

implementation
uses safesave, scr, kminput, str, dwedscru;

function pending_save_dialog(var ctx:TEditorContext; leaving:boolean):boolean;
var scroll,row,width,height,visible:integer; key:byte; finished:boolean;

        procedure line(s:string);
        var part:string;
        begin
                repeat
                        part:=copy(s,1,width); System.delete(s,1,width);
                        if (row>=scroll) and (row<scroll+visible) then
                                scr.print(2,3+row-scroll,ctx.config.color.text,part);
                        inc(row);
                until s='';
        end;

        procedure path(label_text,name:string);
        begin
                if name='' then exit;
                line(label_text); line(name);
        end;

        procedure draw;
        begin
                scr.cls(ctx.config.color.text);
                if ctx.pending_save.published then
                        scr.print(1,0,ctx.config.color.top,'Saved; cleanup pending')
                else scr.print(1,0,ctx.config.color.top,'Save recovery');
                row:=0;
                line('These files belong to the previous save.');
                if ctx.pending_save.opened then line('Temporary file is still open.');
                if ctx.pending_save.journal_opened then line('Recovery record is still open.');
                if ctx.pending_save.cleanup_error<>0 then
                        line('Close/cleanup error: #'+itoa(ctx.pending_save.cleanup_error));
                if ctx.pending_save.recovery_error<>0 then
                        line('Rollback error: #'+itoa(ctx.pending_save.recovery_error));
                path('Recovery record:',ctx.pending_save.journal);
                path('Destination:',ctx.pending_save.destination);
                path('Temporary retained:',ctx.pending_save.temporary);
                if ctx.pending_save.original_moved then
                        path('Original retained:',ctx.pending_save.backup);
                path('Previous backup retained:',ctx.pending_save.previous_backup);
                if not ctx.pending_save.published then
                        line('Retry restores old files and removes the temporary.');
                line('Return to editing to keep these files pending.');
                scr.print(1,height-3,ctx.config.color.top,'R Retry cleanup   Enter/Esc Return');
                if leaving and not ctx.pending_save.opened and not ctx.pending_save.journal_opened then
                        scr.print(1,height-2,ctx.config.color.top,'K Keep files and leave');
                scr.print(1,height-1,ctx.config.color.top,'Up/Down Scroll');
                scr.cursor_off; scr.show;
        end;

begin
        pending_save_dialog:=true;
        if not save_pending_files(ctx.pending_save) then exit;
        pending_save_dialog:=false; scroll:=0; finished:=false;
        width:=scr.getwidth-4; if width<1 then width:=1;
        height:=scr.getheight; visible:=height-6;
        if visible<1 then visible:=1;
        kbd_reset;
        repeat
                draw; key:=hi(kbd_getkey);
                case key of
                SCAN_ESC,SCAN_ENTER:finished:=true;
                SCAN_UP:if scroll>0 then dec(scroll);
                SCAN_DOWN:if scroll+visible<row then inc(scroll);
                SCAN_R:begin
                        retry_save_cleanup(ctx.pending_save);
                        if not save_pending_files(ctx.pending_save) then begin
                                pending_save_dialog:=true; finished:=true;
                        end;
                        scroll:=0;
                end;
                SCAN_K:if leaving and not ctx.pending_save.opened and not ctx.pending_save.journal_opened then begin
                        pending_save_dialog:=true; finished:=true;
                end;
                end;
        until finished;
        { Repaint from the live document; recovery needs no screen-copy heap. }
        dwedscru.update(ctx,SCRU_FULL);
end;
end.
