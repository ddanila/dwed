{ SPDX-License-Identifier: MIT }
unit safesave;
interface

type TSaveFile = record
        handle : word;
        opened : boolean;
        temporary, destination : string;
end;

procedure start_save(var f:TSaveFile; name:string; var error:integer);
procedure write_save(var f:TSaveFile; var data; count:word; var error:integer);
procedure finish_save(var f:TSaveFile; var error:integer);
procedure cancel_save(var f:TSaveFile);

implementation
uses dos;

type TName = array[0..255] of char;

procedure name_z(s:string; var z:TName);
begin
        fillchar(z,sizeof(z),0);
        move(s[1],z[0],length(s));
end;

function result_code(var regs:registers):integer;
begin
        if regs.flags and 1 <> 0 then result_code:=regs.ax
        else result_code:=0;
end;

function attributes(name:string; var attr:word):integer;
var regs:registers; z:TName;
begin
        name_z(name,z); fillchar(regs,sizeof(regs),0);
        regs.ax:=$4300; regs.ds:=seg(z); regs.dx:=ofs(z);
        intr($21,regs); attr:=regs.cx; attributes:=result_code(regs);
end;

function remove_file(name:string):integer;
var regs:registers; z:TName;
begin
        name_z(name,z); fillchar(regs,sizeof(regs),0);
        regs.ah:=$41; regs.ds:=seg(z); regs.dx:=ofs(z);
        intr($21,regs); remove_file:=result_code(regs);
end;

function move_file(oldname,newname:string):integer;
var regs:registers; source,dest:TName;
begin
        name_z(oldname,source); name_z(newname,dest);
        fillchar(regs,sizeof(regs),0);
        regs.ah:=$56; regs.ds:=seg(source); regs.dx:=ofs(source);
        regs.es:=seg(dest); regs.di:=ofs(dest);
        intr($21,regs); move_file:=result_code(regs);
end;

function close_handle(handle:word):integer;
var regs:registers;
begin
        fillchar(regs,sizeof(regs),0); regs.ah:=$3E; regs.bx:=handle;
        intr($21,regs); close_handle:=result_code(regs);
end;

procedure cancel_save(var f:TSaveFile);
var ignored:integer;
begin
        if f.opened then ignored:=close_handle(f.handle);
        f.opened:=false;
        if f.temporary<>'' then ignored:=remove_file(f.temporary);
        f.temporary:='';
end;

procedure start_save(var f:TSaveFile; name:string; var error:integer);
var regs:registers; z:TName; attr:word; dir,number:string;
    i,separator:integer;
begin
        fillchar(f,sizeof(f),0); f.destination:=name;
        error:=attributes(name,attr);
        if error=0 then begin
                if attr and $19 <> 0 then error:=5;
        end else if error=2 then error:=0;
        if error<>0 then exit;
        separator:=length(name);
        while (separator>0) and (name[separator]<>'\') and
              (name[separator]<>':') do dec(separator);
        dir:=copy(name,1,separator);
        if length(dir)>243 then begin error:=3; exit end;
        { DOS create-new prevents collision with another editor's live save. }
        for i:=0 to 9999 do begin
                str(i,number);
                while length(number)<4 do number:='0'+number;
                f.temporary:=dir+'$ED'+number+'.TMP';
                name_z(f.temporary,z); fillchar(regs,sizeof(regs),0);
                regs.ah:=$5B; regs.ds:=seg(z); regs.dx:=ofs(z);
                intr($21,regs); error:=result_code(regs);
                if error=0 then begin
                        f.handle:=regs.ax; f.opened:=true; exit;
                end;
                if error<>80 then break;
        end;
        { Never erase a file which we did not create. }
        f.temporary:='';
end;

procedure write_save(var f:TSaveFile; var data; count:word; var error:integer);
var regs:registers;
begin
        if (error<>0) or (count=0) then exit;
        fillchar(regs,sizeof(regs),0); regs.ah:=$40; regs.bx:=f.handle;
        regs.ds:=seg(data); regs.dx:=ofs(data); regs.cx:=count;
        intr($21,regs); error:=result_code(regs);
        if (error=0) and (regs.ax<>count) then error:=101;
end;

procedure finish_save(var f:TSaveFile; var error:integer);
var regs:registers; attr:word; backup,extension:string;
    i,separator,close_error,rollback_error:integer; existed:boolean;
begin
        if error<>0 then begin cancel_save(f); exit end;
        { Commit DOS buffers before closing and touching the old destination. }
        fillchar(regs,sizeof(regs),0); regs.ah:=$68; regs.bx:=f.handle;
        intr($21,regs); error:=result_code(regs);
        close_error:=close_handle(f.handle); f.opened:=false;
        if error=0 then error:=close_error;
        if error<>0 then begin cancel_save(f); exit end;
        error:=attributes(f.destination,attr); existed:=error=0;
        if error=2 then error:=0;
        if existed and (attr and $19<>0) then error:=5;
        if error<>0 then begin cancel_save(f); exit end;
        if existed then begin
                separator:=length(f.destination); i:=separator;
                while (i>0) and (f.destination[i]<>'\') and
                      (f.destination[i]<>':') do begin
                        if (f.destination[i]='.') and (separator=length(f.destination)) then separator:=i-1;
                        dec(i);
                end;
                backup:=copy(f.destination,1,separator)+'.BAK';
                { Editing a .BAK file must not delete the destination itself. }
                extension:=copy(f.destination,separator+1,255);
                for i:=1 to length(extension) do extension[i]:=upcase(extension[i]);
                if extension='.BAK' then
                        backup:=copy(f.destination,1,separator)+'.BK!';
                error:=remove_file(backup);
                if error=2 then error:=0;
                if error=0 then error:=move_file(f.destination,backup);
                if error<>0 then begin cancel_save(f); exit end;
        end;
        error:=move_file(f.temporary,f.destination);
        if error<>0 then begin
                if existed then begin
                        rollback_error:=move_file(backup,f.destination);
                        { If rollback fails, retain both recoverable files. }
                        if rollback_error<>0 then exit;
                end;
                cancel_save(f);
        end else f.temporary:='';
end;
end.
