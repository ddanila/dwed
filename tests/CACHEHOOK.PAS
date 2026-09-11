{ SPDX-License-Identifier: MIT }
unit cachehook;
interface
var available:boolean; transfer_hits:word;
procedure deny_cache_allocation(deny:boolean);
procedure arm_transfer(direction:byte; partial:boolean);
procedure restore_cache_hook;
implementation
uses dos;
var previous,real_driver:pointer; enabled,partial_copy,installed,deny_allocation:boolean; selected:byte;
const hook:array[0..28] of byte=(
        $3d,$00,$43,$74,$0a,$3d,$10,$43,$74,$08,
        $ea,0,0,0,0,$b0,$80,$cf,$bb,0,0,$50,$b8,0,0,$8e,$c0,$58,$cf);
procedure driver; far; assembler; nostackframe;
asm
        cmp deny_allocation,0
        je @transfer
        cmp ah,$09
        je @reject
        cmp ah,$c9
        je @reject
@transfer:
        cmp enabled,0
        je @chain
        cmp ah,$0b
        je @move
        cmp ah,$cb
        jne @chain
@move:
        cmp word ptr [si+4],0
        jne @read
        cmp selected,1
        jne @chain
        jmp @fail
@read:
        cmp selected,2
        jne @chain
@fail:
        mov enabled,0
        inc transfer_hits
        cmp partial_copy,0
        je @reject
        push si
        mov word ptr [si],8192
        call [real_driver]
        pop si
        mov word ptr [si],16384
@reject:
        xor ax,ax
        mov bl,$a0
        retf
@chain:
        jmp [real_driver]
end;
procedure deny_cache_allocation(deny:boolean);
begin deny_allocation:=deny end;
procedure arm_transfer(direction:byte; partial:boolean);
begin selected:=direction; partial_copy:=partial; enabled:=true end;
procedure restore_cache_hook;
begin if installed then SetIntVec($2f,previous); installed:=false end;
var regs:Registers;
begin
        FillChar(regs,sizeof(regs),0); regs.ax:=$4300; Intr($2f,regs);
        available:=regs.al=$80; installed:=false; enabled:=false; deny_allocation:=false; transfer_hits:=0;
        if available then begin
                regs.ax:=$4310; Intr($2f,regs); real_driver:=Ptr(regs.es,regs.bx);
                GetIntVec($2f,previous); Move(previous,hook[11],4);
                MemW[Seg(hook):Ofs(hook)+19]:=Ofs(driver);
                MemW[Seg(hook):Ofs(hook)+23]:=Seg(driver);
                SetIntVec($2f,@hook); installed:=true;
        end;
end.
