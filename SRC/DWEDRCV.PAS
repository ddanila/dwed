{ SPDX-License-Identifier: MIT }
{$F-}
unit dwedrcv;
interface
uses dwedtype,saveinfo;

const CLEANUP_RETAINED_BACKUP=1015;

function resolve_record(var ctx:TEditorContext; name:string; var expected:TSaveRecord; remove:boolean):integer;
procedure discover_recovery(var ctx:TEditorContext);
function recover_document(var ctx:TEditorContext; var info:TSaveRecord; source:string):integer;
function read_record(var ctx:TEditorContext; name:string; var info:TSaveRecord):integer;

implementation
uses dos,dosread,safesave,strs,dwedutil,dwedscru,dwedsave,kminput,scr,unredo;

function read_record(var ctx:TEditorContext; name:string; var info:TSaveRecord):integer;
var error:integer; count:word; extra:byte; legacy:TSaveRecordV1;
begin
        fillchar(info,sizeof(info),0);
        open_read(ctx.file_reader,name,error);
        if error=0 then begin
                if (ctx.file_reader.size<>sizeof(info)) and (ctx.file_reader.size<>sizeof(legacy)) then error:=RECORD_INVALID;
                read_bytes(ctx.file_reader,info,sizeof(info),count,error);
                if (error=0) and (count<>ctx.file_reader.size) then error:=RECORD_INVALID;
                if (error=0) and (info.version=1) and (count=sizeof(legacy)) then begin
                        move(info,legacy,sizeof(legacy)); fillchar(info,sizeof(info),0);
                        move(legacy,info,sizeof(legacy)-4); info.record_crc:=legacy.record_crc;
                end else if (error=0) and ((info.version<>2) or (count<>sizeof(info))) then error:=RECORD_INVALID;
                read_bytes(ctx.file_reader,extra,1,count,error);
                if (error=0) and ((count<>0) or not valid_record(info,name)) then error:=RECORD_INVALID;
                close_read(ctx.file_reader);
                if error=0 then error:=ctx.file_reader.close_error;
        end;
        read_record:=error;
end;

function payload_matches(var ctx:TEditorContext; name:string; expected_size,expected_crc:longword):integer;
var buffer:array[0..1023] of byte; error:integer; count:word; total,crc:longword;
begin
        open_read(ctx.file_reader,name,error); total:=0; crc:=$FFFFFFFF;
        if error=0 then begin
                if ctx.file_reader.size<>expected_size then error:=RECOVERY_MISMATCH;
                while error=0 do begin
                        read_bytes(ctx.file_reader,buffer,sizeof(buffer),count,error);
                        if (error<>0) or (count=0) then break;
                        inc(total,count); crc:=crc_update(crc,buffer,count);
                        if total>expected_size then error:=RECOVERY_MISMATCH;
                end;
                if (error=0) and ((total<>expected_size) or
                   ((crc xor $FFFFFFFF)<>expected_crc)) then error:=RECOVERY_MISMATCH;
                close_read(ctx.file_reader);
                if error=0 then error:=ctx.file_reader.close_error;
        end;
        payload_matches:=error;
end;

function resolve_record(var ctx:TEditorContext; name:string; var expected:TSaveRecord; remove:boolean):integer;
type TRecordBytes=array[0..sizeof(TSaveRecord)-1] of byte;
var info:TSaveRecord; error,i:integer; f:file; attr:word; has_temporary,has_previous:boolean;
        function erase_name(path:string):integer;
        begin
                System.Assign(f,path);
                {$I-} System.Erase(f); {$I+}
                erase_name:=System.IOResult;
        end;
