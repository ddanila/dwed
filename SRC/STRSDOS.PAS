{ MIT License

Copyright (c) 2022 Viacheslav Komenda

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. }
{$A-,F-}
unit strsdos;

{ Conventional memory string-storage }

interface

uses unredo;

const REPLAY_NO_MEMORY = 8;
      REPLAY_INVALID = 13;

function replay_group(var root:pointer; group:PUndoGroup; forward:boolean;
                      reserve:longint; var errCode:integer):boolean;

var transaction_jump:jmp_buf;
    transaction_error:integer;
    transaction_structure:boolean;
procedure transaction_bind(var history:TUndoHistory; root:pointer;
                           position:TUndoPosition);
procedure transaction_abort(errCode:integer);
procedure transaction_cancel;
procedure transaction_commit(position:TUndoPosition);

procedure init;
procedure done;

function new : pointer;

procedure free(r : pointer);

function create(next, prev : pointer; body : string) : pointer;

function put(r : pointer; var body : string) : pointer;
procedure get(r : pointer; var dest : string);
function delete(r : pointer; num_from, num_to : longint) : pointer;
function merge(r : pointer; var merged : boolean) : pointer;

function is_first(r : pointer) : boolean;
function is_last(r : pointer) : boolean;

function go_first(r : pointer) : pointer;
function go_last(r : pointer) : pointer;

function go_prev(r : pointer) : pointer;
function go_next(r : pointer) : pointer;

function is_nil(r : pointer) : boolean;

function renum(r : pointer) : longint;
function get_num(r : pointer) : longint;
function append(r : pointer; var pos : integer; p : pchar; var lnum:word) : pointer;
function split(r : pointer; pos : integer) : pointer;

function from_file(fname : string; tab_size : integer; var errCode : integer; scrupdate : pointer) : pointer;
procedure to_file(fname : string; r : pointer; var errCode : integer; scrupdate : pointer);

implementation

uses System2, scr, str, strutil, dwedtype, dwedutil;

type
PDosStringRec = ^TDosStringRec;
TDosStringRec = record
        next       : PDosStringRec;
        prev       : PDosStringRec;
        allocated  : word;
        num        : longint;
        len        : byte;
        body       : array[1..1] of char;
end;

PReplayStep = ^TReplayStep;
TReplayStep = record
        previous, next : PReplayStep;
        change : PUndoChange;
        prepared, removed, left, right : PDosStringRec;
        kind : TUndoKind;
        applied : boolean;
end;

PLiveHistory = ^TUndoHistory;
const live_history:PLiveHistory = nil;
var live_root:PDosStringRec;
    live_first,live_last:PReplayStep;
    live_position:TUndoPosition;

function live_change(kind:TUndoKind; node,left,right:PDosStringRec;
                     body:string):pointer;forward;

{$F-}

function norm_len(len : word) : word;
var w : word;
begin
        w := len shr 3;
        if (len and $07) <> 0 then inc(w);
        w := w shl 3;
        norm_len := w;
end;

function create(next, prev : pointer; body : string) : pointer;
var len, nlen : word;
        r : PDosStringRec;
begin
        if live_history<>nil then begin
                create:=live_change(UNDO_INSERT,nil,prev,next,body); exit;
        end;
        len := length(body);
        nlen := norm_len(len);
        getmem(r, sizeof(TDosStringRec) + nlen - 1);
        r^.next := PDosStringRec(next);
        r^.prev := PDosStringRec(prev);
        r^.len := len;
        r^.allocated := nlen;
        move(body[1], r^.body[1], len);
        if prev <> nil then PDosStringRec(prev)^.next := r;
        if next <> nil then PDosStringRec(next)^.prev := r;
        create := r;
end;

procedure free_str(r : pointer);
begin
        if r = nil then exit;
        freemem(r, sizeof(TDosStringRec) + PDosStringRec(r)^.allocated - 1);
end;

function put(r : pointer; var body : string) : pointer;
var len : word;
        old : PDosStringRec;
