{ SPDX-License-Identifier: MIT }
program undotest;
uses unredo;
var output:text; tests:longint;
    h,other:TUndoHistory; position:TUndoPosition;
    lines:array[1..8] of string; count:integer;
    hashes:array[0..1000] of longint;
    remembered:PUndoGroup;
    a,b,full:string; i,j:integer; baseline,before_hash,seed:longint;
    operation,n,steps:integer;

procedure check(ok:boolean; message:string);
begin
        inc(tests);
        if not ok then begin
                writeln(output,'FAIL ',tests,' ',message);
                close(output); halt(1);
        end;
end;

function fingerprint:longint;
var i,j:integer; n:longint;
begin
        n:=count;
        for i:=1 to count do begin
                n:=(n*31+length(lines[i])) mod 10000019;
                for j:=1 to length(lines[i]) do
                        n:=(n*31+ord(lines[i][j])) mod 10000019;
        end;
        fingerprint:=n;
end;

procedure apply(change:PUndoChange; forward:boolean);
var old,newtext,temp:string; kind:TUndoKind; n,k:integer;
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
                check((n>=1) and (n<=count+1) and (count<8),'insert range');
                for k:=count downto n do lines[k+1]:=lines[k];
                inc(count); lines[n]:=newtext;
        end else begin
                check((n>=1) and (n<=count),'existing range');
                check(lines[n]=old,'replay preimage');
                if kind=UNDO_DELETE then begin
                        for k:=n to count-1 do lines[k]:=lines[k+1];
                        dec(count);
                end else lines[n]:=newtext;
        end;
end;

procedure change(kind:TUndoKind; n:integer; old,newtext:string);
begin
        check(undo_record(h,kind,n,old,newtext),'record');
        apply(h.pending^.last,true);
end;

procedure begin_edit;
begin
        check(undo_begin(h,position),'begin');
end;

procedure finish_edit;
begin
        check(undo_finish(h,position),'finish');
end;

procedure replay(forward:boolean);
var group:PUndoGroup; p:PUndoChange;
begin
        if forward then group:=undo_next(h) else group:=undo_previous(h);
        check(group<>nil,'history available');
        if forward then p:=group^.first else p:=group^.last;
        while p<>nil do begin
                apply(p,forward);
                if forward then p:=p^.next else p:=p^.previous;
        end;
        check(undo_accept(h,group,forward),'acknowledge');
        if forward then position:=group^.after_position
        else position:=group^.before_position;
end;

procedure rollback;
var p:PUndoChange;
begin
        p:=h.pending^.last;
        while p<>nil do begin apply(p,false); p:=p^.previous end;
        undo_cancel(h);
end;

procedure invariants;
var p,previous:PUndoGroup; c,last:PUndoChange; bytes,total:longint;
begin
        p:=h.first; previous:=nil; total:=0;
        while p<>nil do begin
                check(p^.previous=previous,'group links');
                bytes:=sizeof(TUndoGroup); c:=p^.first; last:=nil;
                while c<>nil do begin
                        check(c^.previous=last,'change links');
                        inc(bytes,c^.size); last:=c; c:=c^.next;
                end;
                check(last=p^.last,'change tail');
                check(bytes=p^.bytes,'group accounting');
                inc(total,bytes); previous:=p; p:=p^.next;
        end;
        check(previous=h.last,'history tail');
        check(total=h.bytes,'history accounting');
        check(h.bytes<=h.limit,'bounded committed memory');
end;

