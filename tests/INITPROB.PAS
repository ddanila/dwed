{ SPDX-License-Identifier: MIT }
program initprob;
uses dos,dosread,doslines,dwedtype,dwedinit,dwedutil,strs,unredo;
var ctx:TEditorContext; output:text; checks:longint; kind,error,i:integer;
    old21,old60:pointer; armed,document_target:boolean; fault,hits,handle,reads:word;
    saved:PFileContext; lines:PInputLine; observed,checkpoint_text:string;
    checkpoint_padding:boolean; baseline:longint;
const config_name='A:\INIT.CFG'; session_name='A:\RESUME.TMP';
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers; service:byte; target,reject:boolean;
begin
        service:=hi(ax); reject:=false;
        target:=(service=$3D) and ((mem[ds:dx+3] in [ord('I'),ord('R')]) or
                ((fault in [10,11]) and (mem[ds:dx+3]=ord('T'))));
        if armed then begin
                if target and (fault=7) then reject:=true;
                if bx=handle then begin
                        if service=$3F then begin
                                inc(reads);
                                if (fault=1) or ((fault=2) and (reads=2)) or
                                   ((fault=10) and document_target) then reject:=true;
                                if fault=4 then begin ax:=0; flags:=flags and $FFFE; inc(hits); exit end;
                        end;
                        if ((fault=6) or ((fault=11) and document_target)) and (service=$3E) then reject:=true;
                        if (fault=8) and (service=$42) then reject:=true;
                end;
                if (fault=9) and (service=$41) then reject:=true;
        end;
        if reject then begin ax:=5; flags:=flags or 1; inc(hits); exit end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        if armed and (fault=3) and (service=$3F) and (bx=handle) and (reads=1) then begin
                r.cx:=r.cx div 2; inc(hits);
        end;
        intr($60,r);
        if armed and target and (r.flags and 1=0) then begin
                handle:=r.ax; document_target:=mem[ds:dx+3]=ord('T');
        end;
        if armed and (fault=5) and (ax=$4202) and (bx=handle) and (r.flags and 1=0) then begin
                dec(r.ax); inc(hits);
        end;
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp;
        flags:=(flags and $0300) or (r.flags and $FCFF);
end;
procedure check(ok:boolean; message:string);
begin
        inc(checks);
        if not ok then begin
                armed:=false; SetIntVec($21,old21); SetIntVec($60,old60);
                writeln(output,'FAIL kind ',kind,' fault ',fault,' assertion ',checks,' ',message);
                close(output); halt(1);
        end;
end;
procedure fixture(name,body:string; padding:boolean);
var f:file; written:word; i:integer; blank:string;
begin
        if name=session_name then begin checkpoint_text:=body; checkpoint_padding:=padding end;
        System.Assign(f,name); System.Rewrite(f,1);
        System.BlockWrite(f,body[1],length(body),written);
        check(written=length(body),'fixture write');
        blank:=#13#10;
        if padding then for i:=1 to 300 do System.BlockWrite(f,blank[1],2,written);
        System.Close(f);