begin
        if live_history<>nil then begin
                put:=live_change(UNDO_REPLACE,r,PDosStringRec(r)^.prev,PDosStringRec(r)^.next,body); exit;
        end;
        len := norm_len(length(body));
        if len = PDosStringRec(r)^.allocated then begin
                len := length(body);
                move(body[1], PDosStringRec(r)^.body[1], len);
                PDosStringRec(r)^.len := len;
        end else begin
                old := r;
                r := PDosStringRec(create(PDosStringRec(r)^.next, PDosStringRec(r)^.prev, body));
                PDosStringRec(r)^.num := old^.num;
                strsdos.free_str(old);
        end;
        put := r;
end;

function new : pointer;
begin
        new := create(nil, nil, '');
end;

procedure get(r : pointer; var dest : string);
begin
        if r <> nil then begin
                move(PDosStringRec(r)^.body[1], dest[1], PDosStringRec(r)^.len);
                dest[0] := chr(PDosStringRec(r)^.len);
        end else dest := '';
end;

function is_first(r : pointer) : boolean;
begin
        is_first := PDosStringRec(r)^.prev = nil;
end;

function is_last(r : pointer) : boolean;
begin
        is_last := PDosStringRec(r)^.next = nil;
end;

function go_first(r : pointer) : pointer;
begin
        if r <> nil then begin
                while PDosStringRec(r)^.prev <> nil do r := PDosStringRec(r)^.prev;
        end;
        go_first := r;
end;

function go_last(r : pointer) : pointer;
begin
        if r <> nil then begin
                while PDosStringRec(r)^.next <> nil do r := PDosStringRec(r)^.next;
        end;
        go_last := r;
end;

function go_prev(r : pointer) : pointer;
begin
        if r <> nil then r := PDosStringRec(r)^.prev;
        go_prev := r;
end;

function go_next(r : pointer) : pointer;
begin
        if r <> nil then r := PDosStringRec(r)^.next;
        go_next := r;
end;

procedure free(r : pointer);
var o : pointer;
begin
        while r <> nil do begin
                o := PDosStringRec(r)^.next;
                strsdos.free_str(r);
                r := o;
        end;
end;

function renum(r : pointer) : longint;
var res : longint;
begin
        res := 0;
        while r <> nil do begin
                inc(res);
                PDosStringRec(r)^.num := res;
                r := PDosStringRec(r)^.next;
        end;
        renum := res;
end;

function get_num(r : pointer) : longint;
begin
        get_num := PDosStringRec(r)^.num;
end;

function del_str(r : PDosStringRec) : PDosStringRec;
var t : PDosStringRec;
begin
        if (r<>nil) and (live_history<>nil) then begin
                del_str:=live_change(UNDO_DELETE,r,r^.prev,r^.next,''); exit;
        end;
        if r <> nil then begin
                t := r;
                r := r^.next;
                with t^ do begin
                        if next <> nil then next^.prev := prev;
                        if prev <> nil then prev^.next := next;
                end;
                free_str(t);
        end;
        del_str := r;
end;

function delete(r : pointer; num_from, num_to : longint) : pointer;
var t  : PDosStringRec;
    n  : longint;
begin
        t := r;
        n := 1;
        while (t <> nil) and (t^.num <> num_from) do begin
                if t^.prev = nil then r := t;
                t^.num := n; inc(n);
                t := t^.next;
        end;
        while (t <> nil) and (t^.num <= num_to) do begin
                        t := del_str(t);
                        if (t <> nil) and (t^.prev = nil) then r := t;
        end;
        while (t <> nil) do begin
                t^.num := n; inc(n);
                t := t^.next;
        end;
        if live_history<>nil then r:=live_root;
        delete := r;
end;

function merge(r : pointer; var merged : boolean) : pointer;
var s1, s2 : string;
        t1, t2 :PDosStringRec;
begin
        merged := false;
        if PDosStringRec(r)^.next <> nil then begin
                t1 := r;
                t2 := t1^.next;
                strsdos.get(t1, s1);
                strsdos.get(t2, s2);
                if length(s1) + length(s2) <= 255 then begin
                        if live_history<>nil then begin
                                s1:=s1+s2; r:=strsdos.put(r,s1);
                                t2:=del_str(PDosStringRec(r)^.next);
                                merged:=true; merge:=r; exit;
                        end;
                        r := strsdos.create(t2^.next, t1^.prev, s1 + s2);
                        free_str(t1);
                        free_str(t2);
                        merged := true;
                end;
        end;
        merge := r;
