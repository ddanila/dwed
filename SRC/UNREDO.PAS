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
unit unredo;

{ Bounded, per-document line-delta journal. The storage adapter must record
  each mutation before applying it and replay groups atomically. This unit
  owns history bytes only; it never owns editor line pointers. }

interface

type
TUndoPosition = record
        line, top, anchor_line : longint;
        column, left, anchor_column : integer;
        selection : boolean;
end;
TUndoKind = (UNDO_REPLACE, UNDO_INSERT, UNDO_DELETE);
PUndoChange = ^TUndoChange;
TUndoChange = record
        previous, next : PUndoChange;
        line : longint;
        kind : TUndoKind;
        size : word;
        data : array[0..0] of byte;
end;
PUndoGroup = ^TUndoGroup;
TUndoGroup = record
        previous, next : PUndoGroup;
        first, last : PUndoChange;
        before_position, after_position : TUndoPosition;
        before_state, after_state, bytes : longint;
end;
TUndoHistory = record
        first, last, current, pending : PUndoGroup;
        bytes, limit, reserve : longint;
        state, saved_state, serial : longint;
        failed : boolean;
end;

const
UNDO_DEFAULT_LIMIT = 16384;
UNDO_DEFAULT_RESERVE = 32768;

procedure undo_init(var h:TUndoHistory; limit,reserve:longint);
procedure undo_done(var h:TUndoHistory);
function undo_begin(var h:TUndoHistory; position:TUndoPosition):boolean;
function undo_record(var h:TUndoHistory; kind:TUndoKind; line:longint;
                     before_text,after_text:string):boolean;
function undo_finish(var h:TUndoHistory; position:TUndoPosition):boolean;
{ Cancel frees the pending journal only. The adapter must first roll back any
  mutations already applied, using pending^.last and previous in reverse. }
procedure undo_cancel(var h:TUndoHistory);
function undo_previous(var h:TUndoHistory):PUndoGroup;
function undo_next(var h:TUndoHistory):PUndoGroup;
{ Acknowledge only after the whole group has been applied successfully. }
function undo_accept(var h:TUndoHistory; group:PUndoGroup; forward:boolean):boolean;
procedure undo_saved(var h:TUndoHistory);
procedure undo_unsaved(var h:TUndoHistory);
function undo_dirty(var h:TUndoHistory):boolean;
procedure undo_text(change:PUndoChange; var before_text,after_text:string);

implementation

function allocate(var h:TUndoHistory; size:word):pointer;
var p:pointer;
begin
        p:=nil;
        { DOS is single threaded. Keep a working-memory reserve and check the
          largest block as well as total free memory before GetMem. }
        if (MaxAvail>=size) and (MemAvail-longint(size)>=h.reserve) then
                GetMem(p,size);
        allocate:=p;
end;

procedure release_group(g:PUndoGroup);
var p,n:PUndoChange;
begin
        p:=g^.first;
        while p<>nil do begin
                n:=p^.next;
                FreeMem(p,p^.size);
                p:=n;
        end;
        FreeMem(g,sizeof(TUndoGroup));
end;

procedure undo_init(var h:TUndoHistory; limit,reserve:longint);
begin
        FillChar(h,sizeof(h),0);
        if limit<0 then limit:=0;
        if reserve<0 then reserve:=0;
        h.limit:=limit; h.reserve:=reserve;
end;

procedure undo_cancel(var h:TUndoHistory);
begin
        if h.pending<>nil then release_group(h.pending);
        h.pending:=nil; h.failed:=false;
end;

procedure undo_done(var h:TUndoHistory);
var p,n:PUndoGroup;
begin
        undo_cancel(h);
        p:=h.first;
        while p<>nil do begin
                n:=p^.next; release_group(p); p:=n;
        end;
        undo_init(h,h.limit,h.reserve);
end;

function undo_begin(var h:TUndoHistory; position:TUndoPosition):boolean;
var g:PUndoGroup;
begin
        undo_begin:=false;
        if (h.pending<>nil) or (h.serial=2147483647) then exit;
        h.failed:=false;
        if h.limit<sizeof(TUndoGroup) then exit;
        g:=allocate(h,sizeof(TUndoGroup));
        if g=nil then exit;
        FillChar(g^,sizeof(TUndoGroup),0);
        g^.before_position:=position;
        g^.before_state:=h.state;
        g^.bytes:=sizeof(TUndoGroup);
        h.pending:=g;
        undo_begin:=true;
