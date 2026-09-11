; SPDX-License-Identifier: MIT
; Reimplements the DWED.C-- protocol by Viacheslav Komenda (copyright 2022).
; See ../LICENSE for the inherited MIT notice.
; 8086 DOS launcher for the DWED overlay protocol (see DWEDLNCH.PAS).
bits 16
cpu 8086
org 100h

start:
    cld
    push cs
    pop ds
    push cs
    pop es
    cli
    mov ax,cs
    mov ss,ax
    mov sp,stack_top
    sti
    mov bx,(resident_end-$$+100h+15)/16
    mov ah,4Ah
    int 21h
    jc fatal_memory
    call check_parent
    jc fatal_cycle
    mov word [5],info
    mov ax,cs
    mov [params+4],ax
    mov [params+8],ax
    mov [params+12],ax
    mov ah,19h
    int 21h
    mov [drive],al
    mov si,directory+1
    xor dx,dx
    mov ax,7147h
    stc
    int 21h
    jnc .directory_ok
    mov si,directory+1
    xor dx,dx
    mov ah,47h
    int 21h
    jc fatal_directory
.directory_ok:
    call environment
    jc fatal_environment
    ; BIOS ticks plus PSP distinguish simultaneous editor sessions.
    xor ax,ax
    int 1Ah
    mov ax,cs
    xor cx,ax
    mov di,session+1
    mov ax,cx
    call hex_word
    mov ax,dx
    call hex_word

editor:
    mov word [params],0
    mov dx,overlay
    mov word [params+2],80h
    call spawn
    or ax,ax
    jnz fatal_exec
    mov ah,4Dh
    int 21h
    cmp al,254
    je command
    mov ah,4Ch
    int 21h
command:
    mov byte [resume_pending],1
    ; The overlay uses a Pascal string; DOS accepts at most 126 tail bytes.
    xor bx,bx
    mov bl,[command_tail]
    cmp byte [command_tail+bx],0
    jne .length_ready
    dec bx
    mov [command_tail],bl
.length_ready:
    cmp bx,126
    ja fatal_command
    mov byte [command_tail+bx+1],13
    call command_environment
    jc .failed
    mov ax,[env_block]
    mov [params],ax
    mov dx,comspec
    mov word [params+2],command_tail
    call spawn
    or ax,ax
    jz .restore
.failed:
    mov dx,msg_command
    call puts
.restore:
    mov dl,[drive]
    mov ah,0Eh
    int 21h
    mov dx,directory
    mov ax,713Bh
    stc
    int 21h
    jnc .pause
    mov dx,directory
    mov ah,3Bh
    int 21h
    jc fatal_directory
.pause:
    mov dx,msg_pause
    call puts
    xor ax,ax
    int 16h
    jmp editor

; DOS EXEC may destroy the stack on older DOS versions. Keep the saved state
; in CS and restore SS:SP before using any stack-based data after it returns.
spawn:
    mov [saved_sp],sp
    mov [saved_ss],ss
    mov bx,params
    mov ax,4B00h
    int 21h
    jc .failed
    xor ax,ax
.failed:
    cli
    mov ss,[cs:saved_ss]
    mov sp,[cs:saved_sp]
    sti
    push cs
    pop ds
    push cs
    pop es
    cld
    ret

check_parent:
    mov bx,[16h]
    mov cx,256
.next:
    or bx,bx
    jz .clear
    mov es,bx
    mov di,[es:5]
    cmp di,100h
    jb .ancestor
    cmp di,0FFF8h
    ja .ancestor
    cmp byte [es:di],4
    jne .ancestor
    cmp word [es:di+1],'DW'
    jne .ancestor
    cmp word [es:di+3],'ED'
    je .cycle
    cmp word [es:di+3],'E2'
    je .cycle
.ancestor:
    mov ax,[es:16h]
    cmp ax,bx
    je .clear
    mov bx,ax
    loop .next
.cycle:
    push cs
    pop es
    stc
    ret
.clear:
    push cs
    pop es
    clc
    ret

; Locate COMSPEC and the DOS 3+ executable path in our inherited environment.
environment:
    mov ax,[2Ch]
    or ax,ax
    jz .bad
    mov es,ax
    mov [env_source],ax
    xor di,di
.next:
    cmp byte [es:di],0
    je .path
    push di
    mov si,active_key
    mov cx,14
    repe cmpsb
    pop di
    jne .not_active
    jmp fatal_cycle