end;

function append(r : pointer; var pos : integer; p : pchar; var lnum:word) : pointer;
var     s, src, s1, s2 : string;
        c : char;
        len : integer;
begin
        lnum := 0;
        if not ((r = nil) or (p = nil)) then begin
                s := '';
                strsdos.get(r, src);
                while p^ <> #0 do begin
                        c := p^;
                        case c of
                        #$0A: begin
                                inc(lnum);
                                s1 := '';
                                s2 := '';
                                len := length(src);
                                if len > 0 then s1 := copy(src, 1, pos - 1);
                                if pos <= len then s2 := copy(src, pos, len - pos + 1);
                                s1 := s1 + s;
                                r := strsdos.put(r, s1);
                                r := strsdos.create(PDosStringRec(r)^.next, r, s2);
                                src := s2;
                                pos := 1;
                                s := '';
                        end;
                        else if c <> #$0d then s := s + c;
                        end;
                        inc(p);
                end;
                if length(s) <> 0 then begin
                        strsdos.get(r, s1);
                        System.insert(s, s1, pos);
                        inc(pos, length(s));
                        r := strsdos.put(r, s1);
                end;
        end;
        append := r;
end;

function split(r : pointer; pos : integer) : pointer;
var s1, s2 : string;
begin
        strsdos.get(r, s1);
        s2 := copy(s1, pos, length(s1) - pos + 1);
        s1 := copy(s1, 1, pos - 1);
        r := strsdos.put(r, s1);
        strsdos.create(PDosStringRec(r)^.next, r, s2);
        split := r;
end;

{ Apply a journal group without publishing a partial document. Every node and
  replay record is allocated before the first link changes. Removed nodes are
  retained until commit, so rollback never needs to allocate. }
function replay_allocate(size:word; reserve:longint):pointer;
var p:pointer;
begin
        p:=nil;
        if (MaxAvail>=size) and (MemAvail-longint(size)>=reserve) then
                GetMem(p,size);
        replay_allocate:=p;
end;

procedure replay_link(var head:PDosStringRec; left,right,node:PDosStringRec);
begin
        if node<>nil then begin
                node^.prev:=left; node^.next:=right;
                if left=nil then head:=node else left^.next:=node;
                if right<>nil then right^.prev:=node;
        end else begin
                if left=nil then head:=right else left^.next:=right;
                if right<>nil then right^.prev:=left;
        end;
end;

procedure transaction_bind(var history:TUndoHistory; root:pointer;
                           position:TUndoPosition);
begin
        live_history:=@history; live_root:=root; live_position:=position;
        live_first:=nil; live_last:=nil; transaction_error:=0;
        transaction_structure:=false;
end;

procedure transaction_abort(errCode:integer);
begin
        transaction_error:=errCode;
        longjmp(transaction_jump,1);
end;

function live_change(kind:TUndoKind; node,left,right:PDosStringRec;
                     body:string):pointer;
var step:PReplayStep; oldtext:string; number:longint;
    p:PDosStringRec; size:word;
begin
        oldtext:='';
        if node<>nil then strsdos.get(node,oldtext);
        if (kind=UNDO_REPLACE) and (body=oldtext) then begin
                live_change:=node; exit;
        end;
        if live_history^.pending=nil then
                if not undo_begin(live_history^,live_position) then transaction_abort(1004);
        step:=replay_allocate(sizeof(TReplayStep),live_history^.reserve);
        if step=nil then transaction_abort(1004);
        FillChar(step^,sizeof(TReplayStep),0);
        step^.kind:=kind; step^.left:=left; step^.right:=right;
        step^.removed:=node; step^.previous:=live_last;
        if live_last=nil then live_first:=step else live_last^.next:=step;
        live_last:=step;
        if kind<>UNDO_DELETE then begin
                size:=norm_len(length(body));
                p:=replay_allocate(sizeof(TDosStringRec)+size-1,live_history^.reserve);
                if p=nil then transaction_abort(1004);
                p^.next:=nil; p^.prev:=nil; p^.num:=0;
                if node<>nil then p^.num:=node^.num;
                p^.allocated:=size; p^.len:=length(body);
                Move(body[1],p^.body[1],length(body)); step^.prepared:=p;
        end;
        if (not transaction_structure) and (node<>nil) then number:=node^.num
        else begin
                number:=1; p:=left;
                while p<>nil do begin inc(number); p:=p^.prev end;
        end;
        if kind<>UNDO_REPLACE then transaction_structure:=true;
        if not undo_record(live_history^,kind,number,oldtext,body) then
                transaction_abort(1004);
        replay_link(live_root,left,right,step^.prepared);
        if node<>nil then begin node^.prev:=nil; node^.next:=nil end;
        step^.applied:=true;
        if kind=UNDO_DELETE then live_change:=right else live_change:=step^.prepared;
