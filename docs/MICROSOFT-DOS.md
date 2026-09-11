# Microsoft DOS reference qualification

The parent DWED QEMU harness accepts an explicit boot floppy and matching
memory-manager files. It copies the boot image privately for every case; the
editor, test probes and scratch hard disk are otherwise the same as in the
parent-DOS tests. The run records the boot image, driver and editor artifact
hashes and captures the guest's VER output.

With local Microsoft DOS installation media and its expanded matching system
files, prepare a boot-only copy from the parent repository:

```sh
python3 tests/prepare_dwed_reference.py \
  --image .reference/msdos622/msdos622disk1.IMA \
  --system-files .reference/msdos622/files \
  --output out/dwed-reference
python3 tests/test_dwed_qemu.py \
  --build dwed/out/build \
  --boot-image out/dwed-reference/boot.img \
  --boot-files .reference/msdos622/files \
  --case edit-low --case edit-high
```

The preparation command requires a new output directory. It verifies that the
image's core files match the expanded files, preserves the boot sectors and
core, and removes other files only from its private copy. HIMEM and EMM386 are
copied from the supplied system-files directory into each test guest. Commercial
media and extracted binaries remain local; only fingerprints and results belong
in Git.

`microsoft-dos-milestone.json` records the qualified cases on Microsoft DOS 6.22,
including text bytes, memory exhaustion, automatic indentation, undo, save faults
and restart recovery. LOW and HIGH/UMB use the corresponding CONFIG.SYS entries;
this matrix is functional qualification, not a boot-speed or memory-usage
measurement. The broader editor release gates and untested hardware remain open.
