# Component Cleaner — Build Tracker

Native macOS app (zero-native + Vue frontend + Zig backend) that scans a
components directory and reports whether a given component is used anywhere.

This file tracks **where we are** and the **decisions/gotchas**. It holds no
code — code is written by hand against the notes below.

---

## Environment

- **Zig**: 0.16.0 target. Original plan was written against an older Zig; 0.16
  reworked the filesystem + I/O APIs (see migration notes).
- **zig binary**: `~/.zvm/0.16.0/zig`. The `mise` shim is broken right now
  (`mise ERROR No version is set for shim: zig`). Either prefix commands with
  `PATH="$HOME/.zvm/0.16.0:$PATH"`, or fix once with `mise use -g zig@0.16.0`.
- **Node/npm**: Vite 8 requires Node **20.19+ / 22.12+**. The shell default
  (`nvm`) is 18.11.0, which fails with `CustomEvent is not defined`. v22.22.3 is
  installed — either `nvm alias default 22.22.3`, or launch with
  `PATH="$HOME/.nvm/versions/node/v22.22.3/bin:$PATH"`. `zig build run` spawns
  `npm run dev` (app.zon `dev.command`) as a subprocess, so it inherits the
  launching shell's PATH — node must be on it.
- Test: `zig build test --summary all`. Run app: `zig build run`.
  Full launch line:
  `PATH="$HOME/.nvm/versions/node/v22.22.3/bin:$HOME/.zvm/0.16.0:$PATH" zig build run`

---

## Zig 0.16 migration notes

Every API the original plan used that changed. Verified against 0.16 std source
and against zero-native's own source (which already uses the new forms).

- Filesystem moved under `std.Io.Dir`: `std.fs.cwd()` → `std.Io.Dir.cwd()`.
- `openDir`, `openFile`, `close`, and `walker.next` all take an `io: std.Io`
  argument now.
- `file.readToEndAlloc` is gone. Read a whole file by getting a reader
  (`file.reader(io, buf)`) and calling `.interface.allocRemaining(allocator,
  limit)` with a `std.Io.Limit` (e.g. `std.Io.Limit.limited(max)`).
- `zero_native.bridge.writeJsonStringValue` no longer returns an error union —
  drop the `try`.
- Tests need an `io`. Use `std.testing.io` (the default test runner
  initializes `testing.io_instance`, confirmed for 0.16.0).

**Where `io` comes from at runtime:** `std.process.Init` carries one
(`init.io`), and `runner.zig` already threads it everywhere.
`bridge.Invocation` does **not** carry an `io`, so the handler reads it from the
`App` struct, which is populated from `init.io` in `main()`.

---

## Conventions to keep

- `defer` the cleanup right next to each acquire (`open*` / `init` /
  `allocPrint`).
- `findUsage` frees all its own scratch; caller owns only the returned path
  slice.
- Bridge handler uses a per-call `ArenaAllocator`; `arena.deinit()` reclaims
  everything on return, so the body never frees individually.
- Tests pass `std.testing.allocator` (leak-checked) + `std.testing.io`.
- `scan.zig` stays pure (no bridge imports) so it unit-tests in isolation.

---

## Progress

| Step | What | Status |
|------|------|--------|
| 0 | Prereqs (zig 0.16, node) | ✅ done |
| 1 | Scaffold + smoke test (`zig build run`) | ✅ done |
| 2 | `src/scan.zig` pure scan logic | ✅ done — ported to 0.16 I/O |
| 3 | `test-fixtures/` + `zig build test` green | ✅ done (4/4 pass) |
| 4 | `runScan` + `ScanRequest`/`ScanResult` in `main.zig` | ✅ done |
| 5 | Extend `App` struct (io, allocator, handlers) | ✅ done |
| 6 | `App.bridge()` dispatcher + command policy | ✅ done |
| 7 | Wire dispatcher into `runWithOptions` in `main()` | ✅ done — exe + tests compile |
| 8 | app.zon allow-list | ⚠️ likely N/A — see note |
| 9 | Vue UI (`frontend/src/App.vue`) | ✅ done — frontend builds (node 22) |
| 10 | End-to-end run | ✅ done — "Used — first hit: BaseButton.vue" |
| 11 | Package (optional) | ✅ done — `zig build package -Doptimize=ReleaseFast` |

