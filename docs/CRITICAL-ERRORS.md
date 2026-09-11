# DOS critical errors and protected media

The checked reader and writer initialize a shared INT 24h handler. It returns
Fail without calling DOS, allocating memory or using a Pascal stack frame.
This lets DOS return an error to the checked I/O operation instead of entering
COMMAND.COM's Abort/Retry/Fail prompt over the editor screen. The normal editor
error and pending-cleanup flows retain the unsaved document and owned handles.

The handler belongs to the editor process. An ExitProc hook restores the
previous vector and chains the prior exit procedure. The QEMU tests snapshot
the vector before launching DWED and after it exits to check that the handler
does not remain installed in the parent command processor.

The parent media-readonly cases expose a separate floppy as write protected at
the QEMU device boundary. Its file has ordinary writable attributes. Tests read
and edit it, attempt a save, dismiss the editor error, and either discard the
unsaved buffer or Save As to the writable hard disk. They compare the entire
protected image before and after, check the original and backup, and verify
exact bytes after Save As. The previous editor reaches the DOS critical-error
prompt and fails this interaction test.

Generated evidence on the parent DOS and Microsoft DOS reference is in
`critical-errors-milestone.json`. The test uses emulated write-protected media;
it does not qualify physical media removal, failing controllers, torn writes,
or recovery-record discovery from every read-only device type.
