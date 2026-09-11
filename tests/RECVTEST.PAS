{ SPDX-License-Identifier: MIT }
program recvtest;
uses dos,saveinfo;
var output:text; record_file:file; info,changed:TSaveRecord;
    got:word; extra:byte; stage,code:integer; tests:longint; body,original,older:string;

procedure check(ok:boolean; message:string);
begin
        inc(tests);
        if not ok then begin writeln(output,'FAIL ',message); close(output); halt(1) end;
end;

procedure expect_file(name,expected:string);
var f:file; actual:string; count:word;
begin
        System.Assign(f,name); {$I-} System.Reset(f,1); {$I+}
        check(System.IOResult=0,'file exists: '+name);
        System.BlockRead(f,actual[1],255,count); System.Close(f); actual[0]:=chr(count);
        check(actual=expected,'file bytes: '+name);
end;

procedure expect_absent(name:string);
var f:file; attr:word;
begin
        System.Assign(f,name); GetFAttr(f,attr); check(DosError=2,'file absent: '+name);
end;

begin
        tests:=0; System.FileMode:=0;
        System.Assign(output,'A:\RECOVER.LOG'); System.Rewrite(output);
        val(paramstr(1),stage,code); check((code=0) and (stage>=0) and (stage<=4),'cut stage');
        original:='DWED_MARKER'+#13#10+'second line'+#13#10;
        body:='z'+original; older:='PREVIOUS_BACKUP'+#13#10;
        System.Assign(record_file,'C:\$ER0000.REC');
        {$I-} System.Reset(record_file,1); {$I+}
        check(System.IOResult=0,'journal survived restart');
        System.BlockRead(record_file,info,sizeof(info),got);
        check(got=sizeof(info),'complete journal record');
        System.BlockRead(record_file,extra,1,got); System.Close(record_file);
        check(got=0,'no trailing journal bytes');
        check(valid_record(info,'C:\$ER0000.REC'),'journal checksum and paths');
        check(info.destination='C:\SAMPLE.TXT','destination association');
        check(info.temporary='C:\$ED0001.TMP','payload association');
        check(info.backup='C:\SAMPLE.BAK','original association');
        check(info.previous_backup='C:\$EB0000.TMP','older backup association');
        check(info.previous_known=1,'older backup fingerprint present');
        check(info.previous_size=length(older),'older backup size');
        check(info.previous_crc=(crc_update($FFFFFFFF,older[1],length(older)) xor $FFFFFFFF),'older backup checksum');
        check(info.payload_size=length(body),'payload size');
        check(info.payload_crc=(crc_update($FFFFFFFF,body[1],length(body)) xor $FFFFFFFF),'payload checksum');
        if stage<3 then expect_file(info.temporary,body) else expect_absent(info.temporary);
        if stage<2 then expect_file(info.destination,original)
        else if stage=2 then expect_absent(info.destination)
        else expect_file(info.destination,body);
        if stage=0 then expect_file(info.backup,older)
        else if stage=1 then expect_absent(info.backup)
        else expect_file(info.backup,original);
        if (stage=0) or (stage=4) then expect_absent(info.previous_backup)
        else expect_file(info.previous_backup,older);
        expect_file('C:\$ED0000.TMP','OTHER_EDITOR_SAVE'+#13#10);
        body:='123456789';
        check((crc_update($FFFFFFFF,body[1],length(body)) xor $FFFFFFFF)=$CBF43926,'IEEE CRC check vector');
        changed:=info; changed.magic[0]:='X';
        check(not valid_record(changed,'C:\$ER0000.REC'),'damaged signature rejected');
        changed:=info; changed.payload_crc:=changed.payload_crc xor 1;
        check(not valid_record(changed,'C:\$ER0000.REC'),'damaged record rejected');
        changed:=info; changed.previous_crc:=changed.previous_crc xor 1;
        check(not valid_record(changed,'C:\$ER0000.REC'),'damaged backup fingerprint rejected');
        changed:=info; changed.version:=3;
        changed.record_crc:=crc_update($FFFFFFFF,changed,sizeof(changed)-4) xor $FFFFFFFF;
        check(not valid_record(changed,'C:\$ER0000.REC'),'unknown version rejected');
        changed:=info; dec(changed.record_size);
        changed.record_crc:=crc_update($FFFFFFFF,changed,sizeof(changed)-4) xor $FFFFFFFF;
        check(not valid_record(changed,'C:\$ER0000.REC'),'unknown record size rejected');
        changed:=info; changed.temporary:='C:\OTHER\$ED0001.TMP'; seal_record(changed);
        check(not valid_record(changed,'C:\$ER0000.REC'),'different directory rejected');
        changed:=info; changed.temporary:=info.destination; seal_record(changed);
        check(not valid_record(changed,'C:\$ER0000.REC'),'payload alias rejected');
        changed:=info; changed.backup:='C:\OTHER.BAK'; seal_record(changed);
        check(not valid_record(changed,'C:\$ER0000.REC'),'unrelated backup rejected');
        changed:=info; changed.destination:='SAMPLE.TXT'; seal_record(changed);
        check(not valid_record(changed,'C:\$ER0000.REC'),'relative destination rejected');
        check(not valid_record(info,'D:\$ER0000.REC'),'relocated journal rejected');
        writeln(output,'PASS ',tests,' assertions'); System.Close(output);
        System.Assign(output,'A:\RECOVER.OK'); System.Rewrite(output);
        writeln(output,'RESTART RECORD PASS'); System.Close(output);
end.
