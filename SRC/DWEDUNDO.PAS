{ SPDX-License-Identifier: MIT }
{$A-,F-}
unit dwedundo;
interface
uses dwedtype;
function start_edit(var ctx:TEditorContext):boolean;
procedure finish_edit(var ctx:TEditorContext);
procedure cancel_edit(var ctx:TEditorContext);
function replay_edit(var ctx:TEditorContext; forward:boolean):integer;
implementation
uses unredo,strs,strsdos,dwedutil,scr;
var snapshot:TFileContext;

function position_of(var filectx:TFileContext):TUndoPosition;
var p:TUndoPosition;
begin
        FillChar(p,sizeof(p),0);
        p.line:=strs.get_num(filectx.cline);
        p.top:=p.line-filectx.scry; if p.top<1 then p.top:=1;
        p.column:=filectx.editor.x; p.left:=filectx.scrx;
        p.selection:=filectx.editor.selection;
        p.anchor_line:=filectx.editor.sel_row;
        p.anchor_column:=filectx.editor.sel_x;
        position_of:=p;
end;

function start_edit(var ctx:TEditorContext):boolean;
begin
        start_edit:=strs.supports_undo;
        if not strs.supports_undo then exit;
        snapshot:=ctx.current^;
        transaction_bind(ctx.current^.history,ctx.current^.rline,position_of(ctx.current^));
end;

procedure finish_edit(var ctx:TEditorContext);
var redraw:integer;
begin
        commit(ctx);
        if transaction_structure then with ctx.current^ do begin
                rline:=strs.go_first(cline);
                total:=strs.renum(rline);
        end;
        redraw:=norm_xy(ctx,SCRU_FULL);
        transaction_commit(position_of(ctx.current^));
        ctx.current^.chg:=undo_dirty(ctx.current^.history);
end;

procedure cancel_edit(var ctx:TEditorContext);
begin
        transaction_cancel;
        ctx.current^:=snapshot;
        spinner_stop;
        handle_error(ctx,transaction_error);
end;

function replay_edit(var ctx:TEditorContext; forward:boolean):integer;
var group:PUndoGroup; p:TUndoPosition; errCode,redraw:integer; accepted:boolean;
begin
        replay_edit:=SCRU_NONE;
        if not strs.supports_undo then exit;
        if forward then group:=undo_next(ctx.current^.history)
        else group:=undo_previous(ctx.current^.history);
        if group=nil then exit;
        if not strsdos.replay_group(ctx.current^.rline,group,forward,
                                   ctx.current^.history.reserve,errCode) then begin
                handle_error(ctx,errCode); replay_edit:=SCRU_FULL; exit;
        end;
        if forward then p:=group^.after_position else p:=group^.before_position;
        accepted:=undo_accept(ctx.current^.history,group,forward);
        with ctx.current^ do begin
                total:=strs.renum(rline);
                cline:=strs.find_num(rline,p.line);
                if cline=nil then cline:=strs.go_last(rline);
                editor.x:=p.column; scrx:=p.left;
                scry:=strs.get_num(cline)-p.top;
                editor.selection:=p.selection; editor.sel_row:=p.anchor_line;
                editor.sel_x:=p.anchor_column; editor.chg:=false;
                chg:=undo_dirty(history);
        end;
        load_ed(ctx); redraw:=norm_xy(ctx,SCRU_FULL);
        replay_edit:=SCRU_FULL;
end;
end.
