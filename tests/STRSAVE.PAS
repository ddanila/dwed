{ SPDX-License-Identifier: MIT }
program strsave;
uses cachehook,dos,strs,safesave,dwedtype;
const lines=1100;
var output:text; checks:longint; backend,kind,error,i,j:integer;
    old21,old60:pointer; collect:boolean; source_handles:array[1..2] of word;
    handles,hits,seen,selected,fault,trigger:word; saved_bytes:longint;
    root,last,added,empty,n,p:EditorStr; body:string; sf:TSaveFile; format:TTextFormat;
    actual:record before:array[0..31] of byte; body:string; after:array[0..31] of byte end;
    ok:boolean; raw:file; count:word; bytes:array[0..255] of byte;
procedure intercept(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var r:registers; service:byte; matching:boolean;
begin
        { Both qualification kernels lack LFN services. Preserve their explicit
          unsupported result instead of Pascal Intr changing the carry input. }
        if hi(ax)=$71 then begin ax:=$7100; flags:=flags or 1; exit end;
        service:=hi(ax); matching:=bx=source_handles[selected];
        if (service=$40) and (bx=sf.handle) and sf.opened then inc(saved_bytes,cx);
        if (fault=12) and (service=$3E) and sf.opened and (bx=sf.handle) then begin
                ax:=5; flags:=flags or 1; inc(hits); exit;
        end;
        if matching and (service=$3F) then inc(seen);
        if matching and (seen>=trigger) then begin
                if (fault in [1,12]) and (service=$3F) then begin ax:=5; flags:=flags or 1; inc(hits); exit end;
                if (fault=2) and (service=$3F) then begin ax:=0; flags:=flags and $FFFE; inc(hits); exit end;
        end;
        if matching and (fault=3) and (service=$42) then begin ax:=5; flags:=flags or 1; inc(hits); exit end;
        r.ax:=ax; r.bx:=bx; r.cx:=cx; r.dx:=dx; r.si:=si; r.di:=di;
        r.ds:=ds; r.es:=es; r.bp:=bp;
        if matching and (fault=4) and (service=$3F) and (r.cx>127) then begin r.cx:=127; inc(hits) end;
        intr($60,r);
        if collect and (service=$5B) and (r.flags and 1=0) then begin
                inc(handles); if handles<=2 then source_handles[handles]:=r.ax;
        end;
        if matching and (service=$3F) and (r.flags and 1=0) and (fault in [5..11]) then begin
                { The evicted root index/payload page is read at offset zero.
                  Corrupt only the returned bytes; the disk fixture stays intact. }
                if r.ax>64 then begin
                        case fault of
                        5:MemW[ds:dx+24]:=0;
                        6:MemW[ds:dx+24]:=257;
                        7:begin MemW[ds:dx+16]:=1; MemW[ds:dx+18]:=0 end;
                        8:begin MemW[ds:dx+20]:=99; MemW[ds:dx+22]:=0 end;
                        9:begin MemW[ds:dx+30]:=0; MemW[ds:dx+32]:=0 end;
                        10:Mem[ds:dx+46]:=0;
                        11:begin MemW[ds:dx+16]:=$FFFF; MemW[ds:dx+18]:=$7FFF end;
                        end;
                        inc(hits);
                end;
        end;
        ax:=r.ax; bx:=r.bx; cx:=r.cx; dx:=r.dx; si:=r.si; di:=r.di;
        ds:=r.ds; es:=r.es; bp:=r.bp; flags:=r.flags;
end;
procedure check(condition:boolean; message:string);
begin
        inc(checks);
        if not condition then begin
                SetIntVec($21,old21); SetIntVec($60,old60); restore_cache_hook;
                System.Writeln(output,'FAIL backend ',backend,' kind ',kind,' fault ',fault,
                        ' assertion ',checks,' error ',error,' ',message);
                System.Close(output); Halt(1);
        end;
end;
procedure fixture(name,text:string);
begin
        System.Assign(raw,name); System.Rewrite(raw,1);
        System.BlockWrite(raw,text[1],length(text),count); System.Close(raw);
        check(count=length(text),'destination fixture');
end;
procedure expect_file(name,text:string);
begin
        System.Assign(raw,name); System.Reset(raw,1);
        check(System.FileSize(raw)=length(text),'retained destination length');
        System.BlockRead(raw,bytes,sizeof(bytes),count); System.Close(raw);
        check(count=length(text),'retained destination read');
        for j:=1 to length(text) do check(bytes[j-1]=ord(text[j]),'retained destination bytes');
end;
procedure evict_root;
begin
        fault:=0;
{$IFDEF LEGACY_STORE}
        strs.get(last,body);
{$ELSE}
        check(strs.try_read(last,body,n,p,error),'evict root with last line');
{$ENDIF}
        check(length(body)=255,'last fixture line remains readable');
end;
procedure arm;
begin hits:=0; seen:=0; saved_bytes:=0; SetIntVec($21,@intercept) end;
procedure disarm;
begin SetIntVec($21,old21) end;
procedure sentinel;
begin FillChar(actual,sizeof(actual),$A5); actual.body:='SENTINEL'; n:=pointer(111); p:=pointer(222) end;
procedure intact;
begin
        check(actual.body='SENTINEL','failed read preserves destination');
        for j:=0 to 31 do begin
                check(actual.before[j]=$A5,'leading canary'); check(actual.after[j]=$A5,'trailing canary');
        end;
end;
procedure exact_file;
var line,column:integer;
begin
        System.Assign(raw,'C:\SAVE.TXT'); System.Reset(raw,1);
        check(System.FileSize(raw)=longint(lines)*257-2,'complete output length');
        for line:=1 to lines do begin
                System.BlockRead(raw,bytes,255,count); check(count=255,'whole physical line');
                for column:=0 to 254 do check(bytes[column]=byte((column+line) mod 256),'exact codepage and tab bytes');
                if line<lines then begin
                        System.BlockRead(raw,bytes,2,count);
                        check((count=2) and (bytes[0]=13) and (bytes[1]=10),'exact separator');
                end;
        end;
        System.Close(raw);
end;
begin
        System.Assign(output,'A:\STRSAVE.LOG'); System.Rewrite(output);
        GetIntVec($21,old21); GetIntVec($60,old60); SetIntVec($60,old21);
        format.newline:=#13#10; selected:=1; trigger:=1;
        for backend:=1 to 2 do begin
                System.Writeln(output,'backend ',backend,' fixtures'); System.Flush(output);
                FillChar(sf,sizeof(sf),0); fault:=0; collect:=true; handles:=0;
                deny_cache_allocation(true); SetIntVec($21,@intercept);
                if backend=1 then strs.init(MT_SWAP) else strs.init(MT_SXMS);
                SetIntVec($21,old21); deny_cache_allocation(false); collect:=false;
                check(handles=2,'capture backing handles'); root:=nil; last:=nil;
                for i:=1 to lines do begin
                        body[0]:=chr(255);
                        for j:=1 to 255 do body[j]:=chr((j-1+i) mod 256);
                        added:=strs.create(nil,last,body); check(added<>nil,'create line');
                        if root=nil then root:=added; last:=added;
                end;
{$IFNDEF LEGACY_STORE}
                empty:=strs.new; check(empty<>nil,'create empty independent line');
                sentinel; check(strs.try_read(empty,actual.body,n,p,error),'read empty line');
                check((actual.body='') and (n=nil) and (p=nil) and (error=0),'empty line metadata');
                sentinel; check(strs.try_read(nil,actual.body,n,p,error),'read null line');
                check((actual.body='') and (n=nil) and (p=nil) and (error=0),'null line result');
{$ENDIF}
                for kind:=1 to 10 do begin
                        evict_root; sentinel; selected:=2; fault:=kind; trigger:=1;
                        if kind in [1..4,10] then selected:=1;
                        arm;
{$IFDEF LEGACY_STORE}
                        strs.get(root,actual.body); ok:=true;
{$ELSE}
                        ok:=strs.try_read(root,actual.body,n,p,error);
{$ENDIF}
                        disarm; check(hits>0,'read injection exercised');
                        if kind in [4,7,8] then begin
                                { A single read accepts in-range links. Traversal validates reciprocity. }
                                check(ok and (length(actual.body)=255),'valid single-line read');
                        end else begin
                                {$IFNDEF LEGACY_STORE}
                                check(not ok,'checked line read rejects failure');
                                if kind in [1..3] then check(error=100,'line read I/O status')
                                else check(error=1019,'invalid line status');
{$ENDIF}
                                intact;
                                check((n=pointer(111)) and (p=pointer(222)),'failed read preserves links');
                        end;
                end;
                for kind:=1 to 12 do begin
                        System.Writeln(output,'backend ',backend,' save case ',kind); System.Flush(output);
                        evict_root; fixture('C:\SAVE.TXT','ORIGINAL'); fixture('C:\SAVE.BAK','OLDER');
                        selected:=2; fault:=kind; trigger:=1;
                        if kind in [1..4,10,12] then selected:=1;
                        if kind in [1,2,12] then trigger:=2;
                        arm; strs.to_file(sf,'C:\SAVE.TXT',root,format,error,nil); disarm;
                        check(hits>0,'save injection exercised');
                        if kind=4 then begin
                                check(error=0,'short backing reads save successfully'); exact_file;
                                expect_file('C:\SAVE.BAK','ORIGINAL');
                        end else begin
                                check(error<>0,'backing failure aborts save');
                                if kind in [1,2,3,12] then check(error=100,'save preserves primary read error')
                                else check(error=1019,'save reports invalid backing data');
                                expect_file('C:\SAVE.TXT','ORIGINAL'); expect_file('C:\SAVE.BAK','OLDER');
                                if kind in [1,2,12] then check(saved_bytes>0,'failure after output was staged');
                                if kind=12 then begin
                                        check(sf.opened and save_pending_files(sf),'failed cleanup retains handle');
                                        check((sf.cleanup_error=5) and not sf.published,'cleanup status and unpublished destination');
                                        strs.to_file(sf,'C:\OTHER.TXT',root,format,error,nil);
                                        check(error=SAVE_PENDING,'pending owner blocks new save');
                                        retry_save_cleanup(sf);
                                end;
                                check(not save_pending_files(sf),'failed save cleanup settled');
                        end;
                end;
                evict_root; strs.to_file(sf,'C:\SAVE.TXT',root,format,error,nil);
                check(error=0,'native retry after faults'); exact_file;
                strs.done;
        end;
        SetIntVec($60,old60); restore_cache_hook;
        System.Writeln(output,'PASS ',checks,' assertions'); System.Close(output);
        System.Assign(output,'A:\STRSAVE.OK'); System.Rewrite(output);
        System.Writeln(output,'STORE SAVE PASS'); System.Close(output);
end.
