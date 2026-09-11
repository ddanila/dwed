{ SPDX-License-Identifier: MIT }
{$A-,F-}
unit saveinfo;
interface

type TSaveRecord = packed record
        magic:array[0..7] of char;
        version,record_size:word;
        destination,temporary,backup,previous_backup:string;
        payload_size,payload_crc,record_crc:dword;
end;

function crc_update(crc:dword; var data; count:word):dword;
function path_directory(name:string):string;
function same_path(a,b:string):boolean;
function backup_name(name:string):string;
procedure seal_record(var r:TSaveRecord);
function valid_record(var r:TSaveRecord; journal:string):boolean;

implementation

type TBytes=array[0..65534] of byte;
const signature:array[0..7] of char=('D','W','E','D','S','A','V','E');

function crc_update(crc:dword; var data; count:word):dword;
var i:word; bit:byte;
begin
        i:=0;
        while i<count do begin
                crc:=crc xor TBytes(data)[i];
                for bit:=1 to 8 do
                        if crc and 1<>0 then crc:=(crc shr 1) xor $EDB88320
                        else crc:=crc shr 1;
                inc(i);
        end;
        crc_update:=crc;
end;

function path_directory(name:string):string;
var i:integer;
begin
        i:=length(name);
        while (i>0) and (name[i]<>'\') and (name[i]<>':') do dec(i);
        path_directory:=copy(name,1,i);
end;

function same_path(a,b:string):boolean;
var i:integer;
begin
        same_path:=false;
        if length(a)<>length(b) then exit;
        for i:=1 to length(a) do if upcase(a[i])<>upcase(b[i]) then exit;
        same_path:=true;
end;

function backup_name(name:string):string;
var i,separator:integer; extension:string;
begin
        separator:=length(name); i:=separator;
        while (i>0) and (name[i]<>'\') and (name[i]<>':') do begin
                if (name[i]='.') and (separator=length(name)) then separator:=i-1;
                dec(i);
        end;
        if separator>251 then begin backup_name:=''; exit end;
        extension:=copy(name,separator+1,255);
        if same_path(extension,'.BAK') then extension:='.BK!' else extension:='.BAK';
        backup_name:=copy(name,1,separator)+extension;
end;

procedure seal_record(var r:TSaveRecord);
begin
        move(signature,r.magic,sizeof(signature)); r.version:=1; r.record_size:=sizeof(r);
        r.record_crc:=crc_update($FFFFFFFF,r,sizeof(r)-sizeof(r.record_crc)) xor $FFFFFFFF;
end;

function owned_name(name,dir,prefix,extension:string):boolean;
var base:string; i:integer;
begin
        owned_name:=false;
        if not same_path(path_directory(name),dir) then exit;
        base:=copy(name,length(dir)+1,255);
        if length(base)<>11 then exit;
        if not same_path(copy(base,1,3),prefix) then exit;
        if not same_path(copy(base,8,4),extension) then exit;
        for i:=4 to 7 do if not (base[i] in ['0'..'9']) then exit;
        owned_name:=true;
end;

function valid_record(var r:TSaveRecord; journal:string):boolean;
var dir:string; i:integer;
begin
        valid_record:=false;
        for i:=0 to 7 do if r.magic[i]<>signature[i] then exit;
        if (r.version<>1) or (r.record_size<>sizeof(r)) then exit;
        if r.record_crc<>(crc_update($FFFFFFFF,r,sizeof(r)-sizeof(r.record_crc)) xor $FFFFFFFF) then exit;
        dir:=path_directory(r.destination);
        if length(dir)<3 then exit;
        if not (((dir[2]=':') and (dir[3]='\') and (upcase(dir[1]) in ['A'..'Z'])) or
                (copy(dir,1,2)='\\')) then exit;
        if length(r.destination)<=length(dir) then exit;
        if not owned_name(journal,dir,'$ER','.REC') then exit;
        if not owned_name(r.temporary,dir,'$ED','.TMP') then exit;
        if r.backup<>'' then
                if not same_path(r.backup,backup_name(r.destination)) then exit;
        if r.previous_backup<>'' then begin
                if r.backup='' then exit;
                if not owned_name(r.previous_backup,dir,'$EB','.TMP') then exit;
        end;
        if same_path(r.destination,r.temporary) or same_path(r.destination,journal) or
           same_path(r.destination,r.previous_backup) or same_path(r.backup,journal) then exit;
        valid_record:=true;
end;
end.
