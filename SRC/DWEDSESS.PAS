{ SPDX-License-Identifier: MIT }
{$F-}
unit dwedsess;
interface
uses dwedtype;
const SESSION_FORMAT=1017;
function store_session(var ctx:TEditorContext):integer;
implementation
uses safesave,strs,str,strutil;

function session_line(current:PFileContext; var line:string):boolean;
var i:integer;
begin
        session_line:=false;
        line:=itoa(current^.editor.x)+','+itoa(current^.scrx)+','+
              itoa(current^.scry)+','+ltoa(strs.get_num(current^.cline))+',';
        if length(line)+length(current^.fname)>255 then exit;
        for i:=1 to length(current^.fname) do
                if current^.fname[i] in [#0,#10,#13] then exit;
        line:=line+current^.fname;
        session_line:=true;
end;

function store_session(var ctx:TEditorContext):integer;
var current:PFileContext; count,i,j:integer; line,newline:string; error:integer;
begin
        store_session:=SAVE_PENDING;
        if save_pending_files(ctx.session_save) then exit;
        { Validate every record before opening an output file. }
        current:=ctx.all; count:=0;
        while current<>nil do begin
                if not session_line(current,line) then begin store_session:=SESSION_FORMAT; exit end;
                inc(count); current:=current^.next;
        end;
        start_save(ctx.session_save,ctx.temp,error);
        if error<>0 then begin store_session:=error; exit end;
        newline:=#13#10;
        { Keep the existing on-disk order without recursion proportional to the
          document count. The loader prepends each restored document. }
        for i:=count downto 1 do begin
                current:=ctx.all;
                for j:=2 to i do current:=current^.next;
                if not session_line(current,line) then error:=SESSION_FORMAT;
                write_save(ctx.session_save,line[1],length(line),error);
                write_save(ctx.session_save,newline[1],length(newline),error);
                if error<>0 then break;
        end;
        finish_save(ctx.session_save,error);
        store_session:=error;
end;
end.
