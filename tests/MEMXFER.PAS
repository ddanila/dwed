{ SPDX-License-Identifier: MIT }
program memxfer;
uses exms;
var output:text; buffer:array[0..16383] of byte; handle,i:word;
    checks:longint; status:byte; use_ems:boolean;
procedure check(ok:boolean; message:string);
begin
        inc(checks);
        if not ok then begin writeln(output,'FAIL ',checks,' ',message); Close(output); Halt(1) end;
end;
function transfer(direction:MEM_COPY_DIRECTION):byte;
begin
        if use_ems then transfer:=ems_try_copy(handle,0,buffer,direction)
        else transfer:=xms_try_copy(handle,0,buffer,direction);
end;
begin
        Assign(output,'A:\MXFER.LOG'); Rewrite(output); checks:=0;
        use_ems:=ParamStr(1)='/EMS';
        if use_ems then handle:=ems_malloc(1) else handle:=xms_malloc(1);
        check(handle<>0,'real driver allocates page');
        for i:=0 to 16383 do buffer[i]:=byte(i xor (i shr 8) xor $a5);
        status:=transfer(DOS2EXT); check(status=0,'real driver write succeeds');
        for i:=0 to 16383 do begin
                check(buffer[i]=byte(i xor (i shr 8) xor $a5),'write retains conventional source');
                buffer[i]:=0;
        end;
        status:=transfer(EXT2DOS); check(status=0,'real driver read succeeds');
        for i:=0 to 16383 do check(buffer[i]=byte(i xor (i shr 8) xor $a5),'real driver round trip');
        FillChar(buffer,sizeof(buffer),$5a);
        status:=transfer(EXT2DOS); check(status=0,'second read succeeds');
        for i:=0 to 16383 do check(buffer[i]=byte(i xor (i shr 8) xor $a5),'read retains extended source');
        if use_ems then begin
                ems_free(handle);
                status:=ems_try_copy(handle,0,buffer,EXT2DOS);
        end else begin
                xms_free(handle);
                status:=xms_try_copy(handle,0,buffer,EXT2DOS);
        end;
        check(status<>0,'freed handle reports transfer failure');
        writeln(output,'PASS ',checks,' assertions'); Close(output);
        Assign(output,'A:\MXFER.OK'); Rewrite(output); writeln(output,'REAL TRANSFER PASS'); Close(output);
end.