begin
        { Every confirmation is revalidated before any deletion. The record is
          removed last so a failed deletion remains discoverable and retryable. }
        error:=read_record(ctx,name,info);
        if error=0 then for i:=0 to sizeof(info)-1 do
                if TRecordBytes(info)[i]<>TRecordBytes(expected)[i] then error:=RECORD_INVALID;
        has_previous:=false;
        if (error=0) and (info.previous_backup<>'') then begin
                System.Assign(f,info.previous_backup); GetFAttr(f,attr);
                if DosError=0 then begin
                        has_previous:=true;
                        if info.previous_known=0 then error:=CLEANUP_RETAINED_BACKUP
                        else error:=payload_matches(ctx,info.previous_backup,info.previous_size,info.previous_crc);
                end
                else if DosError<>2 then error:=DosError;
        end;
        if error=0 then error:=payload_matches(ctx,info.destination,info.payload_size,info.payload_crc);
        has_temporary:=false;
        if error=0 then begin
                System.Assign(f,info.temporary); GetFAttr(f,attr);
                if DosError=0 then begin
                        has_temporary:=true;
                        error:=payload_matches(ctx,info.temporary,info.payload_size,info.payload_crc);
                end else if DosError<>2 then error:=DosError;
        end;
        if (error=0) and remove then begin
                if has_temporary then error:=erase_name(info.temporary);
                if (error=0) and has_previous then error:=erase_name(info.previous_backup);
                if error=0 then error:=erase_name(name);
        end;
        resolve_record:=error;
end;

function recover_document(var ctx:TEditorContext; var info:TSaveRecord; source:string):integer;
var error:integer; root:EditorStr; format:TTextFormat;
begin
        root:=strs.from_file(ctx.file_reader,source,true,info.payload_size,info.payload_crc,format,error,nil);
        if error=0 then begin
                error:=new_file(ctx,info.destination);
                if error<>0 then begin
                        strs.free(root); recover_document:=error; exit;
                end;
                strs.free(ctx.current^.rline);
                with ctx.current^ do begin
                        rline:=root; cline:=root; scrline:=root;
                        total:=strs.renum(root); chg:=true;
                        sfname:='Recovered '+mk_short_name(info.destination);
                end;
                ctx.current^.format:=format; undo_unsaved(ctx.current^.history); load_ed(ctx);
        end;
        recover_document:=error;
end;

function candidate(var info:TSaveRecord):string;
var f:file; attr:word;
begin
        candidate:=info.temporary;
        System.Assign(f,info.temporary); GetFAttr(f,attr);
        { Only an absent temporary selects the destination; read/access errors
          must not silently substitute some other file. }
        if DosError=2 then candidate:=info.destination;
end;

procedure offer_record(var ctx:TEditorContext; name:string; var stop:boolean);
var info:TSaveRecord; error,cleanup_error,row,width,scroll,visible:integer; source,number:string; key:byte; done,settled,confirm_cleanup:boolean;
        procedure line(value:string);
        begin
                repeat
                        if (row>=scroll) and (row<scroll+visible) then
                                scr.print(2,2+row-scroll,ctx.config.color.text,copy(value,1,width));
                        System.delete(value,1,width); inc(row);
                until value='';
        end;
