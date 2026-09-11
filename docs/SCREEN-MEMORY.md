# Screen snapshots under memory pressure

Screen saves check the largest free heap block before allocating. A refusal
leaves the snapshot stack untouched. Callers cancel the requested window or
command; error reporting falls back to a temporary top-row notice that uses
stack space and restores the previous row after Enter or Escape. The startup
screen buffer also checks available contiguous memory before allocation.

Menu redraws and the DOS console view reuse their existing snapshots. They do
not release and reacquire a buffer on every redraw or console roundtrip.

The optional MEMTEST /SCREEN probe fragments the heap while retaining a dirty
document and nested screen snapshots. It verifies repeated allocation refusal,
menu cancellation through the actual notice, snapshot restoration, unchanged
heap accounting, document preservation and retry after memory is released.
Command-line arguments are parsed before recording the heap baseline, because
[FPC lazily allocates its retained argument array](https://github.com/fpc/FPCSource/blob/release_3_2_2/rtl/msdos/system.pp)
on the first ParamCount or ParamStr call. The subsequent reclamation checks compare exact free-heap totals.

The parent QEMU harness dismisses the notice and checks the probe result before
performing a normal edit and save. Separate console scenarios repeatedly leave
and return to an unsaved document before saving it. Qualification details,
build fingerprints and selected UI regressions are in
[screen-memory-milestone.json](screen-memory-milestone.json).

This qualifies screen snapshot refusal on the tested DOS configurations. It
does not establish a minimum startup memory requirement or safe failure of every
clipboard, help, handler or alternate-store allocation. The development package
must be rebuilt and requalified before these changes ship as EDIT.
