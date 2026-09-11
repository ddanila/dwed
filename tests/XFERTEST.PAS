{ SPDX-License-Identifier: MIT }
{$A-}
program xfertest;
uses xmsshim,emsshim,exms;
type TXRequest=record
        count:longint; src_handle:word; src_offset:longint;
        dst_handle:word; dst_offset:longint; src_high,dst_high:byte;
end;
var output:text; checks:longint; buffer:array[0..16383] of byte;
    i:word; request:TXRequest; status:byte; direction:MEM_COPY_DIRECTION;
procedure check(ok:boolean; message:string);
begin
        inc(checks);
        if not ok then begin
                writeln(output,'FAIL ',checks,' ',message); Close(output);
                restore_ems; restore_driver; Halt(1);
        end;
end;
begin
        Assign(output,'A:\XFER.LOG'); Rewrite(output); checks:=0;
        for i:=0 to 16383 do begin buffer[i]:=byte(i xor $a5); page_data[i]:=byte(i xor $5a) end;
        { The legacy entry point must also copy instead of exchanging source bytes. }
        ems_copy($1234,0,buffer,DOS2EXT);
        for i:=0 to 16383 do begin
                check(buffer[i]=byte(i xor $a5),'EMS write retains source');
                check(page_data[i]=buffer[i],'EMS write copies destination');
                buffer[i]:=0;
        end;
        check(ems_function=$5700,'EMS copy function, not exchange');
        ems_copy($1234,0,buffer,EXT2DOS);
        for i:=0 to 16383 do begin
                check(buffer[i]=byte(i xor $a5),'EMS read copies destination');
                check(page_data[i]=buffer[i],'EMS read retains source');
        end;
{$IFNDEF LEGACY_TRANSFER}
        ems_refuse:=true;
        status:=ems_try_copy($1234,0,buffer,DOS2EXT);
        check(status=$88,'EMS failure status propagated');
        ems_refuse:=false;
        check(ems_try_copy($1234,0,buffer,EXT2DOS)=0,'EMS success status');
        for direction:=DOS2EXT to EXT2DOS do begin
                refuse:=false;
                status:=exms_try_copy($beef,$ffff,buffer,direction);
                check(status=0,'XMS transfer success status');
                Move(transfer,request,sizeof(request));
                check(request.count=16384,'XMS transfer size');
                if classic then check(called_function=$0b,'ordinary XMS move function')
                else check(called_function=$cb,'SXMS move function');
                if direction=DOS2EXT then begin
                        check(request.src_handle=0,'conventional source handle');
                        check(request.src_offset=longint(@buffer),'conventional source address');
                        check(request.dst_handle=$beef,'extended destination handle');
                        check(request.dst_offset=longint($ffff)*16384,'extended destination offset');
                end else begin
                        check(request.dst_handle=0,'conventional destination handle');
                        check(request.dst_offset=longint(@buffer),'conventional destination address');
                        check(request.src_handle=$beef,'extended source handle');
                        check(request.src_offset=longint($ffff)*16384,'extended source offset');
                end;
                check((request.src_high=0) and (request.dst_high=0),'wide extension bytes');
                refuse:=true;
                check(exms_try_copy($beef,0,buffer,direction)=$a0,'XMS failure status propagated');
        end;
{$ENDIF}
        restore_ems; restore_driver;
        writeln(output,'PASS ',checks,' assertions'); Close(output);
        Assign(output,'A:\XFER.OK'); Rewrite(output); writeln(output,'TRANSFER PASS'); Close(output);
end.