end;

procedure transaction_cancel;
var step,previous:PReplayStep; number:longint;
begin
        step:=live_last;
        while step<>nil do begin
                if step^.applied then replay_link(live_root,step^.left,step^.right,step^.removed);
                step:=step^.previous;
        end;
        step:=live_last;
        while step<>nil do begin
                previous:=step^.previous;
                free_str(step^.prepared); FreeMem(step,sizeof(TReplayStep)); step:=previous;
        end;
        number:=strsdos.renum(live_root);
        undo_cancel(live_history^);
        live_history:=nil; live_first:=nil; live_last:=nil;
end;

procedure transaction_commit(position:TUndoPosition);
var step,next:PReplayStep;
begin
        if live_history^.pending<>nil then
                if not undo_finish(live_history^,position) then transaction_abort(1004);
        step:=live_first;
        while step<>nil do begin
                next:=step^.next; free_str(step^.removed);
                FreeMem(step,sizeof(TReplayStep)); step:=next;
        end;
        live_history:=nil; live_first:=nil; live_last:=nil;
end;

function replay_group(var root:pointer; group:PUndoGroup; forward:boolean;
                      reserve:longint; var errCode:integer):boolean;
var first,last,step,next:PReplayStep;
    change:PUndoChange;
    head,node,left:PDosStringRec;
    oldtext,newtext,actual,temp:string;
    size:word; number:longint;
begin
        replay_group:=false; errCode:=REPLAY_INVALID;
        if group=nil then exit;
        if reserve<0 then reserve:=0;
        first:=nil; last:=nil; errCode:=0;
        if forward then change:=group^.first else change:=group^.last;
        while (change<>nil) and (errCode=0) do begin
                step:=replay_allocate(sizeof(TReplayStep),reserve);
                if step=nil then errCode:=REPLAY_NO_MEMORY else begin
                        FillChar(step^,sizeof(TReplayStep),0);
                        step^.change:=change; step^.kind:=change^.kind;
                        step^.previous:=last;
                        if last=nil then first:=step else last^.next:=step;
                        last:=step;
                        undo_text(change,oldtext,newtext);
                        if not forward then begin
                                temp:=oldtext; oldtext:=newtext; newtext:=temp;
                                case step^.kind of
                                UNDO_INSERT:step^.kind:=UNDO_DELETE;
                                UNDO_DELETE:step^.kind:=UNDO_INSERT;
                                end;
                        end;
                        if step^.kind<>UNDO_DELETE then begin
                                size:=norm_len(length(newtext));
                                node:=replay_allocate(sizeof(TDosStringRec)+size-1,reserve);
                                if node=nil then errCode:=REPLAY_NO_MEMORY else begin
                                        node^.next:=nil; node^.prev:=nil; node^.num:=0;
                                        node^.allocated:=size; node^.len:=length(newtext);
                                        Move(newtext[1],node^.body[1],length(newtext));
                                        step^.prepared:=node;
                                end;
                        end;
                end;
                if forward then change:=change^.next else change:=change^.previous;
        end;
        head:=root; step:=first;
        while (step<>nil) and (errCode=0) do begin
                { Resolve the ordinal in the intermediate document, not the
                  cached line numbers from before the command. }
                node:=head; left:=nil; number:=1;
                while (node<>nil) and (number<step^.change^.line) do begin
                        left:=node; node:=node^.next; inc(number);
                end;
                if (number<>step^.change^.line) or
                   ((node=nil) and (step^.kind<>UNDO_INSERT)) then
                        errCode:=REPLAY_INVALID
                else begin
                        if step^.kind=UNDO_INSERT then step^.right:=node
                        else begin
                                undo_text(step^.change,oldtext,newtext);
                                if not forward then oldtext:=newtext;
                                strsdos.get(node,actual);
                                if actual<>oldtext then errCode:=REPLAY_INVALID;
                                step^.removed:=node; step^.right:=node^.next;
                        end;
                        if errCode=0 then begin
                                step^.left:=left;
                                replay_link(head,step^.left,step^.right,step^.prepared);
                                if step^.removed<>nil then begin
                                        step^.removed^.next:=nil;
                                        step^.removed^.prev:=nil;
                                end;
                                step^.applied:=true;
                        end;
                end;
                step:=step^.next;
        end;
        if errCode<>0 then begin
                step:=last;
                while step<>nil do begin
                        if step^.applied then
                                replay_link(head,step^.left,step^.right,step^.removed);
                        step:=step^.previous;
                end;
        end else begin
                root:=head;
                number:=strsdos.renum(root);
                replay_group:=true;
        end;
        step:=first;
        while step<>nil do begin
                next:=step^.next;
                if errCode=0 then free_str(step^.removed)
                else free_str(step^.prepared);
                FreeMem(step,sizeof(TReplayStep)); step:=next;
        end;
