# Extended-memory transfers

`ems_try_copy`, `xms_try_copy` and `exms_try_copy` return zero on success and a
nonzero status on failure. EMS returns the driver status byte. XMS returns the
driver error byte after a failed call, using a nonzero fallback if a driver
reports failure without an error byte. Dispatch without a memory manager also
returns a nonzero fallback. A driver may have partially modified a destination
before reporting failure; these APIs do not promise atomic transfer.

The legacy copy procedures remain source-compatible wrappers which discard the
status. EMS transfers now request a copy rather than an exchange, so copying to
extended memory does not replace the conventional source with old page contents.
Reading a page also preserves the extended source for subsequent reads.

The test shims exercise copy semantics, ordinary and SXMS descriptor fields,
wide page offsets, both directions, and driver failure returns. Separate probes
use the actual configured HIMEM and EMM386 drivers, verify patterned round trips
and source preservation, and require a transfer through a freed handle to fail.
The parent runner enables EMS explicitly for the real EMS cases. See
[transfer-status-milestone.json](transfer-status-milestone.json) for executable
identity, driver hashes, results and the old-implementation negative control.

## Pending cache integration

`EXCACHE` and its `SYSTEM2` consumers still use the legacy wrappers and can mark
failed transfers as successful. They must migrate together. In particular, a
failed write-cache read cannot become an ordinary cache miss followed by a read
of stale disk data. Dirty data must retain an owner until successful writeback;
failed or partial replacement must not destroy the only cached copy. Cache item
metadata must be published only after successful transfer.

The checked APIs and source-preserving EMS copy are prerequisites for this
work, not evidence of end-to-end cache failure safety. Optional extended-memory
stores and their file-I/O error propagation remain release qualification work.
