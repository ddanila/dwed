{ SPDX-License-Identifier: MIT }
program stortest;
uses unredo,strsdos;
var output:text; tests:longint;
    h:TUndoHistory; position:TUndoPosition;
    root,node:pointer;
    lines:array[1..16] of string; count:integer;
    pointers:array[1..16] of pointer;
    hashes:array[0..600] of longint;
    before_heap,before_hash,seed:longint;
    i,j,n,steps,operation,err:integer;
    a,b,large:string;

procedure check(ok:boolean; message:string);
begin
        inc(tests);
        if not ok then begin
                writeln(output,'FAIL ',tests,' ',message);
                close(output); halt(1);
        end;
end;

procedure compare_store;
var p,previous:pointer; s:string; k:integer;
begin
        p:=root; previous:=nil;
        for k:=1 to count do begin
                check(p<>nil,'stored line exists');
                strsdos.get(p,s);
                check(s=lines[k],'stored bytes match model');
                check(strsdos.go_prev(p)=previous,'backward link');
                check(strsdos.get_num(p)=k,'cached line number');
                previous:=p; p:=strsdos.go_next(p);
        end;
        check(p=nil,'stored count matches model');
end;

procedure remember;
var k:integer; p:pointer;
begin
        p:=root;
        for k:=1 to count do begin pointers[k]:=p; p:=strsdos.go_next(p) end;
        before_heap:=MemAvail;
end;

procedure unchanged;
var k:integer; p:pointer;
begin
        compare_store; p:=root;
        for k:=1 to count do begin
                check(p=pointers[k],'failure preserves original nodes');
                p:=strsdos.go_next(p);
        end;
        check(MemAvail=before_heap,'replay failure has no heap leak');
end;

procedure model_apply(change:PUndoChange; forward:boolean);
var old,newtext,temp:string; kind:TUndoKind; k,n:integer;
begin
        undo_text(change,old,newtext); kind:=change^.kind;
        if not forward then begin
                temp:=old; old:=newtext; newtext:=temp;
                case kind of
                UNDO_INSERT:kind:=UNDO_DELETE;
                UNDO_DELETE:kind:=UNDO_INSERT;
                end;
        end;
        n:=change^.line;
        if kind=UNDO_INSERT then begin
                check((n>=1) and (n<=count+1) and (count<16),'model insert range');
                for k:=count downto n do lines[k+1]:=lines[k];
                inc(count); lines[n]:=newtext;
        end else begin
                check((n>=1) and (n<=count),'model existing range');
                check(lines[n]=old,'model preimage');
                if kind=UNDO_DELETE then begin
                        for k:=n to count-1 do lines[k]:=lines[k+1];
                        dec(count);
                end else lines[n]:=newtext;
        end;
end;

function fingerprint:longint;
var k,j:integer; value:longint;
begin
        value:=count;
        for k:=1 to count do begin
                value:=(value*31+length(lines[k])) mod 10000019;
                for j:=1 to length(lines[k]) do
                        value:=(value*31+ord(lines[k][j])) mod 10000019;
        end;
        fingerprint:=value;
end;

procedure record_change(kind:TUndoKind; n:integer; old,newtext:string);
begin
        check(undo_record(h,kind,n,old,newtext),'record');
        model_apply(h.pending^.last,true);
end;

procedure begin_edit;
begin
        check(undo_begin(h,position),'begin');
end;

procedure finish_edit;
begin
        check(strsdos.replay_group(root,h.pending,true,h.reserve,err),'apply pending group');
        check(err=0,'success code'); compare_store;
        check(undo_finish(h,position),'finish');
end;

procedure replay(forward:boolean);
var g:PUndoGroup; c:PUndoChange;
begin
        if forward then g:=undo_next(h) else g:=undo_previous(h);
        check(g<>nil,'history available');
        check(strsdos.replay_group(root,g,forward,h.reserve,err),'atomic replay');
        check(err=0,'replay success code');
        if forward then c:=g^.first else c:=g^.last;
        while c<>nil do begin
                model_apply(c,forward);
                if forward then c:=c^.next else c:=c^.previous;
        end;
        compare_store;
        check(undo_accept(h,g,forward),'acknowledge');
end;