begin
        assign(output,'A:\UNDO.LOG'); rewrite(output); tests:=0;
        FillChar(position,sizeof(position),0); position.line:=1; position.column:=1;
        { Warm the heap before measuring leak-free disposal. }
        undo_init(h,UNDO_DEFAULT_LIMIT,UNDO_DEFAULT_RESERVE);
        begin_edit; undo_cancel(h); undo_done(h); baseline:=MemAvail;
        count:=2; lines[1]:='original'; lines[2]:='tail'; hashes[0]:=fingerprint;
        begin_edit;
        change(UNDO_REPLACE,1,'original','changed');
        change(UNDO_INSERT,2,'','');
        change(UNDO_INSERT,2,'',#9#128#255);
        change(UNDO_DELETE,4,'tail','');
        position.line:=3; position.column:=7; position.selection:=true;
        position.anchor_line:=2; position.anchor_column:=1;
        position.top:=2; position.left:=4;
        finish_edit; hashes[1]:=fingerprint;
        check(undo_dirty(h),'edit dirty'); undo_saved(h);
        check(not undo_dirty(h),'saved clean'); invariants;
        replay(false); check(fingerprint=hashes[0],'group undo exact');
        check((position.line=1) and (position.column=1) and
              not position.selection,'before cursor and selection');
        check(undo_dirty(h),'undo past save dirty');
        replay(true); check(fingerprint=hashes[1],'group redo exact');
        check((position.line=3) and (position.column=7) and position.selection and
              (position.anchor_line=2) and (position.anchor_column=1) and
              (position.top=2) and (position.left=4),'after cursor and selection');
        check(not undo_dirty(h),'redo to save clean');
        begin_edit; change(UNDO_REPLACE,1,'changed','later'); finish_edit;
        replay(false); check(not undo_dirty(h),'undo to save clean');
        remembered:=undo_next(h);
        begin_edit;
        check(not undo_begin(h,position),'nested group refused');
        check(undo_previous(h)=nil,'undo hidden during pending edit');
        check(undo_next(h)=nil,'redo hidden during pending edit');
        check(undo_record(h,UNDO_REPLACE,1,'changed','changed'),'no-op accepted');
        finish_edit;
        check(undo_next(h)=remembered,'no-op preserves redo');
        begin_edit; change(UNDO_REPLACE,1,'changed','cancelled');
        undo_saved(h); rollback;
        check((fingerprint=hashes[1]) and not undo_dirty(h),'rollback keeps save');
        check(undo_next(h)=remembered,'cancel preserves redo');
        before_hash:=fingerprint;
        begin_edit; change(UNDO_REPLACE,1,'changed','partial');
        { Force a mid-group capacity failure after a real applied change. }
        h.limit:=h.pending^.bytes;
        check(not undo_record(h,UNDO_INSERT,2,'','cannot fit'),'capacity rejection');
        check(not undo_finish(h,position),'failed group cannot commit');
        check(h.pending<>nil,'failed group retained for rollback');
        rollback; h.limit:=UNDO_DEFAULT_LIMIT;
        check(fingerprint=before_hash,'allocation failure rollback exact');
        check(undo_next(h)=remembered,'failure preserves redo');
        check(not undo_dirty(h),'failure preserves saved state');
        check(not undo_accept(h,remembered,false),'wrong direction rejected');
        begin_edit; change(UNDO_REPLACE,1,'changed','fork'); finish_edit;
        check(undo_next(h)=nil,'new edit invalidates redo');
        check(undo_dirty(h),'branch state distinct');
        replay(false); check(not undo_dirty(h),'branch undo returns to save');
        undo_saved(h);
        check(not undo_dirty(h),'saving after undo checkpoints current state');
        replay(true); check(undo_dirty(h),'redo away from new checkpoint dirty');
        replay(false); check(not undo_dirty(h),'undo to new checkpoint clean');
        undo_done(h);
        check(MemAvail=baseline,'group disposal has no heap leak');

        { Maximum byte strings, embedded NUL and codepage bytes are opaque. }
        full:=''; for i:=1 to 255 do full:=full+chr(i-1);
        undo_init(h,2048,UNDO_DEFAULT_RESERVE); begin_edit;
        check(undo_record(h,UNDO_REPLACE,70000,full,full+#255),'255-byte no-op');
        check(h.pending^.first=nil,'Pascal truncation creates no-op');
        b:=full; b[255]:=#255;
        check(undo_record(h,UNDO_REPLACE,70000,full,b),'maximum strings');
        undo_text(h.pending^.first,a,full);
        check((length(a)=255) and (a[1]=#0) and (a[255]=#254) and
              (full=b) and (h.pending^.first^.line=70000),'opaque payload and long line index');
        undo_cancel(h);
        h.reserve:=MemAvail;
        check(not undo_begin(h,position),'heap reserve prevents allocation');
        check((h.pending=nil) and (h.bytes=0),'begin failure unchanged');
        h.reserve:=UNDO_DEFAULT_RESERVE; begin_edit;
        h.reserve:=MemAvail;
        check(not undo_record(h,UNDO_INSERT,1,'','x'),'mid-group heap reserve');
        check(h.failed,'heap failure latched'); undo_cancel(h);
        undo_done(h);
        check(MemAvail=baseline,'payload disposal has no heap leak');

        { Eviction stress: independent expected states, full undo and redo of
          all surviving groups, and invariants after every operation. }
        undo_init(h,512,UNDO_DEFAULT_RESERVE);
        undo_init(other,512,UNDO_DEFAULT_RESERVE);
        count:=1; lines[1]:='0'; hashes[0]:=fingerprint;
        for i:=1 to 1000 do begin
                begin_edit; str(i,b); change(UNDO_REPLACE,1,lines[1],b);
                finish_edit; hashes[i]:=fingerprint; invariants;
                if i=998 then undo_saved(h);
        end;
        check((h.first<>nil) and (h.first^.before_state>0),'old groups evicted');
        check(undo_begin(other,position),'independent document begin');
        check(undo_record(other,UNDO_INSERT,1,'','other'),'independent document record');
        check(undo_finish(other,position),'independent document finish');
        undo_saved(other);
        j:=0;
        while undo_previous(h)<>nil do begin
                replay(false); inc(j);
                check(fingerprint=hashes[h.state],'eviction undo state');
                check(undo_dirty(h)=(h.state<>998),'save checkpoint under eviction');
                invariants;
        end;
        check(j>0,'surviving undo history');
        check(not undo_dirty(other),'other document checkpoint intact');
        while undo_next(h)<>nil do begin
                replay(true);
                check(fingerprint=hashes[h.state],'eviction redo state'); invariants;
        end;
        check(h.state=1000,'all surviving changes redone');
        undo_done(h); undo_done(other);
        check(MemAvail=baseline,'stress disposal has no heap leak');
        { Mixed multi-line commands with an independent document model.
          Line numbers are relative to each individual mutation, so reverse
          replay must visit changes in the opposite order. }
        undo_init(h,2048,UNDO_DEFAULT_RESERVE);
        count:=1; lines[1]:='seed'; hashes[0]:=fingerprint; seed:=19;
        for i:=1 to 600 do begin
                before_hash:=fingerprint; begin_edit;
                seed:=(seed*97+11) mod 32749; steps:=seed mod 4+1;
                for j:=1 to steps do begin
                        seed:=(seed*97+11) mod 32749; operation:=seed mod 3;
                        if count=1 then operation:=1;
                        if count=8 then operation:=2;
                        seed:=(seed*97+11) mod 32749;
                        if operation=1 then begin
                                n:=seed mod (count+1)+1;
                                if seed mod 5=0 then b:='' else begin
                                        str(seed,b); b:=#9+b+#255;
                                end;
                                change(UNDO_INSERT,n,'',b);
                        end else begin
                                n:=seed mod count+1;
                                if operation=2 then change(UNDO_DELETE,n,lines[n],'')
                                else begin
                                        str(seed,b); b:=b+#128;
                                        if b=lines[n] then b:='different';
                                        change(UNDO_REPLACE,n,lines[n],b);
                                end;
                        end;
                end;
                finish_edit; hashes[h.state]:=fingerprint; invariants;
                replay(false); check(fingerprint=before_hash,'mixed undo exact');
                replay(true); check(fingerprint=hashes[h.state],'mixed redo exact');
                if i mod 7=0 then undo_saved(h);
                if i mod 11=0 then begin
                        replay(false);
                        check(fingerprint=before_hash,'branch preimage');
                        { The next iteration branches from here. }
                end;
        end;
        while undo_previous(h)<>nil do begin
                replay(false);
                check(fingerprint=hashes[h.state],'mixed retained undo exact');
        end;
        while undo_next(h)<>nil do begin
                replay(true);
                check(fingerprint=hashes[h.state],'mixed retained redo exact');
        end;
        undo_done(h);
        check(MemAvail=baseline,'mixed stress disposal has no heap leak');
        writeln(output,'PASS ',tests,' assertions'); close(output);
        assign(output,'A:\UNDO.OK'); rewrite(output);
        writeln(output,'UNDO JOURNAL PASS'); close(output);
end.
