{ SPDX-License-Identifier: MIT }
program xmstest;
uses xmsshim,exms;
const poisons:array[1..6] of byte=(0,1,4,7,31,255);
      sizes:array[1..6] of word=(0,1,7,4095,4096,65535);
var output:text; checks:integer; i,j:integer; handle:word; expected:longint;
procedure check(ok:boolean; message:string);
begin
        inc(checks);
        if not ok then begin
                writeln(output,'FAIL ',checks,' ',message,' got ',requested,' expected ',expected);
                close(output); restore_driver; Halt(1);
        end;
end;
function request(pages:word; poison:byte):word; assembler;
asm
        mov cl,poison
        push pages
        call xms_malloc
end;
begin
        Assign(output,'A:\XMS.LOG'); Rewrite(output); checks:=0;
        check(exms_check_driver,'mock driver detected');
        for i:=1 to 6 do for j:=1 to 6 do begin
                if (not classic) or (sizes[j]<=4095) then begin
                        expected:=longint(sizes[j])*16;
                        refuse:=false; requested:=-1; called_function:=0;
                        handle:=request(sizes[j],poisons[i]);
                        check(handle=$beef,'allocation handle returned');
                        check(requested=expected,'requested KiB independent of incoming CL');
                        if classic then check(called_function=$09,'ordinary allocation function')
                        else check(called_function=$c9,'SXMS allocation function');
                        refuse:=true;
                        handle:=request(sizes[j],poisons[i]);
                        check(handle=0,'failed allocation returns zero handle');
                end;
        end;
        restore_driver;
        writeln(output,'PASS ',checks,' assertions'); Close(output);
        Assign(output,'A:\XMS.OK'); Rewrite(output);
        if classic then writeln(output,'CLASSIC XMS PASS')
        else writeln(output,'SXMS PASS'); Close(output);
end.