.not_active:
    push di
    mov si,comspec_key
    mov cx,8
    repe cmpsb
    pop di
    jne .skip
    push di
    add di,8
    mov bx,comspec
    mov cx,255
    call copy_env
    pop di
    jc .bad
.skip:
    cmp byte [es:di],0
    je .skip_done
    inc di
    jnz .skip
    jmp .bad
.skip_done:
    inc di
    jnz .next
    jmp .bad
.path:
    mov [env_end],di
    inc di
    cmp word [es:di],0
    je .bad
    add di,2
    mov bx,overlay
    mov cx,243
    call copy_env
    jc .bad
    mov si,overlay
    mov bx,overlay
.scan:
    lodsb
    or al,al
    jz .replace
    cmp al,'\'
    je .separator
    cmp al,':'
    jne .scan
.separator:
    mov bx,si
    jmp .scan
.replace:
    mov di,bx
    push cs
    pop es
    mov si,overlay_name
    mov cx,12
    rep movsb
    cmp byte [comspec],0
    je .bad
    clc
    ret
.bad:
    push cs
    pop es
    stc
    ret

; COMMAND.COM may relink its PSP ancestry. Pass a private environment marker
; to the external shell as well; do not modify the caller's shared environment.
command_environment:
    cmp word [env_block],0
    jne .ready
    mov ax,[env_source]
    dec ax
    mov es,ax
    mov bx,[es:3]
    cmp bx,4093
    ja .bad
    mov ax,bx
    mov cl,4
    shl ax,cl
    mov [env_bytes],ax
    add bx,2
    mov ah,48h
    int 21h
    jc .bad
    mov [env_block],ax
    mov es,ax
    mov ax,[env_source]
    mov cx,[env_end]
    mov ds,ax
    xor si,si
    xor di,di
    rep movsb
    push cs
    pop ds
    mov si,active_key
    mov cx,14
    rep movsb
    mov si,[env_end]
    mov cx,[env_bytes]
    sub cx,si
    mov ax,[env_source]
    mov ds,ax
    rep movsb
    push cs
    pop ds
.ready:
    push cs
    pop es
    clc
    ret
.bad:
    push cs
    pop es
    stc
    ret

copy_env:
    mov al,[es:di]
    inc di
    mov [bx],al
    inc bx
    or al,al
    jz .done
    loop copy_env
    stc
    ret
.done:
    clc
    ret

hex_word:
    push cx
    push dx
    mov dx,ax
    mov cx,4
.next:
    push cx
    mov cl,4
    rol dx,cl
    pop cx
    mov ax,dx
    and al,15
    add al,'0'
    cmp al,'9'
    jbe .store
    add al,7
.store:
    stosb
    loop .next
    pop dx
    pop cx
    ret

fatal_memory:
    mov dx,msg_memory
    jmp fatal
fatal_cycle:
    mov dx,msg_cycle
    jmp fatal
fatal_directory:
    mov dx,msg_directory
    jmp fatal
fatal_environment:
    mov dx,msg_environment
    jmp fatal
fatal_command:
    mov dx,msg_long_command
    jmp fatal
fatal_exec:
    mov dx,msg_exec
fatal:
    push cs
    pop ds
    call puts
    mov ax,4C01h
    int 21h
puts:
    mov ah,9
    int 21h
    ret

info: db 4,'DWE2'
session: db 12,'00000000.TMP'
command_tail: times 256 db 0
resume_pending: db 0
params: dw 0,80h,0,5Ch,0,6Ch,0
saved_sp: dw 0
saved_ss: dw 0
drive: db 0
directory: db '\'
    times 255 db 0
overlay: times 256 db 0
comspec: times 256 db 0
env_source: dw 0
env_end: dw 0
env_bytes: dw 0
env_block: dw 0
active_key: db 'DWED_ACTIVE=1',0
comspec_key: db 'COMSPEC='
overlay_name: db 'DWEDOVL.EXE',0
msg_memory: db 'DWED: cannot resize launcher memory.',13,10,'$'
msg_cycle: db 'DWED: recursive editor launch refused.',13,10,'$'
msg_directory: db 'DWED: cannot restore working directory.',13,10,'$'
msg_environment: db 'DWED: invalid environment or missing COMSPEC.',13,10,'$'
msg_exec: db 'DWED: cannot execute DWEDOVL.EXE.',13,10,'$'
msg_command: db 'DWED: command execution failed.',13,10,'$'
msg_long_command: db 'DWED: external command is too long.',13,10,'$'
msg_pause: db 13,10,'Press any key to return to the editor.',13,10,'$'
align 16,db 0
    times 256 db 0
stack_top:
resident_end:
