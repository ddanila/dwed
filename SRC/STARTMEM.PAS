{ SPDX-License-Identifier: MIT }
unit startmem;
interface
{ Only for initialization before opening or recovering any document. }
procedure startup_fail(stage:string);
function startup_alloc(size:word; stage:string):pointer;
implementation
procedure startup_fail(stage:string);
begin
        System.Writeln('EDIT: Not enough memory for ',stage,'.');
        Halt(8);
end;
function startup_alloc(size:word; stage:string):pointer;
var p:pointer;
begin
        p:=nil;
        if MaxAvail>=size then GetMem(p,size);
        if p=nil then startup_fail(stage);
        startup_alloc:=p;
end;
end.