begin
        assign(output,'A:\STORE.LOG'); rewrite(output); tests:=0;
        root:=nil; count:=0; FillChar(position,sizeof(position),0);
        undo_init(h,UNDO_DEFAULT_LIMIT,UNDO_DEFAULT_RESERVE);
        { Build from an empty chain and include empty and non-ASCII lines. }
        begin_edit;
        record_change(UNDO_INSERT,1,'','first');
        record_change(UNDO_INSERT,2,'','');
        record_change(UNDO_INSERT,3,'',#9#128#255);
        finish_edit;
        replay(false); check(root=nil,'undo entire insertion to empty');
        replay(true); check(count=3,'redo from empty');
        undo_saved(h); before_hash:=fingerprint;
        begin_edit;
        record_change(UNDO_REPLACE,1,'first','changed');
        record_change(UNDO_INSERT,2,'','middle');
        record_change(UNDO_DELETE,3,'','');
        record_change(UNDO_REPLACE,2,'middle','twice');
        record_change(UNDO_DELETE,2,'twice','');
        finish_edit; replay(false);
        check(fingerprint=before_hash,'mixed group undo');
        check(not undo_dirty(h),'saved checkpoint reached');
        replay(true); replay(false);

        { A malformed preimage after mutations forces rollback, including a
          node prepared by an earlier step then removed by a later step. }
        begin_edit;
        check(undo_record(h,UNDO_REPLACE,1,'first','partial'),'failure record 1');
        check(undo_record(h,UNDO_INSERT,2,'','prepared'),'failure record 2');
        check(undo_record(h,UNDO_DELETE,2,'prepared',''),'failure record 3');
        check(undo_record(h,UNDO_DELETE,2,'',''),'failure record 4');
        check(undo_record(h,UNDO_REPLACE,2,'wrong','bad'),'failure record 5');
        remember;
        check(not strsdos.replay_group(root,h.pending,true,h.reserve,err),'bad preimage rejected');
        check(err=REPLAY_INVALID,'bad preimage code'); unchanged;
        check(h.state=h.saved_state,'failure keeps history cursor');
        undo_cancel(h); check(undo_next(h)<>nil,'failure retains redo');

        { Reverse replay can also encounter a diverged preimage after it has
          detached the head and inserted a prepared line. }
        begin_edit;
        check(undo_record(h,UNDO_REPLACE,3,'before','wrong'),'reverse failure record 1');
        check(undo_record(h,UNDO_DELETE,2,'restore',''),'reverse failure record 2');
        check(undo_record(h,UNDO_INSERT,1,'','first'),'reverse failure record 3');
        remember;
        check(not strsdos.replay_group(root,h.pending,false,h.reserve,err),'reverse bad preimage rejected');
        check(err=REPLAY_INVALID,'reverse bad preimage code'); unchanged;
        undo_cancel(h);

        { Invalid ordinal after a valid deletion must restore the old head. }
        begin_edit;
        check(undo_record(h,UNDO_DELETE,1,'first',''),'head delete record');
        check(undo_record(h,UNDO_INSERT,90,'','bad'),'bad ordinal record');
        remember;
        check(not strsdos.replay_group(root,h.pending,true,h.reserve,err),'bad ordinal rejected');
        check(err=REPLAY_INVALID,'bad ordinal code'); unchanged; undo_cancel(h);

        { Low working memory rejects before publication, including failure
          partway through preparation of several maximum-length lines. }
        large:=''; for i:=1 to 255 do large:=large+chr(i-1);
        begin_edit; a:='first';
        for i:=1 to 8 do begin
                b:=large; b[1]:=chr(i);
                check(undo_record(h,UNDO_REPLACE,1,a,b),'large record'); a:=b;
        end;
        remember;
        check(not strsdos.replay_group(root,h.pending,true,MemAvail,err),'first allocation rejected');
        check(err=REPLAY_NO_MEMORY,'first allocation code'); unchanged;
        check(not strsdos.replay_group(root,h.pending,true,MemAvail-512,err),'later allocation rejected');
        check(err=REPLAY_NO_MEMORY,'later allocation code'); unchanged;
        undo_cancel(h);

        { Exercise maximum opaque payloads in both directions. }
        begin_edit; record_change(UNDO_REPLACE,1,'first',large); finish_edit;
        replay(false); replay(true); compare_store;
        strsdos.free(root); root:=nil; count:=0; undo_done(h);

        { Mixed stress uses a separate text model for every resulting byte,
          and fingerprints for states revisited after eviction/branching. }
        undo_init(h,2048,UNDO_DEFAULT_RESERVE);
        before_heap:=MemAvail; hashes[0]:=fingerprint; seed:=29;
        for i:=1 to 600 do begin
                before_hash:=fingerprint; begin_edit;
                seed:=(seed*97+11) mod 32749; steps:=seed mod 4+1;
                for j:=1 to steps do begin
                        seed:=(seed*97+11) mod 32749; operation:=seed mod 3;
                        if count=0 then operation:=1;
                        if count=16 then operation:=2;
                        seed:=(seed*97+11) mod 32749;
                        if operation=1 then begin
                                n:=seed mod (count+1)+1;
                                if seed mod 5=0 then b:='' else begin
                                        str(seed,b); b:=#9+b+#255;
                                end;
                                record_change(UNDO_INSERT,n,'',b);
                        end else begin
                                n:=seed mod count+1;
                                if operation=2 then record_change(UNDO_DELETE,n,lines[n],'')
                                else begin
                                        str(seed,b); b:=b+#128;
                                        if b=lines[n] then b:='different';
                                        record_change(UNDO_REPLACE,n,lines[n],b);
                                end;
                        end;
                end;
                finish_edit; hashes[h.state]:=fingerprint;
                replay(false); check(fingerprint=before_hash,'stress undo exact');
                replay(true); check(fingerprint=hashes[h.state],'stress redo exact');
                if i mod 7=0 then undo_saved(h);
                if i mod 11=0 then replay(false);
        end;
        while undo_previous(h)<>nil do begin
                replay(false); check(fingerprint=hashes[h.state],'retained undo state');
        end;
        while undo_next(h)<>nil do begin
                replay(true); check(fingerprint=hashes[h.state],'retained redo state');
        end;
        strsdos.free(root); undo_done(h);
        check(MemAvail=before_heap,'stress replay has no heap leak');
        writeln(output,'PASS ',tests,' assertions'); close(output);
        assign(output,'A:\STORE.OK'); rewrite(output);
        writeln(output,'ATOMIC STORAGE PASS'); close(output);
end.
