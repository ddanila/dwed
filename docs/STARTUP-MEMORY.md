# Controlled startup memory refusal

Startup screen, syntax, help, keyboard-handler and clipboard allocations use a
shared checked allocator. It reports which resource cannot fit and returns a
DOS memory-error exit code. This helper is reserved for initialization before
opening or recovering documents; runtime command failures must retain the
interactive session.

The legacy buffered reader and writer check their buffer allocations before
opening a file. Refusal leaves the file closed and reports a memory error.
Optional XMS caches decline creation before allocating an XMS block when the
conventional-memory descriptor cannot fit. Configuration loading turns a buffer
allocation error into a controlled startup refusal.

If the console snapshot cannot fit, or the initial document cannot be created
and no document is already open, the editor exits with a diagnostic instead of
waiting in a memory-error dialog. Failure to load another document while a
previous document exists retains the normal interactive error path.

The parent startup-memory harness uses a test-only DOS TSR to leave a specified
contiguous free block, then launches the normal source-built editor. It checks
both controlled refusal and successful editing, retains diagnostics and exit
status, and verifies the source and backup remain unchanged after refusal.
LOW and HIGH/UMB use private images and matching memory managers. The tested
budgets, observed outcomes, reproduction builds and selected UI regressions are
in [startup-memory-milestone.json](startup-memory-milestone.json).

The measured boundary applies to this executable, DOS image, environment,
configuration and small edit/save scenario. It is not a minimum physical RAM
specification or qualification of every command at that boundary. Fragmentation,
other backing stores and displays, additional files, undo history and different
configurations affect available memory. Runtime screen and list allocation
refusal are covered in [SCREEN-MEMORY.md](SCREEN-MEMORY.md) and
[LIST-MEMORY.md](LIST-MEMORY.md). Distribution qualification remains open.
