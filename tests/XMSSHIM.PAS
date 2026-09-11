{ SPDX-License-Identifier: MIT }
{ Test-only XMS entry point. Install before EXMS unit initialization. }
unit xmsshim;
interface
var requested:longint; called_function:byte; refuse:boolean; classic:boolean;
procedure restore_driver;
implementation
uses dos;
var previous:pointer;
const hook:array[0..28] of byte=(
        $3d,$00,$43,$74,$0a, { CMP AX,4300 / JE present }
        $3d,$10,$43,$74,$08, { CMP AX,4310 / JE entry }
        $ea,0,0,0,0,        { JMP FAR previous }
        $b0,$80,$cf,        { present: MOV AL,80 / IRET }
        $bb,0,0,            { entry: MOV BX,driver offset }
        $50,$b8,0,0,$8e,$c0,$58,$cf); { preserve AX, set ES, IRET }
procedure driver; far; assembler;
asm
        cmp ah,0
        je @version
        mov called_function,ah
        cmp ah,$09
        je @ordinary
        cmp ah,$c9
        jne @bad
        mov word ptr requested,dx
        db $66,$c1,$ea,$10 { SHR EDX,16 }
        mov word ptr [requested+2],dx
        jmp @allocated
@ordinary:
        mov word ptr requested,dx
        mov word ptr [requested+2],0
@allocated:
        mov dx,$beef
        mov ax,1
        cmp refuse,0
        je @done
@bad:
        xor ax,ax
        mov bl,$a0
        jmp @done
@version:
        mov ax,$0351
        cmp classic,0
        je @done
        mov ax,$0300
@done:
end;
procedure restore_driver;
begin
        SetIntVec($2f,previous);
end;
begin
        classic:=ParamStr(1)='/CLASSIC'; refuse:=false;
        GetIntVec($2f,previous);
        Move(previous,hook[11],4);
        MemW[Seg(hook):Ofs(hook)+19]:=Ofs(driver);
        MemW[Seg(hook):Ofs(hook)+23]:=Seg(driver);
        SetIntVec($2f,@hook);
end.
