# Monochrome display and real mouse qualification

The editor selects its video-memory segment from the active BIOS text mode.
Mode 7 uses monochrome memory even on a VGA adapter. Color DAC fades and color
retrace polling are bypassed in that mode. The old adapter-based choice wrote
to the wrong segment, and unconditional color retrace polling could prevent
the first screen update. A missing BIOS row-count field falls back to the
legacy text height instead of allocating a single-row screen.

Mode 7 enforces a readable monochrome palette after configuration and command
options are loaded. Normal, bright and reversed text distinguish menus,
selection and status. Unavailable main-menu commands have an explicit `- `
prefix, remain navigable, and do not execute on Enter or their mnemonic.
This avoids relying on color differences or invisible dark text to convey
availability. Color mode retains its configured palette and menu colors.

The parent tests inspect monochrome video memory and attributes while opening
menus, selecting text, copying/pasting, using undo/redo, saving and viewing
About. A negative control with the preceding editor build produces a blank
mode-7 screen. The missing-row-field case exercises the fallback on QEMU VGA;
it does not establish physical MDA or Hercules compatibility.

## Real mouse path

The runtime matrix uses the hash-pinned CuteMouse fixture already identified
in the parent's DOS application manifest. QEMU supplies relative PS/2 motion
and button transitions, and the real driver provides INT 33h services to the
editor. A source-built resident observer records function-3 replies after
calling the original driver; it neither substitutes driver responses nor
injects editor events. Tests adjust relative movement using those observed
positions so driver acceleration does not make fixed motion counts unreliable.

Coverage includes clicking File/Save and Edit/Undo/Redo, dragging across a tab,
right-button clipboard popup cancellation, Cut/Paste, and undo/redo of those
popup commands. Final destination and backup bytes are checked. Color cases
run in LOW and HIGH/UMB, and a monochrome case exercises tab selection and the
clipboard popup with the same real driver.

## Running the gate

From the parent repository, prepare the external fixture and enable the mouse
matrix explicitly:

```sh
python3 tests/prepare_dwed_mouse.py
make test-dwed-qemu DWED_BUILD=dwed/out/build \
  DWED_MOUSE_DRIVER=out/dwed-mouse-fixtures/ctmouse-extracted/ctmouse.exe
```

The preparer verifies the archive against `tests/dos_app_smoke.json` and the
executable against the mouse scenario's pinned digest. Downloads and extracted
binaries stay in the ignored output directory. The ordinary gate includes the
monochrome cases; the real-driver cases require the explicit fixture argument.
Build the editor with `tools/build.py --tests` as described in `BUILD.md`.

`display-mouse-milestone.json` records build hashes, fixture provenance,
negative-control results and the runtime matrix. These tests qualify QEMU VGA
text modes and its emulated PS/2 mouse with this fixture. Additional mouse
drivers, serial mice, physical adapters, other text geometries and legacy CPUs
remain outside this evidence. Safe-save recovery and constrained-memory
qualification remain separate `EDIT-PLAN.md` gates.
