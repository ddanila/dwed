{ SPDX-License-Identifier: MIT }
program keytest;
uses dos,event,kminput;
var output:text; e:TEvent; regs:registers; tests:integer;
procedure expect(key:word; flags:byte; expected:word);
begin
        inc(tests);
        if keyboard_modifiers(key,flags)<>expected then begin
                writeln(output,'FAILED ',tests,' actual ',keyboard_modifiers(key,flags),' expected ',expected);
                close(output); halt(1);
        end;
end;
begin
        assign(output,'A:\KEY.LOG'); rewrite(output);
        tests:=0;
        expect($75E0,0,key_ctrl); { released Ctrl-End }
        expect($7700,0,key_ctrl); { released Ctrl-Home }
        expect($1F13,0,key_ctrl); { released Ctrl-S }
        expect($2E03,0,key_ctrl); { released Ctrl-C }
        expect($5500,0,key_shift); { released Shift-F2 }
        expect($6800,0,key_alt); { released Alt-F1 }
        expect($2100,0,key_alt); { released Alt-F }
        expect($4FE0,0,0); { plain End }
        expect($0F09,0,0); { Tab is not Ctrl-I }
        expect($1C0D,0,0); { Enter is not Ctrl-M }
        expect($0E08,0,0); { Backspace is not Ctrl-H }
        expect($2166,$60,0); { lock keys are not modifiers }
        expect($1F13,2,key_ctrl or key_shift);
        { Exercise the real BIOS queue and wait_event after modifiers release. }
        kbd_reset;
        fillchar(regs,sizeof(regs),0); regs.ah:=5; regs.cx:=$75E0;
        intr($16,regs);
        if regs.al<>0 then begin writeln(output,'BIOS queue full'); close(output); halt(2) end;
        wait_event(e);
        if (e.etype<>KEYBOARD) or (e.scancode<>$75) or
           (e.ctrl_keys<>key_ctrl) then begin
                writeln(output,'BIOS event ',e.scancode,' ',e.ctrl_keys); close(output); halt(3);
        end;
        close(output);
        assign(output,'A:\KEY.OK'); rewrite(output);
        writeln(output,'KEYBOARD PASS ',tests); close(output);
end.