---

## Step 5 — extend `App` (TODO)

Add three fields to the existing `App` struct in `main.zig`: `io: std.Io`,
`allocator: std.mem.Allocator`, and a `handlers` array sized to the number of
custom commands (1). Existing `app()`/`source()` methods stay unchanged. Update
`scanComponent` to pull `io` and `allocator` off `self` and pass them to
`runScan`.

---

## Step 6 — dispatcher + command policy (TODO)

Verified zero-native types (`src/bridge/root.zig`):
- `Handler` = `{ name, context, invoke_fn }`
- `Dispatcher` = `{ policy, registry }`
- `Registry` = `{ handlers }`
- `Policy` = `{ enabled, permissions, commands }`
- `CommandPolicy` = `{ name, permissions, origins }` (`permissions`/`origins`
  default to empty, so a name-only entry is valid)

Add a `command_policies` array with one `CommandPolicy` named
`native.scanComponent`, plus an `App.bridge()` method that fills
`self.handlers` (name `native.scanComponent`, `context = self`, `invoke_fn =
scanComponent`) and returns a `Dispatcher` with `policy.enabled = true`,
`policy.commands = &command_policies`, and `registry.handlers =
&self.handlers`.

---

## Step 7 — wire into `main()` (TODO)

`runner.RunOptions` already exposes `bridge: ?BridgeDispatcher = null` and
`builtin_bridge: BridgePolicy = .{}`. In `main()`:
- Build `App` with `.io = init.io` and `.allocator = std.heap.smp_allocator`
  (thread-safe; arena frees per call so the backing choice is low-stakes).
- `App` must outlive the run and `bridge()` mutates `self.handlers`, so call it
  on a pointer to the long-lived `app`.
- Pass `.bridge = app.bridge()` in the `RunOptions`.

**Dialogs require `builtin_bridge` enabled + the command listed.** (This
reverses an earlier wrong note.) In `runtime/root.zig`
`allowsBuiltinBridgeCommand` (line 623): if `builtin_bridge.enabled` is false,
the origin fallback only applies to window/webview commands gated by
`uses_window_permission` — **dialogs are always denied** in that path
(`!uses_window_permission → return false`). Symptom when missing:
`permission_denied: Dialog API is not permitted`.

Fix — in `main()` options:
- add a `builtin_command_policies` array containing a `BridgeCommandPolicy`
  named `zero-native.dialog.openFile` (empty permissions/origins ⇒ any allowed
  origin), and
- pass `.builtin_bridge = .{ .enabled = true, .commands = &builtin_command_policies }`.

`Policy.allows` (bridge/root.zig:59): enabled + name match + empty `origins`
⇒ allowed. List `saveFile`/`showMessage` only if used.

Builtin dialog command names (verified): `zero-native.dialog.openFile`,
`zero-native.dialog.saveFile`, `zero-native.dialog.showMessage`.

---

## Step 8 — app.zon allow-list (likely N/A)

Current `app.zon` has `.permissions = .{}` and no per-command bridge section,
and there's no example bridge-command entry to copy. In this scaffold version
the in-code dispatcher `Policy` (Step 6) gates `native.scanComponent` at
runtime. Treat Step 8 as a no-op unless a runtime rejection points elsewhere
(see Step 10).

---

## Step 9 — Vue UI (TODO)

Replace `frontend/src/App.vue` with the scan UI:
- Inputs: component `name`, chosen `dir`; a "Choose folder…" button, a "Scan"
  button (disabled until both set), result line, error line.
- Folder picker: `window.zero.invoke("zero-native.dialog.openFile", { title,
  allowDirectories: true, allowMultiple: false })`, read
  `res.paths?.[0]` (absolute path — sidesteps the packaged-app working-dir
  problem).
