{ SPDX-License-Identifier: MIT }
unit safesave;
interface

const SAVE_PENDING=1010;

type TSaveFile = record
        handle : word;
        opened : boolean;
        temporary, destination, backup, previous_backup : string;
        original_moved, published : boolean;
        cleanup_error, recovery_error : integer;
end;

procedure start_save(var f:TSaveFile; name:string; var error:integer);
procedure write_save(var f:TSaveFile; var data; count:word; var error:integer);
procedure finish_save(var f:TSaveFile; var error:integer);
procedure cancel_save(var f:TSaveFile);
function save_pending_files(var f:TSaveFile):boolean;
procedure retry_save_cleanup(var f:TSaveFile);

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
var code:integer;
begin
        if f.opened then begin
                code:=close_handle(f.handle);
                { Invalid handle on retry means close already released it. }
                if (code<>0) and (code<>6) then begin f.cleanup_error:=code; exit end;
                f.opened:=false;
        end;
        { A failed rollback leaves all recoverable generations in place. }
        if f.original_moved or (f.previous_backup<>'') then exit;
        if f.temporary<>'' then begin
                code:=remove_file(f.temporary);
                if (code=0) or (code=2) then f.temporary:=''
                else f.cleanup_error:=code;
        end;
end;

function park_backup(var f:TSaveFile):integer;
var attr:word; code,i,separator:integer; dir,number,candidate:string;
begin
        park_backup:=0;
        code:=attributes(f.backup,attr);
        if code=2 then exit;
        if (code=0) and (attr and $19<>0) then code:=5;
        if code<>0 then begin park_backup:=code; exit end;
        separator:=length(f.backup);
        while (separator>0) and (f.backup[separator]<>'\') and
              (f.backup[separator]<>':') do dec(separator);
        dir:=copy(f.backup,1,separator);
        for i:=0 to 9999 do begin
                str(i,number); while length(number)<4 do number:='0'+number;
                candidate:=dir+'$EB'+number+'.TMP';
                code:=attributes(candidate,attr);
                if code=2 then begin
                        { DOS rename refuses to overwrite a competing file. }
                        code:=move_file(f.backup,candidate);
                        if code=0 then begin f.previous_backup:=candidate; exit end;
                        if attributes(candidate,attr)<>0 then begin park_backup:=code; exit end;
                end else if code<>0 then begin park_backup:=code; exit end;
        end;
        park_backup:=80;
end;

procedure restore_generations(var f:TSaveFile);
begin
        if f.original_moved then begin
                f.recovery_error:=move_file(f.backup,f.destination);
                if f.recovery_error<>0 then exit;
                f.original_moved:=false;
        end;
        if f.previous_backup<>'' then begin
                f.recovery_error:=move_file(f.previous_backup,f.backup);
                if f.recovery_error=0 then f.previous_backup:='';
        end;
end;

function save_pending_files(var f:TSaveFile):boolean;
begin
        save_pending_files:=f.opened or f.original_moved or
                            (f.temporary<>'') or (f.previous_backup<>'');
end;

procedure retry_save_cleanup(var f:TSaveFile);
var code:integer;
begin
        f.cleanup_error:=0; f.recovery_error:=0;
        if f.opened then begin
                code:=close_handle(f.handle);
                if (code<>0) and (code<>6) then begin f.cleanup_error:=code; exit end;
                f.opened:=false;
        end;
        if f.published then begin
                if f.previous_backup<>'' then begin
                        f.cleanup_error:=remove_file(f.previous_backup);
                        if (f.cleanup_error=0) or (f.cleanup_error=2) then begin
                                f.previous_backup:=''; f.cleanup_error:=0;
                        end;
                end;
        end else begin
                restore_generations(f); cancel_save(f);
        end;
end;

function absolute_name(var name:string):integer;
var regs:registers; directory:TName; drive:byte; prefix,tail:string; i,n:integer;
begin
        absolute_name:=0;
        for i:=1 to length(name) do if name[i]='/' then name[i]:='\';
        { Network roots are already independent of the working directory. }
        if copy(name,1,2)='\\' then exit;
        tail:=name;
        if (length(name)>=2) and (name[2]=':') then begin
                if not (upcase(name[1]) in ['A'..'Z']) then begin absolute_name:=15; exit end;
                drive:=ord(upcase(name[1]))-ord('A')+1;
                System.delete(tail,1,2);
        end else begin
                fillchar(regs,sizeof(regs),0); regs.ah:=$19; intr($21,regs);
                drive:=regs.al+1;
                if drive>26 then begin absolute_name:=15; exit end;
        end;
        prefix:=chr(ord('A')+drive-1)+':';
        if (length(tail)>0) and (tail[1]='\') then begin
                if length(prefix)+length(tail)>255 then begin absolute_name:=3; exit end;
                name:=prefix+tail; exit;
        end;
        fillchar(directory,sizeof(directory),$FF); fillchar(regs,sizeof(regs),0);
        regs.ah:=$47; regs.dl:=drive; regs.ds:=seg(directory); regs.si:=ofs(directory);
        intr($21,regs); absolute_name:=result_code(regs);
        if regs.flags and 1<>0 then exit;
        n:=0;
        while (n<sizeof(directory)) and (directory[n]<>#0) do inc(n);
        if n>251 then begin absolute_name:=3; exit end;
        prefix:=prefix+'\';
        for i:=0 to n-1 do prefix:=prefix+directory[i];
        if n>0 then prefix:=prefix+'\';
        { Check before concatenating short strings; truncation can name a
          different real file. Do not use FExpand's silent truncation here. }
        if length(prefix)+length(tail)>255 then begin absolute_name:=3; exit end;
        name:=prefix+tail;
end;

procedure start_save(var f:TSaveFile; name:string; var error:integer);
var regs:registers; z:TName; attr:word; dir,number:string;
    i,separator:integer;
begin
        fillchar(f,sizeof(f),0); error:=absolute_name(name); f.destination:=name;
        if error<>0 then exit;
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
var regs:registers; attr:word; extension:string;
    i,separator,close_error:integer; existed:boolean;
begin
        if error<>0 then begin cancel_save(f); exit end;
        { Commit DOS buffers before closing and touching the old destination. }
        fillchar(regs,sizeof(regs),0); regs.ah:=$68; regs.bx:=f.handle;
        intr($21,regs); error:=result_code(regs);
        close_error:=close_handle(f.handle); f.opened:=close_error<>0;
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
                f.backup:=copy(f.destination,1,separator)+'.BAK';
                { Editing a .BAK file must not delete the destination itself. }
                extension:=copy(f.destination,separator+1,255);
                for i:=1 to length(extension) do extension[i]:=upcase(extension[i]);
                if extension='.BAK' then
                        f.backup:=copy(f.destination,1,separator)+'.BK!';
                error:=park_backup(f);
                if error<>0 then begin cancel_save(f); exit end;
                error:=move_file(f.destination,f.backup);
                if error<>0 then begin
                        restore_generations(f); cancel_save(f); exit;
                end;
                f.original_moved:=true;
        end;
        error:=move_file(f.temporary,f.destination);
        if error<>0 then begin
                restore_generations(f); cancel_save(f);
        end else begin
                f.temporary:=''; f.original_moved:=false; f.published:=true;
                { Publication is complete. Cleanup cannot undo a successful
                  save; retain its path and error if the old backup persists. }
                if f.previous_backup<>'' then begin
                        f.cleanup_error:=remove_file(f.previous_backup);
                        if f.cleanup_error=0 then f.previous_backup:='';
                end;
        end;
end;
end.
