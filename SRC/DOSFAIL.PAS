{ SPDX-License-Identifier: MIT }
unit dosfail;
interface
implementation
uses dos;
var previous,previous_exit:pointer;

{$F+}
{ DOS invokes INT 24h on its own stack. Do not call DOS, allocate, or use
  Pascal locals here. Returning Fail lets checked handle I/O report its error. }
procedure critical_error; assembler; nostackframe;
asm
        mov al,3
        iret
end;

procedure restore_handler;
begin
        ExitProc:=previous_exit;
        SetIntVec($24,previous);
end;

begin
        GetIntVec($24,previous);
        SetIntVec($24,@critical_error);
        previous_exit:=ExitProc; ExitProc:=@restore_handler;
end.