end;
procedure present(name:string);
var f:file; attr,got:word; actual:string; i:integer; expected_size:longint;
begin
        System.Assign(f,name); GetFAttr(f,attr); check(DosError=0,'failed resume checkpoint retained');
        System.Reset(f,1); expected_size:=length(checkpoint_text);
        if checkpoint_padding then inc(expected_size,600);
        check(System.FileSize(f)=expected_size,'checkpoint length retained');
        System.BlockRead(f,actual[1],length(checkpoint_text),got); actual[0]:=chr(got);
        check(actual=checkpoint_text,'checkpoint record bytes retained');
        if checkpoint_padding then for i:=1 to 300 do begin
                System.BlockRead(f,actual[1],2,got); actual[0]:=chr(got);
                check(actual=#13#10,'checkpoint padding retained');
        end;
        System.Close(f);
end;
procedure append_file(name,body:string);
var f:file; written:word;
begin
        System.Assign(f,name); System.Reset(f,1); System.Seek(f,System.FileSize(f));
        System.BlockWrite(f,body[1],length(body),written); System.Close(f);
        check(written=length(body),'fixture append');
end;
procedure retained;
begin
        check(ctx.all=saved,'document list unchanged'); check(ctx.current=saved,'active unchanged');
        check(saved^.editor.x=2,'cursor unchanged');
        strs.get(saved^.rline,observed); check(observed='ORIGINAL','document bytes unchanged');
end;
procedure clear_restored;
var p:PFileContext;
begin
        while ctx.all<>saved do begin
                p:=ctx.all; ctx.all:=p^.next;
                strs.free(p^.rline); undo_done(p^.history); FreeMem(p,sizeof(TFileContext));
        end;
        ctx.current:=saved;
end;
procedure invalid_session(body:string);
begin
        fixture(session_name,body,false);
        check(restore_session(ctx)=METADATA_INVALID,'invalid resume fields refused');
        retained; present(session_name);
end;
procedure arm;
begin handle:=$FFFF; hits:=0; reads:=0; document_target:=false; armed:=true end;
begin
        System.Assign(output,'A:\INIT.LOG'); System.Rewrite(output);
        GetIntVec($21,old21); GetIntVec($60,old60); SetIntVec($60,old21); SetIntVec($21,@intercept);
        FillChar(ctx,sizeof(ctx),0); ctx.config.width:=80; ctx.config.height:=24; ctx.config.tab_size:=8;
        ctx.temp:=session_name; strs.init(MT_DOS);
        error:=new_file(ctx,''); check(error=0,'initial document'); saved:=ctx.current;
        observed:='ORIGINAL'; saved^.cline:=strs.put(saved^.cline,observed);
        saved^.rline:=saved^.cline; saved^.scrline:=saved^.cline; load_ed(ctx); saved^.editor.x:=2;
        kind:=1;
        for fault:=1 to 8 do begin
                fixture(config_name,'tab_size=4'#13#10,true); ctx.config.tab_size:=8;
                arm; error:=load_config(ctx,config_name); armed:=false;
                check(hits>0,'configuration fault reached DOS');
                if fault=3 then begin
                        check(error=0,'short reads are consumed'); check(ctx.config.tab_size=4,'complete configuration applied');
                end else begin
                        check(error<>0,'configuration failure detected'); check(ctx.config.tab_size=8,'configuration not partially applied');
                end;
                if fault=6 then begin
                        check(ctx.file_reader.opened,'close failure retains read owner');
                        check(load_config(ctx,config_name)=READ_PENDING,'pending owner cannot be reset');
                        close_read(ctx.file_reader); check(not ctx.file_reader.opened,'close retry');
                end;
                retained;
        end;
        fault:=0;
        observed:=''; for i:=1 to 255 do observed:=observed+'x';
        fixture(config_name,observed,false);
        error:=read_lines(ctx.file_reader,config_name,lines,0);
        check((error=0) and (lines<>nil),'maximum physical line accepted'); free_lines(lines);
        fixture(config_name,'tab_size=4'#13#10+'bad'+#0+'record',false);
        ctx.config.tab_size:=8;
        check(load_config(ctx,config_name)=METADATA_INVALID,'control byte rejected');
        check(ctx.config.tab_size=8,'malformed configuration leaves settings');
        fixture(config_name,observed,false); append_file(config_name,'x');
        check(read_lines(ctx.file_reader,config_name,lines,0)=METADATA_INVALID,'overlong physical line refused');
        check(lines=nil,'overlong line releases staged records');
        fixture(config_name,'tab_size=4',true); baseline:=MemAvail;
        check(read_lines(ctx.file_reader,config_name,lines,baseline-sizeof(TInputLine)*2)=8,
              'staging allocation failure detected after earlier records');
        check((lines=nil) and not ctx.file_reader.opened,'allocation failure releases records and handle');
        check(MemAvail=baseline,'staging allocation failure leaks no heap');
        fixture(config_name,copy(observed,1,254),false); append_file(config_name,#13#10);
        append_file(config_name,observed); append_file(config_name,#13#10);
        check(read_lines(ctx.file_reader,config_name,lines,0)=0,'CRLF across read boundary');
        check((length(lines^.value)=254) and (length(lines^.next^.value)=255) and
              (lines^.next^.next=nil),'CRLF split yields exactly two records'); free_lines(lines);
        fixture(config_name,'tab_size=4'#13#10,false);
        check(load_config(ctx,config_name)=0,'configuration retry succeeds');
        fixture('A:\ONE.TXT','ONE'#13#10,false); fixture('A:\TWO.TXT','TWO'#13#10,false);
        kind:=2;
        for fault:=1 to 11 do begin
                if fault=2 then begin
                        { Multiple valid records cross a read-buffer boundary. }
                        fixture(session_name,'2,0,0,1,A:\ONE.TXT'#13#10,true);
                end else fixture(session_name,'2,0,0,1,A:\ONE.TXT'#13#10+'1,0,0,1,A:\TWO.TXT'#13#10,false);
                arm; error:=restore_session(ctx); armed:=false;
                check(hits>0,'resume fault reached DOS');
                if fault=3 then begin
                        check(error=0,'short resume read succeeds');
                        check(ctx.all^.fname='A:\TWO.TXT','document order restored');
                        check(ctx.all^.next^.fname='A:\ONE.TXT','earlier document restored');
                        check(ctx.all^.next^.editor.x=2,'cursor restored'); clear_restored;
                end else begin
                        check(error<>0,'resume failure detected'); present(session_name);
                        if fault in [10,11] then
                                check(ctx.all^.fname='A:\ONE.TXT','earlier restored document remains available');
                        if fault in [9,10,11] then clear_restored;
                        retained;
                end;
                if fault in [6,11] then begin
                        check(ctx.file_reader.opened,'resume close owner retained');
                        close_read(ctx.file_reader); check(not ctx.file_reader.opened,'resume close retry');
                end;
        end;
        fault:=0;
        invalid_session(''); invalid_session('bad');
        invalid_session('0,0,0,1,A:\ONE.TXT');
        invalid_session('257,0,0,1,A:\ONE.TXT');
        invalid_session('1,-1,0,1,A:\ONE.TXT');
        invalid_session('1,0,32768,1,A:\ONE.TXT');
        invalid_session('1,0,0,0,A:\ONE.TXT');
        invalid_session('1,0,0,2147483648,A:\ONE.TXT');
        invalid_session('1,0,0,1');
        fixture(session_name,'1,0,0,1,A:\ONE.TXT'#13#10+'bad',false);
        check(restore_session(ctx)=METADATA_INVALID,'all resume records validated first'); retained; present(session_name);
        fixture(session_name,'1,0,0,1,A:\MISSING.TXT'#13#10,false);
        check(restore_session(ctx)=2,'missing resume file is not a new document'); retained; present(session_name);
        fixture(session_name,'2,0,0,999,A:\ONE.TXT'#13#10,false);
        check(restore_session(ctx)=0,'resume retry succeeds');
        check(strs.get_num(ctx.current^.cline)=ctx.current^.total,'changed document row clamped'); clear_restored;
        strs.free(saved^.rline); undo_done(saved^.history); FreeMem(saved,sizeof(TFileContext));
        SetIntVec($21,old21); SetIntVec($60,old60);
        writeln(output,'PASS ',checks,' assertions'); close(output);
        System.Assign(output,'A:\INIT.OK'); System.Rewrite(output); writeln(output,'METADATA PASS'); close(output);
end.