begin
        error:=read_record(ctx,name,info); width:=scr.getwidth-4;
        if width<1 then width:=1;
        source:=''; if error=0 then source:=candidate(info);
        scroll:=0; visible:=scr.getheight-5;
        done:=false; confirm_cleanup:=false; cleanup_error:=0;
        repeat
                scr.cls(ctx.config.color.text);
                scr.print(1,0,ctx.config.color.top,'Interrupted save'); row:=0;
                line('Recovery record:'); line(name);
                if error=0 then begin
                        line('Destination:'); line(info.destination);
                        line('Saved copy:'); line(source);
                        if confirm_cleanup then begin
                                line('The destination matches the recorded saved contents.');
                                line('Remove the listed recovery files?');
                                line('Temporary:'); line(info.temporary);
                                if info.previous_known=1 then begin
                                        line('Verified older backup, if still present:'); line(info.previous_backup);
                                end;
                                line('The destination and normal backup will be kept.');
                                scr.print(1,scr.getheight-2,ctx.config.color.top,'D Remove listed files   Enter/Esc Keep');
                        end else begin
                                line('R opens a verified copy as an unsaved document.');
                                line('C checks whether the saved copy is already installed.');
                                if cleanup_error<>0 then begin
                                        str(cleanup_error,number); line('Cleanup unavailable. Error #'+number);
                                        if cleanup_error=CLEANUP_RETAINED_BACKUP then begin
                                                line('An older backup has no recorded fingerprint; keep it.');
                                                line(info.previous_backup);
                                        end;
                                end;
                                scr.print(1,scr.getheight-2,ctx.config.color.top,'R Recover  C Check cleanup  S Skip  Esc Skip all');
                        end;
                end else begin
                        str(error,number); line('Cannot recover this record. Error #'+number);
                        if source<>'' then begin line('Saved copy:'); line(source) end;
                        line('Its files have been left in place.');
                        scr.print(1,scr.getheight-2,ctx.config.color.top,'R Retry  S Skip  Esc Skip all');
                end;
                scr.print(1,scr.getheight-1,ctx.config.color.top,'Up/Down Scroll');
                scr.cursor_off; scr.show; key:=hi(kbd_getkey);
                case key of
                SCAN_ESC:if confirm_cleanup then confirm_cleanup:=false
                         else begin stop:=true; done:=true end;
                SCAN_ENTER:if confirm_cleanup then confirm_cleanup:=false else done:=true;
                SCAN_S:if not confirm_cleanup then done:=true;
                SCAN_C:if (error=0) and not confirm_cleanup then begin
                        cleanup_error:=resolve_record(ctx,name,info,false);
                        confirm_cleanup:=cleanup_error=0; scroll:=0;
                end;
                SCAN_D:if confirm_cleanup then begin
                        cleanup_error:=resolve_record(ctx,name,info,true);
                        confirm_cleanup:=false; scroll:=0;
                        if cleanup_error=0 then done:=true;
                end;
                SCAN_UP:if scroll>0 then dec(scroll);
                SCAN_DOWN:if scroll+visible<row then inc(scroll);
                SCAN_R:if confirm_cleanup then confirm_cleanup:=false
                       else if error=0 then begin
                        error:=recover_document(ctx,info,source);
                        if error=0 then done:=true;
                        scroll:=0;
                end else begin
                        close_read(ctx.file_reader);
                        if ctx.file_reader.opened then error:=ctx.file_reader.close_error
                        else begin
                                error:=read_record(ctx,name,info);
                                source:=''; if error=0 then source:=candidate(info);
                        end;
                        scroll:=0;
                end;
                end;
        until done;
        dwedscru.update(ctx,SCRU_FULL);
        if ctx.file_reader.opened then begin
                settled:=pending_save_dialog(ctx,false);
                if not settled then stop:=true;
        end;
end;

procedure discover_recovery(var ctx:TEditorContext);
var i,j,error:integer; initial,dir,name:string;
    found:searchrec; stop,duplicate:boolean;
        function argument_directory(index:integer):string;
        var value:string; code:integer;
        begin
                argument_directory:='';
                if index=0 then begin argument_directory:=initial; exit end;
                value:=paramstr(index);
                if (value='') or (value[1] in ['-','/']) then exit;
                code:=absolute_name(value);
                if code=0 then argument_directory:=canonical_path(path_directory(value));
        end;
begin
        initial:='.'; error:=absolute_name(initial);
        if error=0 then begin
                initial:=canonical_path(initial);
                if (initial<>'') and (initial[length(initial)]<>'\') then initial:=initial+'\';
        end else initial:='';
        stop:=false;
        for i:=0 to paramcount do begin
                dir:=argument_directory(i); duplicate:=false;
                for j:=0 to i-1 do if dir=argument_directory(j) then duplicate:=true;
                if (dir<>'') and not duplicate and (length(dir)+11<=255) then begin
                        FindFirst(dir+'$ER????.REC',AnyFile,found);
                        while (DosError=0) and not stop do begin
                                if found.attr and (Directory+VolumeID)=0 then begin
                                        name:=dir+found.name;
                                        offer_record(ctx,name,stop);
                                end;
                                if not stop then FindNext(found);
                        end;
                        FindClose(found);
                end;
                if stop then exit;
        end;
end;
end.
