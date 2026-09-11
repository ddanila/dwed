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
UNIT DBM;
{ =========================================================================
  This is unit implements dbu files (like a .dbt) - container for memo fields
  with variable length. Free blocks will be reused.
  ========================================================================= }
INTERFACE

USES System2;

CONST DBM_INVALID=1019;

TYPE
DBM_HDR = RECORD
        sign       : WORD;
        next       : LONGINT;
        records    : LONGINT;
        root       : LONGINT;
        size       : WORD;
END;

DBMFile = RECORD
        f          : BFILE;
        header     : DBM_HDR;
        ready      : BOOLEAN;
        rblk_size  : WORD;
END;

{ Initialize the owner to zero before its first use; close before reuse. }
PROCEDURE dbm_Reset(VAR f : DBMFile; fname : STRING; blk_size : WORD);
PROCEDURE dbm_ReWrite(VAR f : DBMFile; fname : STRING; blk_size : WORD);
PROCEDURE dbm_ReWriteTemp(VAR f : DBMFile; blk_size : WORD);

FUNCTION dbm_IsOpen(VAR f : DBMFile) : BOOLEAN;

FUNCTION dbm_GetRoot(VAR f : DBMFile):LONGINT;
PROCEDURE dbm_SetRoot(VAR f : DBMFile; new_root : LONGINT);

FUNCTION dbm_TryAppend(VAR f:DBMFile; VAR b; size:WORD; VAR rec:LONGINT):BOOLEAN;
FUNCTION dbm_Add(VAR f : DBMFile; VAR b; size : WORD) : LONGINT;
FUNCTION dbm_TryGet(VAR f : DBMFile; rec : LONGINT; VAR b; size : WORD):BOOLEAN;
PROCEDURE dbm_Get(VAR f : DBMFile; rec : LONGINT; VAR b; size : WORD);
PROCEDURE dbm_Put(VAR f : DBMFile; rec : LONGINT; VAR b; size : WORD);
FUNCTION dbm_Size(VAR f : DBMFile; rec : LONGINT) : LONGINT;

PROCEDURE dbm_Free(VAR f : DBMFile; rec : LONGINT);

PROCEDURE dbm_Discard(VAR f:DBMFile);
PROCEDURE dbm_Close(VAR f : DBMFile);

IMPLEMENTATION

CONST
DBM_SIGN = $4D44;
ADDED_DATA = SizeOf(LONGINT) + SizeOf(WORD);

FUNCTION _norm_blk_size(blk_size : WORD) : WORD;
BEGIN
        IF blk_size>65526 THEN BEGIN _norm_blk_size:=0; EXIT END;
        blk_size := blk_size + ADDED_DATA;
        IF blk_size < SizeOf(DBM_HDR) THEN blk_size := SizeOf(DBM_HDR);
        IF (blk_size AND 3) <> 0 THEN blk_size := ((blk_size SHR 2) + 1) SHL 2;
        _norm_blk_size := blk_size;
END;

FUNCTION _go(VAR f : DBMFile; recno : LONGINT) : LONGINT;
VAR     r : LONGINT;
BEGIN
        r := recno * f.header.size;
        Seek(f.f, r);
        _go := r;
END;

PROCEDURE dbm_Reset(VAR f : DBMFile; fname : STRING; blk_size : WORD);
VAR candidate:DBM_HDR; count:WORD; error:INTEGER;
BEGIN
        IF IsOpen(f.f) OR f.f.delete_pending THEN BEGIN f.f.ioresult:=BFILE_PENDING; EXIT END;
        blk_size:=_norm_blk_size(blk_size);
        FillChar(f,SizeOf(DBMFile),0);
        IF blk_size=0 THEN BEGIN f.f.ioresult:=DBM_INVALID; EXIT END;
        Assign(f.f,fname); Reset(f.f); error:=f.f.ioresult;
        IF error=0 THEN BEGIN
                count:=BlockRead(f.f,candidate,SizeOf(candidate)); error:=f.f.ioresult;
                IF (error=0) AND (count<>SizeOf(candidate)) THEN error:=DBM_INVALID;
        END;
        IF error=0 THEN BEGIN
                IF (candidate.sign<>DBM_SIGN) OR (candidate.size<>blk_size) OR
                   (candidate.records<0) OR (candidate.next<0) OR (candidate.next>candidate.records) OR
                   (candidate.root<0) OR (candidate.root>candidate.records) THEN error:=DBM_INVALID
                ELSE IF (f.f.fsize<candidate.size) OR
                        (candidate.records>f.f.fsize DIV candidate.size-1) THEN error:=DBM_INVALID;
        END;
        IF error=0 THEN BEGIN
                f.header:=candidate; f.ready:=TRUE;
                f.rblk_size:=candidate.size-ADDED_DATA;
        END ELSE BEGIN
                { Close the read handle without writing an unvalidated header. }
                IF IsOpen(f.f) THEN Close(f.f);
                f.f.ioresult:=error;
        END;
