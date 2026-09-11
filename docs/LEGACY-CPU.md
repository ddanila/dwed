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
these checks. The separate 86Box/real-BIOS gate remains open.
