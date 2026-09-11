{ SPDX-License-Identifier: MIT }
{$F-}
unit dwedrcv;
interface
uses dwedtype,saveinfo;

procedure discover_recovery(var ctx:TEditorContext);
function recover_document(var ctx:TEditorContext; var info:TSaveRecord; source:string):integer;
function read_record(var ctx:TEditorContext; name:string; var info:TSaveRecord):integer;

implementation
uses dos,dosread,safesave,strs,dwedutil,dwedscru,dwedsave,kminput,scr,unredo;

function read_record(var ctx:TEditorContext; name:string; var info:TSaveRecord):integer;
var error:integer; count:word; extra:byte;
begin
        fillchar(info,sizeof(info),0);
        open_read(ctx.file_reader,name,error);
        if error=0 then begin
                if ctx.file_reader.size<>sizeof(info) then error:=RECORD_INVALID;
                read_bytes(ctx.file_reader,info,sizeof(info),count,error);
                if (error=0) and (count<>sizeof(info)) then error:=RECORD_INVALID;
                read_bytes(ctx.file_reader,extra,1,count,error);
                if (error=0) and ((count<>0) or not valid_record(info,name)) then error:=RECORD_INVALID;
                close_read(ctx.file_reader);
                if error=0 then error:=ctx.file_reader.close_error;
        end;
        read_record:=error;
end;

function recover_document(var ctx:TEditorContext; var info:TSaveRecord; source:string):integer;
var error:integer; root:EditorStr; format:TTextFormat;
begin
        root:=strs.from_file(ctx.file_reader,source,true,info.payload_size,info.payload_crc,format,error,nil);
        if error=0 then begin
                new_file(ctx,info.destination);
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
var info:TSaveRecord; error,row,width,scroll,visible:integer; source,number:string; key:byte; done,settled:boolean;
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
        done:=false;
        repeat
                scr.cls(ctx.config.color.text);
                scr.print(1,0,ctx.config.color.top,'Interrupted save'); row:=0;
                line('Recovery record:'); line(name);
                if error=0 then begin
                        line('Destination:'); line(info.destination);
                        line('Saved copy:'); line(source);
                        line('R opens a verified copy as an unsaved document.');
                        line('Files on disk will be preserved.');
                        scr.print(1,scr.getheight-2,ctx.config.color.top,'R Recover  S Skip  Esc Skip all');
                end else begin
                        str(error,number); line('Cannot recover this record. Error #'+number);
                        if source<>'' then begin line('Saved copy:'); line(source) end;
                        line('Its files have been left in place.');
                        scr.print(1,scr.getheight-2,ctx.config.color.top,'R Retry  S Skip  Esc Skip all');
                end;
                scr.print(1,scr.getheight-1,ctx.config.color.top,'Up/Down Scroll');
                scr.cursor_off; scr.show; key:=hi(kbd_getkey);
                case key of
                SCAN_ESC:begin stop:=true; done:=true end;
                SCAN_S,SCAN_ENTER:done:=true;
                SCAN_UP:if scroll>0 then dec(scroll);
                SCAN_DOWN:if scroll+visible<row then inc(scroll);
                SCAN_R:if error=0 then begin
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
