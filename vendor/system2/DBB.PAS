{  MIT License

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
{$A-,I-,S-,R-,D+,L+,Q-,F-,G-,O-,B-}
UNIT DBB;
{ =========================================================================
  This is unit implements dbb files (like a .dbt) - but fixed size blocks,
  has "garbage collection" (free blocks will be reused).
  ========================================================================= }
INTERFACE

USES System2;

CONST DBB_INVALID=1019;

TYPE
DBB_HDR = RECORD
        sign       : WORD;
        next       : LONGINT;
        records    : LONGINT;
        root       : LONGINT;
        size       : WORD;
END;

DBBFile = RECORD
        f          : BFILE;
        header     : DBB_HDR;
        ready      : BOOLEAN;
        rollback_data : POINTER;
        rollback_rec,rollback_pos : LONGINT;
        rollback_size : WORD;
END;

{ Initialize the owner to zero before its first use; close before reuse. }
PROCEDURE dbb_Reset(VAR f : DBBFile; fname : STRING; blk_size : WORD);
PROCEDURE dbb_ReWrite(VAR f : DBBFile; fname : STRING; blk_size : WORD);
PROCEDURE dbb_ReWriteTemp(VAR f : DBBFile; blk_size : WORD);

FUNCTION dbb_IsOpen(VAR f : DBBFile) : BOOLEAN;

FUNCTION dbb_PendingWrite(VAR f:DBBFile):BOOLEAN;
FUNCTION dbb_RetryRollback(VAR f:DBBFile):BOOLEAN;
FUNCTION dbb_TryPut(VAR f:DBBFile; rec:LONGINT; VAR b):BOOLEAN;
FUNCTION dbb_TryAppend(VAR f:DBBFile; VAR b; VAR rec:LONGINT):BOOLEAN;
FUNCTION dbb_Add(VAR f : DBBFile; VAR b) : LONGINT;
PROCEDURE dbb_Put(VAR f : DBBFile; rec : LONGINT; VAR b);
FUNCTION dbb_TryGet(VAR f : DBBFile; rec : LONGINT; VAR b):BOOLEAN;
PROCEDURE dbb_Get(VAR f : DBBFile; rec : LONGINT; VAR b);

PROCEDURE dbb_Free(VAR f : DBBFile; rec : LONGINT);
PROCEDURE dbb_Discard(VAR f:DBBFile);
PROCEDURE dbb_Close(VAR f : DBBFile);

FUNCTION dbb_GetRoot(VAR f : DBBFile):LONGINT;
PROCEDURE dbb_SetRoot(VAR f : DBBFile; new_root : LONGINT);

IMPLEMENTATION

TYPE
PLONGINT = ^LONGINT;

CONST
DBB_SIGN     = $4244;
DBB_HDR_SIZE = SizeOf(DBB_HDR);

FUNCTION _go(VAR f : DBBFile; recno : LONGINT) : LONGINT;
VAR     r : LONGINT;
BEGIN
        r := DBB_HDR_SIZE + (recno - 1) * f.header.size;
        Seek(f.f, DBB_HDR_SIZE + (recno - 1) * f.header.size);
        _go := r;
END;

PROCEDURE dbb_Reset(VAR f : DBBFile; fname : STRING; blk_size : WORD);
VAR candidate:DBB_HDR; count:WORD; error:INTEGER;
BEGIN
        IF IsOpen(f.f) OR f.f.delete_pending OR (f.rollback_data<>NIL) THEN BEGIN f.f.ioresult:=BFILE_PENDING; EXIT END;
        IF blk_size<SizeOf(LONGINT) THEN blk_size:=SizeOf(LONGINT);
        FillChar(f,SizeOf(DBBFile),0);
        IF blk_size=0 THEN BEGIN f.f.ioresult:=DBB_INVALID; EXIT END;
        Assign(f.f,fname); Reset(f.f); error:=f.f.ioresult;
        IF error=0 THEN BEGIN
                count:=BlockRead(f.f,candidate,SizeOf(candidate)); error:=f.f.ioresult;
                IF (error=0) AND (count<>SizeOf(candidate)) THEN error:=DBB_INVALID;
        END;
        IF error=0 THEN BEGIN
                IF (candidate.sign<>DBB_SIGN) OR (candidate.size<>blk_size) OR
                   (candidate.records<0) OR (candidate.next<0) OR (candidate.next>candidate.records) OR
                   (candidate.root<0) OR (candidate.root>candidate.records) THEN error:=DBB_INVALID
                ELSE IF (f.f.fsize<SizeOf(DBB_HDR)) OR
                        (candidate.records>(f.f.fsize-SizeOf(DBB_HDR)) DIV candidate.size) THEN error:=DBB_INVALID;
        END;
        IF error=0 THEN BEGIN
                f.header:=candidate; f.ready:=TRUE;
        END ELSE BEGIN
                { Close the read handle without writing an unvalidated header. }
                IF IsOpen(f.f) THEN Close(f.f);
                f.f.ioresult:=error;
        END;
END;

PROCEDURE _rewrite(VAR f : DBBFile; blk_size : WORD);
BEGIN
        IF blk_size < SizeOf(LONGINT) THEN blk_size := SizeOf(LONGINT);
        IF IsOpen(f.f) THEN BEGIN
                f.header.sign := DBB_SIGN;
                f.header.next := 0;
                f.header.records := 0;
                f.header.root := 0;
                f.header.size := blk_size;
                Seek(f.f, 0);
                IF f.f.ioresult<>0 THEN EXIT;
                BlockWrite(f.f, f.header, DBB_HDR_SIZE);
                f.ready:=f.f.ioresult=0;
        END;
END;

PROCEDURE dbb_ReWrite(VAR f : DBBFile; fname : STRING; blk_size : WORD);
BEGIN
        IF IsOpen(f.f) OR f.f.delete_pending OR (f.rollback_data<>NIL) THEN BEGIN f.f.ioresult:=BFILE_PENDING; EXIT END;
        FillChar(f, SizeOf(DBBFile), #0);
        Assign(f.f, fname);
        ReWrite(f.f);
        _rewrite(f, blk_size);
END;

PROCEDURE dbb_ReWriteTemp(VAR f : DBBFile; blk_size : WORD);
BEGIN
        IF IsOpen(f.f) OR f.f.delete_pending OR (f.rollback_data<>NIL) THEN BEGIN f.f.ioresult:=BFILE_PENDING; EXIT END;
        FillChar(f, SizeOf(DBBFile), #0);
        ReWriteTemp(f.f);
        _rewrite(f, blk_size);
END;

FUNCTION dbb_IsOpen(VAR f : DBBFile) : BOOLEAN;
BEGIN
        dbb_IsOpen := f.ready AND IsOpen(f.f);
END;

FUNCTION dbb_PendingWrite(VAR f:DBBFile):BOOLEAN;
BEGIN dbb_PendingWrite:=f.rollback_data<>NIL END;

PROCEDURE release_rollback(VAR f:DBBFile);
BEGIN
        FreeMem(f.rollback_data,f.rollback_size);
        f.rollback_data:=NIL; f.rollback_rec:=0; f.rollback_pos:=0; f.rollback_size:=0;
END;

FUNCTION dbb_RetryRollback(VAR f:DBBFile):BOOLEAN;
BEGIN
        dbb_RetryRollback:=FALSE;
        IF NOT dbb_PendingWrite(f) THEN BEGIN f.f.ioresult:=0; dbb_RetryRollback:=TRUE; EXIT END;
        IF NOT dbb_IsOpen(f) THEN BEGIN f.f.ioresult:=103; EXIT END;
        Seek(f.f,f.rollback_pos);
        IF f.f.ioresult=0 THEN BlockWrite(f.f,f.rollback_data^,f.rollback_size);
        IF f.f.ioresult=0 THEN Flush(f.f);
        IF f.f.ioresult=0 THEN BEGIN release_rollback(f); dbb_RetryRollback:=TRUE END;
END;

{ Explicitly abandon a temporary database, including any pending before-image.
  A refused handle close still retains every owner; deletion can retry later. }
PROCEDURE dbb_Discard(VAR f:DBBFile);
BEGIN
        IF NOT IsOpen(f.f) AND NOT f.f.delete_pending AND NOT dbb_PendingWrite(f) THEN EXIT;
        IF NOT f.f.delonclose THEN BEGIN f.f.ioresult:=5; EXIT END;
        Close(f.f);
        IF IsOpen(f.f) THEN EXIT;
        IF dbb_PendingWrite(f) THEN release_rollback(f);
        IF f.f.delete_pending THEN EXIT;
        FillChar(f,SizeOf(DBBFile),0);
END;

PROCEDURE dbb_Close(VAR f : DBBFile);
BEGIN
        IF dbb_PendingWrite(f) THEN IF NOT dbb_RetryRollback(f) THEN EXIT;
        IF NOT IsOpen(f.f) AND NOT f.f.delete_pending THEN EXIT;
        IF f.ready AND IsOpen(f.f) THEN BEGIN
                Seek(f.f,0);
                IF f.f.ioresult<>0 THEN EXIT;
                BlockWrite(f.f,f.header,DBB_HDR_SIZE);
                IF f.f.ioresult<>0 THEN EXIT;
        END;
        Close(f.f);
        IF IsOpen(f.f) OR f.f.delete_pending THEN EXIT;
        FillChar(f,SizeOf(DBBFile),0);
END;

PROCEDURE dbb_Free(VAR f : DBBFile; rec : LONGINT);
BEGIN
        IF (NOT dbb_IsOpen(f)) OR (rec = 0) THEN EXIT;
        IF NOT dbb_RetryRollback(f) THEN EXIT;
        _go(f, rec);
        WriteDWord(f.f, f.header.next);
        f.header.next := rec;
END;

FUNCTION _alloc(VAR f : DBBFile) : LONGINT;
VAR     r : LONGINT;
BEGIN
        IF f.header.next <> 0 THEN BEGIN
                r := f.header.next;
                _go(f, r);
                f.header.next := ReadDWord(f.f);
        END ELSE BEGIN
                Inc(f.header.records);
                r := f.header.records;
        END;
        _alloc := r;
END;

FUNCTION valid_record(VAR f:DBBFile; rec:LONGINT):BOOLEAN;
VAR physical:LONGINT;
BEGIN
        valid_record:=FALSE;
        IF NOT dbb_IsOpen(f) THEN BEGIN
                IF f.f.ioresult=0 THEN f.f.ioresult:=103;
                EXIT;
        END;
        physical:=FileSize(f.f);
        IF (rec<1) OR (rec>f.header.records) OR (f.header.size<SizeOf(LONGINT)) OR
           (physical<DBB_HDR_SIZE) THEN BEGIN f.f.ioresult:=DBB_INVALID; EXIT END;
        IF rec>(physical-DBB_HDR_SIZE) DIV f.header.size THEN BEGIN f.f.ioresult:=DBB_INVALID; EXIT END;
        valid_record:=TRUE;
END;

FUNCTION dbb_TryGet(VAR f : DBBFile; rec : LONGINT; VAR b):BOOLEAN;
VAR staged:POINTER; count:WORD;
BEGIN
        dbb_TryGet:=FALSE;
        IF NOT valid_record(f,rec) THEN EXIT;
        IF dbb_PendingWrite(f) AND (rec=f.rollback_rec) THEN BEGIN
                IF f.header.size<>f.rollback_size THEN BEGIN f.f.ioresult:=DBB_INVALID; EXIT END;
                CopyFarBytes(f.rollback_data^,b,f.rollback_size); dbb_TryGet:=TRUE; EXIT;
        END;
        IF MaxAvail<f.header.size THEN BEGIN f.f.ioresult:=8; EXIT END;
        GetMem(staged,f.header.size);
        _go(f,rec);
        IF f.f.ioresult=0 THEN BEGIN
                count:=BlockRead(f.f,staged^,f.header.size);
                IF (f.f.ioresult=0) AND (count<>f.header.size) THEN f.f.ioresult:=100;
        END;
        IF f.f.ioresult=0 THEN BEGIN
                CopyFarBytes(staged^,b,f.header.size); dbb_TryGet:=TRUE;
        END;
        FreeMem(staged,f.header.size);
END;

PROCEDURE dbb_Get(VAR f : DBBFile; rec : LONGINT; VAR b);
BEGIN
        dbb_TryGet(f,rec,b);
END;

{ The before-image becomes the authoritative record on a failed write.
  Keep it owned until rollback has reached the backing file successfully. }
FUNCTION dbb_TryPut(VAR f:DBBFile; rec:LONGINT; VAR b):BOOLEAN;
VAR candidate,before:POINTER; size,count:WORD; position:LONGINT;
BEGIN
        dbb_TryPut:=FALSE;
        IF NOT dbb_IsOpen(f) THEN BEGIN
                IF f.f.ioresult=0 THEN f.f.ioresult:=103;
                EXIT;
        END;
        IF NOT dbb_RetryRollback(f) THEN EXIT;
        IF NOT valid_record(f,rec) THEN EXIT;
        size:=f.header.size; position:=DBB_HDR_SIZE+(rec-1)*size;
        IF MaxAvail<size THEN BEGIN f.f.ioresult:=8; EXIT END;
        GetMem(candidate,size); CopyFarBytes(b,candidate^,size);
        IF MaxAvail<size THEN BEGIN FreeMem(candidate,size); f.f.ioresult:=8; EXIT END;
        GetMem(before,size);
        _go(f,rec);
        IF f.f.ioresult=0 THEN BEGIN
                count:=BlockRead(f.f,before^,size);
                IF (f.f.ioresult=0) AND (count<>size) THEN f.f.ioresult:=100;
        END;
        IF f.f.ioresult=0 THEN Flush(f.f);
        IF f.f.ioresult=0 THEN BEGIN
                f.rollback_data:=before; before:=NIL;
                f.rollback_rec:=rec; f.rollback_pos:=position; f.rollback_size:=size;
                Seek(f.f,position);
                IF f.f.ioresult=0 THEN BlockWrite(f.f,candidate^,size);
                IF f.f.ioresult=0 THEN Flush(f.f);
                IF f.f.ioresult=0 THEN BEGIN release_rollback(f); dbb_TryPut:=TRUE END;
        END;
        IF before<>NIL THEN FreeMem(before,size);
        FreeMem(candidate,size);
END;

{ Copy-on-write callers append an unpublished record instead of consuming
  the free list. Publish its number only after complete buffered writeback. }
FUNCTION dbb_TryAppend(VAR f:DBBFile; VAR b; VAR rec:LONGINT):BOOLEAN;
VAR staged:POINTER; physical,target:LONGINT;
BEGIN
        dbb_TryAppend:=FALSE;
        IF NOT dbb_IsOpen(f) THEN BEGIN
                IF f.f.ioresult=0 THEN f.f.ioresult:=103;
                EXIT;
        END;
        IF NOT dbb_RetryRollback(f) THEN EXIT;
        physical:=FileSize(f.f);
        IF (f.header.size<SizeOf(LONGINT)) OR (f.header.records<0) OR
           (f.header.next<0) OR (f.header.next>f.header.records) OR
           (f.header.root<0) OR (f.header.root>f.header.records) OR
           (physical<DBB_HDR_SIZE) THEN BEGIN f.f.ioresult:=DBB_INVALID; EXIT END;
        IF (f.header.records>(physical-DBB_HDR_SIZE) DIV f.header.size) OR
           (f.header.records>=(2147483647-DBB_HDR_SIZE) DIV f.header.size) THEN BEGIN
                f.f.ioresult:=DBB_INVALID; EXIT;
        END;
        IF MaxAvail<f.header.size THEN BEGIN f.f.ioresult:=8; EXIT END;
        GetMem(staged,f.header.size); CopyFarBytes(b,staged^,f.header.size);
        target:=f.header.records+1;
        Flush(f.f);
        IF f.f.ioresult=0 THEN _go(f,target);
        IF f.f.ioresult=0 THEN BlockWrite(f.f,staged^,f.header.size);
        IF f.f.ioresult=0 THEN Flush(f.f);
        IF f.f.ioresult=0 THEN BEGIN
                f.header.records:=target; rec:=target; dbb_TryAppend:=TRUE;
        END;
        FreeMem(staged,f.header.size);
END;

FUNCTION dbb_Add(VAR f : DBBFile; VAR b) : LONGINT;
VAR     res : LONGINT;
BEGIN
        res := 0;
        IF dbb_IsOpen(f) THEN BEGIN
                IF NOT dbb_RetryRollback(f) THEN BEGIN dbb_Add:=0; EXIT END;
                res := _alloc(f);
                _go(f, res);
                BlockWrite(f.f, b, f.header.size);
        END;
        dbb_Add := res;
END;

PROCEDURE dbb_Put(VAR f : DBBFile; rec : LONGINT; VAR b);
BEGIN
        IF (NOT dbb_IsOpen(f)) OR (rec = 0) THEN EXIT;
        IF NOT dbb_RetryRollback(f) THEN EXIT;
        _go(f, rec);
        BlockWrite(f.f, b, f.header.size);
END;

FUNCTION dbb_GetRoot(VAR f : DBBFile):LONGINT;
BEGIN
        dbb_GetRoot := f.header.root;
END;

PROCEDURE dbb_SetRoot(VAR f : DBBFile; new_root : LONGINT);
BEGIN
        IF dbb_PendingWrite(f) THEN IF NOT dbb_RetryRollback(f) THEN EXIT;
        f.header.root := new_root;
END;

END.