- Scan: `window.zero.invoke("native.scanComponent", { componentName, scanDir
  })`; the resolved value is the `{ used, file }` object. On throw, show
  `${e.code}: ${e.message}`.
- Confirm `frontend/src/main.js` mounts `App.vue` (scaffold default does).

---

## Step 10 — run end to end (TODO)

`zig build run`, pick a real components folder, scan one used and one unused
component. Error-code map:
- `unknown_command` → custom dispatcher not wired (Step 6/7) or name typo.
- `handler_failed` → directory failed to open (bad path / permissions).
- dialog rejected → origin not in `dev_origins` / `app.zon` allowed_origins.

---

## Step 11 — package

Use the build step, **not** raw `zero-native package`:

```
PATH="$HOME/.vite-plus/bin:$HOME/.nvm/versions/node/v22.22.3/bin:$HOME/.zvm/0.16.0:$PATH" \
  zig build package -Doptimize=ReleaseFast
```

`build.zig:119` wires `zero-native package` with the two args raw invocation
omits: `--binary <compiled exe>` (via `package.addFileArg(exe.getEmittedBin())`)
and `--assets frontend/dist`. Raw `zero-native package --target macos` produces
an **empty stub** (`MacOS/README.txt` = "No app binary was supplied") that macOS
reports as "damaged or incomplete". Output:
`zig-out/package/component-cleaner-0.1.0-macos-ReleaseFast.app` (~912K, binary
embedded, ad-hoc signed, no quarantine).

PATH needs three things on it: `~/.vite-plus/bin` (the `zero-native` CLI),
node 22, zig 0.16.

Constraints still true: responses stay well under the 12 KiB result-buffer cap
(only matters if you later return a full match list); the scan runs
synchronously on the UI thread — fine for a components folder, would briefly
block on a huge tree.

---

## v2 — unused-component finder

New handler `native.scanUnused(componentsDir, scanDir)`. `scan.findUnused`
enumerates component def files (`.vue/.tsx/.jsx`), scans the source tree once,
marks each used/unused, returns the unused list as `{total, unused:[{name,path}]}`.
Matching upgraded to whole-word (`containsWord` + `isIdentChar`/`isKebabChar`)
so `BaseButton` no longer matches `BaseButtonGroup`, plus kebab-tag detection
(`<base-button>`) and self-definition-file exclusion. Frontend: two folder
pickers (components dir + source root) and an unused-list table. 7/7 tests pass.

Limits: no transitive graph (a component used only by another *unused*
component still counts used); self-exclude is path-suffix based (assumes
components dir is under the source root); dynamic `<component :is>` not detected.

## Gotchas learned (v2)

- **`'/'` vs `"/"`**: `std.mem.lastIndexOfScalar(u8, path, '/')` needs a `u8`
  char literal. `"/"` is a string → `error: expected type 'u8', found
  '*const [1:0]u8'`.
- **Test build only analyzes code reachable from a test.** `baseName` (reached
  only via `findUnused`→`runScanUnused`→`main`) was never compiled by `zig
  build test`, so its bug only surfaced in `zig build` (the exe). Fix: a test
  that actually calls `findUnused` now forces analysis — run **both** `zig
  build test` and `zig build` after backend changes.
- **`max_result_bytes` is 1 MiB**, not 12 KiB (the original plan was wrong) —
  array responses fit fine.
- Functions taking a raw allocator must free their own scratch to stay
  leak-clean in tests; `findUnused` frees its `kebabs` list even though
  production runs it under an arena.

## Watch-list

- `std.testing.io` depends on the default test runner initializing
  `testing.io_instance` (true for 0.16.0). A custom test runner would need a
  hand-built `std.Io.Threaded`.
- `smp_allocator` chosen for `App.allocator`; swap to `std.heap.DebugAllocator`
  during dev for leak detection on the handler path.
- `std.json.parseFromSlice` call shape is the one version-sensitive line in
  `runScan` — re-check if you bump Zig.