end;

function from_file(fname : string; tab_size : integer; var errCode : integer; scrupdate : pointer) : pointer;
var     root, cur, last : Pointer;
        f          : bfile;
        s          : string;
        i          : integer;
        total      : longint;
        position   : longint;
        scrup      : TPercentUpdateProc;
        tabs       : string;
        readed     : integer;
        start_date : longint;
begin
        scrup := TPercentUpdateProc(scrupdate);
        start_date := get_ticks;

        fillchar(f, sizeof(bfile), #0);
        fillchar(tabs[1], 255, #32);
        tabs[0] := chr(tab_size);

        root := nil; last := nil;
        readed := 0;
        total := 0;
        position := 0;

        assign(f, fname);
        ResetReadOnly(f);
        if not IsOpen(f) then errCode := 104 else total := filesize(f);

        if total <> 0 then begin
                while not eof(f) do begin
                        readln(f, s);
                        remove_tabs(s, tabs);
                        cur := strsdos.create(nil, last, s);
                        if root = nil then root := cur;
                        last := cur;
                        inc(readed, ord(s[0]));
                        if readed > PROGRESS_UPDATE then begin
                                if scrupdate <> nil then begin
                                        position := filepos(f);
                                        scrup(position, total, start_date);
                                end;
                                readed := 0;
                        end;
                end;
        end;

        if IsOpen(f) then close(f);

        if root = nil then root := strsdos.new;
        from_file := root;
end;

procedure to_file(fname : string; r : pointer; var errCode : integer; scrupdate : pointer);
var     f          : bfile;
        s          : string;
        total      : longint;
        position   : longint;
        scrup      : TPercentUpdateProc;
        writed     : integer;
        start_date : longint;
begin
        assign(f, fname);
        rewrite(f);
        if not isopen(f) then begin
                errCode := 105;
                exit;
        end;
        scrup := TPercentUpdateProc(scrupdate);
        start_date := get_ticks;

        total := renum(r);
        position := 0;
        writed := 0;

        while r <> nil do begin
                strsdos.get(r, s);
                writeln(f, s);
                r := strsdos.go_next(r);

                inc(writed, ord(s[0]));
                if writed > PROGRESS_UPDATE then begin
                        if scrupdate <> nil then begin
                                inc(position);
                                scrup(position, total, start_date);
                        end;
                        writed := 0;
                end;
        end;
        truncate(f);
        close(f);
end;

procedure init;
begin
end;

procedure done;
begin
end;

function is_nil(r : pointer) : boolean;
begin
        is_nil := r = nil;
end;

end.
