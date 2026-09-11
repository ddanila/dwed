{ SPDX-License-Identifier: MIT }
{$A-}
unit emsshim;
interface
var page_data:array[0..16383] of byte; ems_function:word; ems_refuse:boolean;
procedure restore_ems;
implementation
uses dos;
type TRequest=record
        count:longint; src_type:byte; src_handle,src_offset,src_segment:word;
        dst_type:byte; dst_handle,dst_offset,dst_segment:word;
end;
var previous:pointer;
const hook:array[0..14] of byte=(
        $80,$fc,$57,$75,$05, { CMP AH,57 / JNE chain }
        $ea,0,0,0,0,        { JMP FAR handler }
        $ea,0,0,0,0);       { chain: JMP FAR previous }
procedure handler(flags,cs,ip,ax,bx,cx,dx,si,di,ds,es,bp:word); interrupt;
var request:TRequest; i:word; value:byte;
begin
        ems_function:=ax;
        if ems_refuse then begin ax:=$8800; exit end;
        Move(Mem[ds:si],request,sizeof(request));
        if (request.count<>16384) or
           ((request.src_type<>0) and (request.dst_type<>0)) then begin ax:=$8f00; exit end;
        for i:=0 to 16383 do begin
                if request.src_type=0 then begin
                        value:=page_data[i];
                        page_data[i]:=Mem[request.src_segment:request.src_offset+i];
                        if Lo(ax)=1 then Mem[request.src_segment:request.src_offset+i]:=value;
                end else begin
                        value:=Mem[request.dst_segment:request.dst_offset+i];
                        Mem[request.dst_segment:request.dst_offset+i]:=page_data[i];
                        if Lo(ax)=1 then page_data[i]:=value;
                end;
        end;
        ax:=ax and $ff;
end;
procedure restore_ems;
begin SetIntVec($67,previous) end;
begin
        GetIntVec($67,previous); Move(previous,hook[11],4);
        MemW[Seg(hook):Ofs(hook)+6]:=Ofs(handler);
        MemW[Seg(hook):Ofs(hook)+8]:=Seg(handler);
        ems_refuse:=false; SetIntVec($67,@hook);
end.
