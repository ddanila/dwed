# Legacy CPU runtime checks

The parent `test_dwed_legacy_dosbox.py` boots a private copy of DOS in DOSBox-X
with explicit 8086 and 286 CPU models. The guest checks PUSH SP semantics and,
for the 286, real-mode FLAGS behavior before running the editor probes. This
prevents a silently selected newer CPU from being treated as legacy evidence.

The same source-built artifacts used by the QEMU tests run text/cursor and
indentation checks, undo-storage transactions, save-failure injection and
repeated document-memory exhaustion. A resident keyboard driver then waits for
the actual editor screen before typing, saving and exiting through BIOS input.
The host checks the saved bytes, original backup and completed AUTOEXEC marker.

From the parent repository:

```sh
python3 tests/test_dwed_legacy_dosbox.py --build dwed/out/build
```

`--cpu` selects one model for diagnosis. Runs use DOS LOW and unrestricted
emulator speed. Private boot and disk images, probe logs and emulator output
remain under the printed run directory. Generated artifact fingerprints and
results are in `legacy-cpu-milestone.json`.

## Qualification boundary

This is instruction-model and functional smoke evidence, not real-BIOS
acceptance or historical timing. DOSBox-X labels its 8086 model experimental.
The generated report records the emulator binary fingerprint. IBM AT/XT ROMs,
physical machines, old display adapters and HMA behavior are not established by
these checks. See the separate IBM AT BIOS check below; broader platform qualification remains open.


## IBM AT BIOS smoke check

The parent `test_dwed_286_86box.py` installs the verified development EDIT
package on a private boot floppy and starts an emulated IBM AT with IBM BIOS
and VGA ROMs. It checks CPU identity and DOS HMA residency, runs the text and
indentation probe, and exercises the packaged EDIT.COM through BIOS keyboard
input. The host requires exact saved and backup bytes and the probe log both
before and after the editor. A guest routine flushes DOS writes, signals the
host through the serial port and halts; the host then stops its private emulator.
This avoids relying on emulator-specific guest shutdown support.

With a local 86Box installation and the official ROM set:

```sh
xvfb-run -a python3 tests/test_dwed_286_86box.py \
  --build dwed/out/build --package dwed/out/package \
  --emulator /path/to/86Box --roms /path/to/roms --mode low
```

On a graphical desktop, omit `xvfb-run`. Extracted Linux AppImages may use
`AppRun` as the executable. The runner defaults to Qt xcb; `--qt-platform`
selects another installed backend. `--timeout` controls the per-machine limit.
ROMs and emulator binaries remain local, outside version control.

The generated `ibmat-bios-milestone.json` records the validated LOW-mode run,
package and core fingerprints, official download provenance and guest results.
The runner also supports `--mode high`, but that mode is not established by
this report. This is BIOS and functional evidence under emulation, not physical
hardware acceptance, boot-speed measurement or coverage of all editor commands.
