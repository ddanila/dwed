# Staged EDIT package

The packager creates an EDIT development archive from an existing source build:

```sh
python3 tools/package.py --build out/build --output out/package
```

The output directory must be new. Each required executable/configuration file
must match the build manifest before any output is created. The result contains
a DOS file tree, EDIT.ZIP, and a host-side package.json with input and payload
fingerprints. ZIP entries have fixed timestamps and ordering and use stored
compression for straightforward DOS extractor compatibility.

The launcher is installed as EDIT.COM, with DWEDOVL.EXE and DWED.CFG alongside
it. Help remains embedded in the overlay. Runtime lookup still uses these
companion names. README.TXT explains installation and development status.
SOURCES.TXT identifies source projects and the pinned runtime source version.
The LICENSES directory includes the editor and system2 MIT texts and both Free
Pascal runtime license documents. License line endings are normalized for DOS;
license text is otherwise preserved. No compiler, test probe, proprietary
binary or historical bundled executable is included.

From the parent repository, `make package-dwed` uses DWED_BUILD and DWED_PACKAGE.
`make test-dwed-package` checks deterministic archives, DOS names, license text,
refusal of changed input artifacts, and preservation of existing output.
For actual command-name qualification:

```sh
python3 tests/test_dwed_qemu.py --build dwed/out/build \
  --package dwed/out/package --case edit-low --case edit-high
```

The harness installs the complete staged file tree and invokes EDIT.COM. It
verifies package-file fingerprints before running. Restart recovery and external
command tests also use the selected launcher name. Generated package and runtime
evidence is in `package-milestone.json`.

This staging command does not add EDIT to the parent release image or mark the
editor qualified. Safe resolution of retained recovery generations, remaining
allocation and platform checks, and final distribution acceptance still apply.
