{ SPDX-License-Identifier: MIT }
{$A-,F-}
unit saveinfo;
interface

type TSaveRecordV1 = packed record
        magic:array[0..7] of char;
        version,record_size:word;
        destination,temporary,backup,previous_backup:string;
        payload_size,payload_crc,record_crc:dword;
end;
TSaveRecord = packed record
        magic:array[0..7] of char;
        version,record_size:word;
        destination,temporary,backup,previous_backup:string;
        payload_size,payload_crc:dword;
        previous_size,previous_crc:dword;
        previous_known:word;
        record_crc:dword;
end;

function crc_update(crc:dword; var data; count:word):dword;
function path_directory(name:string):string;
function same_path(a,b:string):boolean;
function canonical_path(name:string):string;
function same_location(a,b:string):boolean;
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

function canonical_path(name:string):string;
var result,part:string; i,j,base:integer;
        function valid_part(s:string):boolean;
        var k:integer;
        begin
                valid_part:=false;
                for k:=1 to length(s) do
                        if (ord(s[k])<32) or (ord(s[k])=127) or
                           (s[k] in [':','*','?','"','<','>','|']) then exit;
                valid_part:=true;
        end;
begin
        canonical_path:='';
        for i:=1 to length(name) do begin
                if name[i]='/' then name[i]:='\';
                name[i]:=upcase(name[i]);
        end;
        if (length(name)>=3) and (name[1] in ['A'..'Z']) and
           (name[2]=':') and (name[3]='\') then begin
                result:=copy(name,1,3); i:=4;
        end else if copy(name,1,2)='\\' then begin
                i:=3; while (i<=length(name)) and (name[i]<>'\') do inc(i);
                if (i=3) or (i>=length(name)) then exit;
                part:=copy(name,3,i-3);
                if not valid_part(part) or (part='.') or (part='..') then exit;
                j:=i+1; while (j<=length(name)) and (name[j]<>'\') do inc(j);
                part:=copy(name,i+1,j-i-1);
                if (part='') or not valid_part(part) or (part='.') or (part='..') then exit;
                result:=copy(name,1,j-1);
                if length(result)>=255 then exit;
                result:=result+'\'; i:=j+1;
        end else exit;
        base:=length(result);
        while i<=length(name) do begin
                j:=i; while (j<=length(name)) and (name[j]<>'\') do inc(j);
                part:=copy(name,i,j-i); i:=j+1;
                if not valid_part(part) then exit;
                if part='..' then begin
                        if length(result)>base then begin
                                j:=length(result);
                                while (j>base) and (result[j]<>'\') do dec(j);
                                if j>base then dec(j);
                                result:=copy(result,1,j);
                        end;
                end else if (part<>'') and (part<>'.') then begin
                        if result[length(result)]<>'\' then result:=result+'\';
                        result:=result+part;
                end;
        end;
        if (name[length(name)]='\') and (result[length(result)]<>'\') then result:=result+'\';
        canonical_path:=result;
end;

function same_location(a,b:string):boolean;
begin
        a:=canonical_path(a); b:=canonical_path(b);
        same_location:=(a<>'') and (b<>'') and (a=b);
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
        move(signature,r.magic,sizeof(signature)); r.version:=2; r.record_size:=sizeof(r);
        r.record_crc:=crc_update($FFFFFFFF,r,sizeof(r)-sizeof(r.record_crc)) xor $FFFFFFFF;
end;

function owned_name(name,dir,prefix,extension:string):boolean;
var base:string; i:integer;
begin
        owned_name:=false;
        if not same_location(path_directory(name),dir) then exit;
        base:=copy(name,length(path_directory(name))+1,255);
        if length(base)<>11 then exit;
        if not same_path(copy(base,1,3),prefix) then exit;
        if not same_path(copy(base,8,4),extension) then exit;
        for i:=4 to 7 do if not (base[i] in ['0'..'9']) then exit;
        owned_name:=true;
end;

function valid_record(var r:TSaveRecord; journal:string):boolean;
var dir:string; i:integer; legacy:TSaveRecordV1; checksum:dword;
begin
        valid_record:=false;
        for i:=0 to 7 do if r.magic[i]<>signature[i] then exit;
        if r.version=1 then begin
                if (r.record_size<>sizeof(legacy)) or (r.previous_known<>0) or
                   (r.previous_size<>0) or (r.previous_crc<>0) then exit;
                move(r,legacy,sizeof(legacy)-4);
                checksum:=crc_update($FFFFFFFF,legacy,sizeof(legacy)-4) xor $FFFFFFFF;
        end else if r.version=2 then begin
                if (r.record_size<>sizeof(r)) or (r.previous_known>1) then exit;
                if (r.previous_known=0) and ((r.previous_size<>0) or (r.previous_crc<>0)) then exit;
                if (r.previous_known=1) and (r.previous_backup='') then exit;
                checksum:=crc_update($FFFFFFFF,r,sizeof(r)-4) xor $FFFFFFFF;
        end else exit;
        if r.record_crc<>checksum then exit;
        if canonical_path(r.destination)='' then exit;
        dir:=path_directory(r.destination);
        if length(dir)<3 then exit;
        if not (((dir[2]=':') and (dir[3]='\') and (upcase(dir[1]) in ['A'..'Z'])) or
                (copy(dir,1,2)='\\')) then exit;
        if length(r.destination)<=length(dir) then exit;
        if not owned_name(journal,dir,'$ER','.REC') then exit;
        if not owned_name(r.temporary,dir,'$ED','.TMP') then exit;
        if r.backup<>'' then
                if not same_location(r.backup,backup_name(r.destination)) then exit;
        if r.previous_backup<>'' then begin
                if r.backup='' then exit;
                if not owned_name(r.previous_backup,dir,'$EB','.TMP') then exit;
        end;
        if same_location(r.destination,r.temporary) or same_location(r.destination,journal) or
           same_location(r.destination,r.previous_backup) or same_location(r.backup,journal) then exit;
        valid_record:=true;
end;
end.
