{ SPDX-License-Identifier: MIT }
unit sessboot;
interface
procedure session_boot_done;
implementation
uses dos;
var parent_seg,block_seg:word; storage:array[0..655] of byte;
procedure session_boot_done;
begin
        if block_seg=0 then exit;
        memw[PrefixSeg:$16]:=parent_seg;
        block_seg:=0;
end;
begin
        block_seg:=seg(storage)+(ofs(storage) shr 4)+1; FillChar(mem[block_seg:0],640,0);
        memw[block_seg:5]:=256;
        mem[block_seg:256]:=4;
        mem[block_seg:257]:=ord('D'); mem[block_seg:258]:=ord('W');
        mem[block_seg:259]:=ord('E'); mem[block_seg:260]:=ord('2');
        parent_seg:=memw[PrefixSeg:$16]; memw[PrefixSeg:$16]:=block_seg;
end.