end;

function undo_record(var h:TUndoHistory; kind:TUndoKind; line:longint;
                     before_text,after_text:string):boolean;
var p:PUndoChange; size:word; g:PUndoGroup;
begin
        undo_record:=false;
        if (h.pending=nil) or h.failed then exit;
        if (line<1) or ((kind=UNDO_INSERT) and (before_text<>'')) or
           ((kind=UNDO_DELETE) and (after_text<>'')) then begin
                h.failed:=true; exit;
        end;
        if (kind=UNDO_REPLACE) and (before_text=after_text) then begin
                undo_record:=true; exit;
        end;
        g:=h.pending;
        size:=sizeof(TUndoChange)-1+length(before_text)+length(after_text)+2;
        if g^.bytes+size>h.limit then begin h.failed:=true; exit end;
        p:=allocate(h,size);
        if p=nil then begin h.failed:=true; exit end;
        p^.size:=size; p^.line:=line; p^.kind:=kind;
        p^.previous:=g^.last; p^.next:=nil;
        { Payload: two Pascal byte strings, without padding to 255 bytes. }
        Move(before_text[0],p^.data[0],length(before_text)+1);
        Move(after_text[0],p^.data[length(before_text)+1],length(after_text)+1);
        if g^.last=nil then g^.first:=p else g^.last^.next:=p;
        g^.last:=p; inc(g^.bytes,size);
        undo_record:=true;
end;

procedure undo_text(change:PUndoChange; var before_text,after_text:string);
var offset:word;
begin
        Move(change^.data[0],before_text[0],change^.data[0]+1);
        offset:=change^.data[0]+1;
        Move(change^.data[offset],after_text[0],change^.data[offset]+1);
end;

function undo_previous(var h:TUndoHistory):PUndoGroup;
begin
        if h.pending<>nil then undo_previous:=nil
        else undo_previous:=h.current;
end;

function undo_next(var h:TUndoHistory):PUndoGroup;
begin
        if h.pending<>nil then undo_next:=nil
        else if h.current=nil then undo_next:=h.first
        else undo_next:=h.current^.next;
end;

function undo_finish(var h:TUndoHistory; position:TUndoPosition):boolean;
var g,p,n:PUndoGroup;
begin
        undo_finish:=false;
        if (h.pending=nil) or h.failed then exit;
        g:=h.pending;
        if g^.first=nil then begin
                undo_cancel(h); undo_finish:=true; exit;
        end;
        { Only a successful, nonempty edit invalidates redo. Until here an
          aborted edit leaves the previous history and saved state intact. }
        if h.current=nil then p:=h.first else p:=h.current^.next;
        while p<>nil do begin
                n:=p^.next; dec(h.bytes,p^.bytes); release_group(p); p:=n;
        end;
        if h.current=nil then h.first:=g else h.current^.next:=g;
        g^.previous:=h.current;
        g^.after_position:=position;
        inc(h.serial); g^.after_state:=h.serial;
        h.state:=h.serial;
        h.current:=g; h.last:=g; h.pending:=nil;
        inc(h.bytes,g^.bytes);
        { Evict whole oldest groups. Never retain half of a user command. }
        while h.bytes>h.limit do begin
                p:=h.first; h.first:=p^.next; h.first^.previous:=nil;
                dec(h.bytes,p^.bytes); release_group(p);
        end;
        undo_finish:=true;
end;

function undo_accept(var h:TUndoHistory; group:PUndoGroup; forward:boolean):boolean;
begin
        undo_accept:=false;
        if (h.pending<>nil) or (group=nil) then exit;
        if forward then begin
                if group<>undo_next(h) then exit;
                h.current:=group; h.state:=group^.after_state;
        end else begin
                if group<>undo_previous(h) then exit;
                h.current:=group^.previous; h.state:=group^.before_state;
        end;
        undo_accept:=true;
end;

procedure undo_unsaved(var h:TUndoHistory);
begin h.saved_state:=-1 end;

procedure undo_saved(var h:TUndoHistory);
begin
        { Saving a partially applied group must not establish a checkpoint. }
        if h.pending=nil then h.saved_state:=h.state;
end;

function undo_dirty(var h:TUndoHistory):boolean;
begin
        undo_dirty:=(h.state<>h.saved_state);
        if h.pending<>nil then
                if h.pending^.first<>nil then undo_dirty:=true;
end;

end.