END;

PROCEDURE _rewrite(VAR f : DBMFile);
VAR     i : WORD;
BEGIN
        IF IsOpen(f.f) THEN BEGIN
                f.header.sign := DBM_SIGN;
                f.header.next := 0;
                f.header.records := 0;
                f.header.root := 0;
                Seek(f.f, 0);
                IF f.f.ioresult<>0 THEN EXIT;
                BlockWrite(f.f, f.header, SizeOf(DBM_HDR));
                IF f.f.ioresult<>0 THEN EXIT;
                FOR i := 1 TO f.header.size - SizeOf(DBM_HDR) DO BEGIN
                        WriteByte(f.f,0); IF f.f.ioresult<>0 THEN EXIT;
                END;
                f.ready:=f.f.ioresult=0;
        END;
END;

PROCEDURE dbm_ReWrite(VAR f : DBMFile; fname : STRING; blk_size : WORD);
BEGIN
        IF IsOpen(f.f) OR f.f.delete_pending THEN BEGIN f.f.ioresult:=BFILE_PENDING; EXIT END;
        FillChar(f, SizeOf(DBMFile), #0);
        f.header.size:=_norm_blk_size(blk_size);
        IF f.header.size=0 THEN BEGIN f.f.ioresult:=DBM_INVALID; EXIT END;
        Assign(f.f, fname);
        ReWrite(f.f);
        f.header.size := _norm_blk_size(blk_size);
        f.rblk_size := f.header.size - ADDED_DATA;
        _rewrite(f);
END;

PROCEDURE dbm_ReWriteTemp(VAR f : DBMFile; blk_size : WORD);
BEGIN
        IF IsOpen(f.f) OR f.f.delete_pending THEN BEGIN f.f.ioresult:=BFILE_PENDING; EXIT END;
        FillChar(f, SizeOf(DBMFile), #0);
        f.header.size:=_norm_blk_size(blk_size);
        IF f.header.size=0 THEN BEGIN f.f.ioresult:=DBM_INVALID; EXIT END;
        ReWriteTemp(f.f);
        f.header.size := _norm_blk_size(blk_size);
        f.rblk_size := f.header.size - ADDED_DATA;
        _rewrite(f);
END;

FUNCTION dbm_IsOpen(VAR f : DBMFile) : BOOLEAN;
BEGIN
        dbm_IsOpen := f.ready AND IsOpen(f.f);
END;

{ Explicit temporary-store discard must not seek or flush payload pages. }
PROCEDURE dbm_Discard(VAR f:DBMFile);
BEGIN
        IF NOT IsOpen(f.f) AND NOT f.f.delete_pending THEN EXIT;
        IF NOT f.f.delonclose THEN BEGIN f.f.ioresult:=5; EXIT END;
        Close(f.f);
        IF IsOpen(f.f) OR f.f.delete_pending THEN EXIT;
        FillChar(f,SizeOf(DBMFile),0);
END;

PROCEDURE dbm_Close(VAR f : DBMFile);
BEGIN
        IF NOT IsOpen(f.f) AND NOT f.f.delete_pending THEN EXIT;
        IF f.ready AND IsOpen(f.f) THEN BEGIN
                Seek(f.f,0);
                IF f.f.ioresult<>0 THEN EXIT;
                BlockWrite(f.f,f.header,SizeOf(DBM_HDR));
                IF f.f.ioresult<>0 THEN EXIT;
        END;
        Close(f.f);
        IF IsOpen(f.f) OR f.f.delete_pending THEN EXIT;
        FillChar(f,SizeOf(DBMFile),0);
END;

PROCEDURE dbm_Free(VAR f : DBMFile; rec : LONGINT);
VAR     n : LONGINT;
BEGIN
        IF NOT dbm_IsOpen(f) THEN EXIT;
        WHILE rec <> 0 DO BEGIN
                _go(f, rec);
                n := ReadDWord(f.f);
                _go(f, rec);
                WriteDWord(f.f, f.header.next);
                WriteWord(f.f, 0);
                f.header.next := rec;
                rec := n;
        END;
END;

FUNCTION _alloc(VAR f : DBMFile) : LONGINT;
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
        _go(f, r);
        _alloc := r;
END;

{ Validate the complete chain, even when the caller requests only a prefix.
  Brent's cycle detector needs constant memory and detects short cycles without
  waiting for the database's record-count traversal bound. }
FUNCTION scan_chain(VAR f:DBMFile; rec:LONGINT; target:PCHAR; requested:WORD;
                    VAR total:LONGINT):BOOLEAN;
VAR link:PACKED RECORD next:LONGINT; count:WORD END;
    physical,visited,anchor,power,distance:LONGINT;
    copied,take,count:WORD; part:PCHAR;
BEGIN
        scan_chain:=FALSE; total:=0; copied:=0; visited:=0;
        IF NOT dbm_IsOpen(f) THEN BEGIN
                IF f.f.ioresult=0 THEN f.f.ioresult:=103;
                EXIT;
        END;
        physical:=FileSize(f.f);
        IF (f.header.size<=ADDED_DATA) OR (f.rblk_size<>f.header.size-ADDED_DATA) OR
           (physical<f.header.size) THEN BEGIN f.f.ioresult:=DBM_INVALID; EXIT END;
        anchor:=rec; power:=1; distance:=0;
        WHILE rec<>0 DO BEGIN
                IF (rec<1) OR (rec>f.header.records) OR
                   (rec>physical DIV f.header.size-1) OR (visited>=f.header.records) THEN BEGIN
                        f.f.ioresult:=DBM_INVALID; EXIT;
                END;
                Inc(visited); _go(f,rec);
                IF f.f.ioresult<>0 THEN EXIT;
                count:=BlockRead(f.f,link,SizeOf(link));
                IF f.f.ioresult<>0 THEN EXIT;
                IF count<>SizeOf(link) THEN BEGIN f.f.ioresult:=100; EXIT END;
                IF (link.count=0) OR (link.count>f.rblk_size) OR
                   (link.next<0) OR (link.next>f.header.records) OR
                   (total>2147483647-link.count) THEN BEGIN f.f.ioresult:=DBM_INVALID; EXIT END;
                Inc(total,link.count);
                take:=link.count;
                IF take>requested-copied THEN take:=requested-copied;
                IF (target<>NIL) AND (take<>0) THEN BEGIN
                        part:=FarBytePtr(target,copied);
                        count:=BlockRead(f.f,part^,take);
                        IF f.f.ioresult<>0 THEN EXIT;
                        IF count<>take THEN BEGIN f.f.ioresult:=100; EXIT END;
                        Inc(copied,take);
                END;
                rec:=link.next; Inc(distance);
                IF (rec<>0) AND (rec=anchor) THEN BEGIN f.f.ioresult:=DBM_INVALID; EXIT END;
                IF distance=power THEN BEGIN
                        anchor:=rec; distance:=0;
                        IF power<=1073741823 THEN power:=power*2 ELSE power:=2147483647;
                END;
        END;
        IF total<requested THEN BEGIN f.f.ioresult:=DBM_INVALID; EXIT END;
        scan_chain:=TRUE;
END;

FUNCTION dbm_Size(VAR f : DBMFile; rec : LONGINT) : LONGINT;
VAR total:LONGINT;
BEGIN
        dbm_Size:=0;
        IF scan_chain(f,rec,NIL,0,total) THEN dbm_Size:=total;
END;

FUNCTION dbm_TryGet(VAR f : DBMFile; rec : LONGINT; VAR b; size : WORD):BOOLEAN;
VAR staged:POINTER; total:LONGINT;
BEGIN
        dbm_TryGet:=FALSE; staged:=NIL;
        IF NOT dbm_IsOpen(f) THEN BEGIN
                IF f.f.ioresult=0 THEN f.f.ioresult:=103;
                EXIT;
        END;
        IF size<>0 THEN BEGIN
                IF MaxAvail<size THEN BEGIN f.f.ioresult:=8; EXIT END;
                GetMem(staged,size);
        END;
        IF scan_chain(f,rec,PCHAR(staged),size,total) THEN BEGIN
                IF size<>0 THEN CopyFarBytes(staged^,b,size);
                dbm_TryGet:=TRUE;
        END;
        IF staged<>NIL THEN FreeMem(staged,size);
END;

PROCEDURE dbm_Get(VAR f : DBMFile; rec : LONGINT; VAR b; size : WORD);
BEGIN
        dbm_TryGet(f,rec,b,size);
END;

{ Write complete new blocks without linking them into an existing chain or
  consuming the free list. A failed append may leave an unpublished tail;
  retry overwrites that tail starting at the unchanged record-count boundary. }
FUNCTION dbm_TryAppend(VAR f:DBMFile; VAR b; size:WORD; VAR rec:LONGINT):BOOLEAN;
VAR staged,source,payload:PCHAR;
    link:PACKED RECORD next:LONGINT; count:WORD END;
    physical,blocks,target,last:LONGINT; remaining,take:WORD;
BEGIN
        dbm_TryAppend:=FALSE;
        IF NOT dbm_IsOpen(f) THEN BEGIN
                IF f.f.ioresult=0 THEN f.f.ioresult:=103;
                EXIT;
        END;
        physical:=FileSize(f.f);
        IF (f.header.size<=ADDED_DATA) OR (f.rblk_size<>f.header.size-ADDED_DATA) OR
           (f.header.records<0) OR (f.header.next<0) OR (f.header.next>f.header.records) OR
           (f.header.root<0) OR (f.header.root>f.header.records) OR
           (physical<f.header.size) THEN BEGIN
                f.f.ioresult:=DBM_INVALID; EXIT;
        END;
        IF f.header.records>physical DIV f.header.size-1 THEN BEGIN f.f.ioresult:=DBM_INVALID; EXIT END;
        IF size=0 THEN BEGIN rec:=0; dbm_TryAppend:=TRUE; EXIT END;
        blocks:=(LONGINT(size)+f.rblk_size-1) DIV f.rblk_size;
        IF f.header.records>2147483647 DIV f.header.size-1-blocks THEN BEGIN
                f.f.ioresult:=DBM_INVALID; EXIT;
        END;
        IF MaxAvail<size THEN BEGIN f.f.ioresult:=8; EXIT END;
        GetMem(payload,size); CopyFarBytes(b,payload^,size);
        IF MaxAvail<f.header.size THEN BEGIN
                FreeMem(payload,size); f.f.ioresult:=8; EXIT;
        END;
        GetMem(staged,f.header.size);
        target:=f.header.records+1; last:=f.header.records+blocks;
        source:=payload; remaining:=size;
        Flush(f.f);
        WHILE (remaining<>0) AND (f.f.ioresult=0) DO BEGIN
                take:=remaining; IF take>f.rblk_size THEN take:=f.rblk_size;
                FillFarBytes(staged^,f.header.size,0);
                link.next:=0; IF target<last THEN link.next:=target+1;
                link.count:=take; Move(link,staged^,SizeOf(link));
                CopyFarBytes(source^,staged[ADDED_DATA],take);
                _go(f,target);
                IF f.f.ioresult=0 THEN BlockWrite(f.f,staged^,f.header.size);
                IF f.f.ioresult=0 THEN BEGIN Inc(target); source:=FarBytePtr(source,take); Dec(remaining,take) END;
        END;
        IF f.f.ioresult=0 THEN Flush(f.f);
        IF f.f.ioresult=0 THEN BEGIN
                rec:=f.header.records+1; f.header.records:=last; dbm_TryAppend:=TRUE;
        END;
        FreeMem(staged,f.header.size); FreeMem(payload,size);
END;

FUNCTION dbm_Add(VAR f : DBMFile; VAR b; size : WORD) : LONGINT;
VAR     root, prec, crec : LONGINT;
        p        : PCHAR;
        csize    : WORD;
        i        : WORD;
BEGIN
        root := 0;
        IF dbm_IsOpen(f) THEN BEGIN
                p := @b;
                prec := 0;
                WHILE size <> 0 DO BEGIN
                        crec := _alloc(f);
                        IF root = 0 THEN root := crec;
                        IF prec <> 0 THEN BEGIN
                                _go(f, prec);
                                WriteDWord(f.f, crec);
                        END;
                        csize := f.rblk_size;
                        IF csize > size THEN csize := size;
                        _go(f, crec);
                        WriteDWord(f.f, 0);
                        WriteWord(f.f, csize);
                        BlockWrite(f.f, p^, csize);
                        IF f.rblk_size > csize THEN BEGIN
                                i := f.rblk_size - csize;
                                WHILE i >= SizeOf(LONGINT) DO BEGIN
                                        WriteDWord(f.f, 0);
                                        Dec(i, SizeOf(LONGINT));
                                END;
                                WHILE i >= 1 DO BEGIN
                                        WriteByte(f.f, 0);
                                        Dec(i, 1);
                                END;
                        END;
                        Dec(size, csize);
                        Inc(p, csize);
                        prec := crec;
                END;
        END;
        dbm_Add := root;
END;

PROCEDURE dbm_Put(VAR f : DBMFile; rec : LONGINT; VAR b; size : WORD);
VAR     crec : LONGINT;
BEGIN
        IF NOT dbm_IsOpen(f) THEN EXIT;
        _go(f, rec);
        crec := ReadDWord(f.f);
        _go(f, rec);
        WriteDWord(f.f, 0);
        WriteWord(f.f, 0);
        dbm_Free(f, crec);
        dbm_Free(f, rec);
        dbm_Add(f, b, size);
END;

FUNCTION dbm_GetRoot(VAR f : DBMFile):LONGINT;
BEGIN
        dbm_GetRoot := f.header.root;
END;

PROCEDURE dbm_SetRoot(VAR f : DBMFile; new_root : LONGINT);
BEGIN
        f.header.root := new_root;
END;

END.
