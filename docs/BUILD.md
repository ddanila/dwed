# Open-toolchain build

On Linux x86_64 with Python 3.12 or later:

```
python3 tools/build.py
```

The command downloads and verifies the compiler archive pinned in
`tools/toolchain.json`, extracts it privately, regenerates the help and compiles
the editor for 8086 DOS. The output directory must be new. Use `--output PATH`
for another clean build and `--archive PATH` to reuse a downloaded archive
offline. Compare the artifact hashes in each output's `build.json` to check
reproducibility. Compiler diagnostics are retained in `compiler.log`.

This is an intermediate overlay build, not a complete EDIT distribution.
The historical launcher is still required to run it. Bundled EXE/OBJ files are
not inputs to this build command. Safe saving and lossless file handling remain
release gates; see `EDIT-PLAN.md` before using it for real documents.

Editor sources and the vendored system2 library are MIT licensed. The vendored
library's original revision and file checksums are in `vendor/system2/UPSTREAM.json`.
The unmodified Free Pascal runtime is under the GNU Library GPL with its
independent-module linking exception; its notices are in `licenses/fpc`.
Corresponding runtime source is available from the versioned source URL in
`tools/toolchain.json`. The compiler itself is a separate build tool.
