# Open-toolchain build

On Linux x86_64 with Python 3.12 or later and NASM:

```
python3 tools/build.py
```

Add `--tests` to build the DOS regression probes required by the parent
`make test-dwed-qemu` target. These probes are test artifacts, not editor
distribution files.

The command downloads and verifies the compiler archive pinned in
`tools/toolchain.json`, extracts it privately, regenerates the help and compiles
the editor for 8086 DOS. The output directory must be new. Use `--output PATH`
for another clean build and `--archive PATH` to reuse a downloaded archive
offline. Compare the artifact hashes in each output's `build.json` to check
reproducibility. Compiler diagnostics are retained in `compiler.log`.

Copy `DWED.COM`, `DWEDOVL.exe` and `DWED.CFG` to the same DOS directory, then run
`DWED filename`. Help is embedded in the overlay. The NASM version is recorded
in `build.json`; `LAUNCH.ASM` enforces the 8086 instruction set. The launcher
releases unused memory, locates the overlay next to itself and supports the
external-command/session-resume protocol. No bundled EXE/OBJ is a build or
runtime dependency.

This is an intermediate editor build, not a qualified EDIT distribution.
The [save protocol](SAVING.md) protects the
destination against detected write failures, but recovery qualification and
lossless file handling remain release gates; see `EDIT-PLAN.md`.
Current supported input and explicit rejection rules are documented in
[TEXT-FORMAT.md](TEXT-FORMAT.md).
Menu access and its remaining qualification work are described in
[MENUS.md](MENUS.md).

Editor sources and the vendored system2 library are MIT licensed. The vendored
library's original revision and file checksums are in `vendor/system2/UPSTREAM.json`.
The unmodified Free Pascal runtime is under the GNU Library GPL with its
independent-module linking exception; its notices are in `licenses/fpc`.
Corresponding runtime source is available from the versioned source URL in
`tools/toolchain.json`. The compiler itself is a separate build tool.

For a development archive containing EDIT.COM and its runtime notices, use the
[staged package procedure](PACKAGE.md). This is separate from release promotion.
