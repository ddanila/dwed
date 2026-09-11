{ SPDX-License-Identifier: MIT }
{$F-}
unit dosread;
interface

const READ_PENDING=1011; READ_CHANGED=1012;
      RECORD_INVALID=1013; RECOVERY_MISMATCH=1014;
type TReadFile=record
        handle:word;
        opened:boolean;
        name:string;
        size:dword;
        close_error:integer;
end;

procedure open_read(var f:TReadFile; name:string; var error:integer);
procedure read_bytes(var f:TReadFile; var data; requested:word; var count:word; var error:integer);
procedure close_read(var f:TReadFile);

implementation
uses dos;

function result_code(var r:registers):integer;
begin
        if r.flags and 1<>0 then result_code:=r.ax else result_code:=0;
end;

procedure close_read(var f:TReadFile);
var r:registers;
begin
        f.close_error:=0;
        if not f.opened then exit;
        fillchar(r,sizeof(r),0); r.ah:=$3E; r.bx:=f.handle; intr($21,r);
        f.close_error:=result_code(r);
        if (f.close_error=0) or (f.close_error=6) then begin
                f.opened:=false; f.close_error:=0;
        end;
end;

procedure open_read(var f:TReadFile; name:string; var error:integer);
var r:registers; z:array[0..255] of char;
begin
        error:=READ_PENDING;
        if f.opened then exit;
        fillchar(f,sizeof(f),0); f.name:=name;
        fillchar(z,sizeof(z),0); move(name[1],z[0],length(name));
        fillchar(r,sizeof(r),0); r.ax:=$3D00; r.ds:=seg(z); r.dx:=ofs(z); intr($21,r);
        error:=result_code(r);
        if error<>0 then exit;
        f.handle:=r.ax; f.opened:=true;
        fillchar(r,sizeof(r),0); r.ax:=$4202; r.bx:=f.handle; intr($21,r);
        error:=result_code(r); f.size:=(dword(r.dx) shl 16) or r.ax;
        if error=0 then begin
                fillchar(r,sizeof(r),0); r.ax:=$4200; r.bx:=f.handle; intr($21,r);
                error:=result_code(r);
        end;
        if error<>0 then close_read(f);
end;

procedure read_bytes(var f:TReadFile; var data; requested:word; var count:word; var error:integer);
var r:registers;
begin
        count:=0;
        if error<>0 then exit;
        if not f.opened then begin error:=6; exit end;
        fillchar(r,sizeof(r),0); r.ah:=$3F; r.bx:=f.handle;
        r.ds:=seg(data); r.dx:=ofs(data); r.cx:=requested; intr($21,r);
        error:=result_code(r);
        if error=0 then begin
                if r.ax>requested then error:=READ_CHANGED else count:=r.ax;
        end;
end;
end.
