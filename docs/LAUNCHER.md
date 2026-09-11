# Source-built launcher

`SRC/LAUNCH.ASM` is an 8086 COM program assembled by NASM. It replaces the
historical C-- binary and implements the protocol used by `DWEDLNCH.PAS`.
The launcher and overlay must come from the same build: the new `DWE2`
signature distinguishes the explicit session-resume protocol from the old one.

The resident launcher shrinks its DOS allocation before EXEC, preserves its
stack across EXEC, finds `DWEDOVL.EXE` beside its own executable and forwards
the original DOS command tail. It uses the exact `COMSPEC=` environment entry
for external commands, restores the original drive and absolute working
directory, waits for a key and restarts the overlay with the saved session.
Commands exceeding the DOS command-tail limit are rejected.

Recursive launch protection checks ancestor PSP signatures and a
`DWED_ACTIVE=1` entry in a private environment passed to the external shell.
COMMAND.COM can change its PSP ancestry, so the environment check is needed
as well. The caller's environment is not modified.

The launcher supplies a BIOS-clock/PSP-derived session filename and a separate
resume flag. On initial entry the overlay skips existing names instead of
loading an unrelated stale file. Session restore is permitted only on a
launcher-requested restart. This is not full crash recovery: context-file I/O
errors and concurrent creation after the name check still need qualification.

The parent QEMU suite exercises ordinary and failed saves, external commands,
drive/directory restoration, recursive-launch refusal, session resume and
launching from outside the executable directory. Legacy CPU and low-memory
qualification and startup/EXEC failure injection remain release gates.
