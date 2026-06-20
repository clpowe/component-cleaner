# Component Cleaner

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Zig](https://img.shields.io/badge/Zig-0.16-f7a41d?logo=zig&logoColor=white)
![Vue](https://img.shields.io/badge/Vue-3-42b883?logo=vuedotjs&logoColor=white)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)

A small native desktop app that finds **unused Vue components** so you can
delete dead code with confidence. The scanning core is written in Zig; the UI
is a Vue frontend hosted in a native window via
[zero-native](https://zero-native.dev).

---

## What it does

Point it at your components folder and your source tree. It reads every source
file once and reports which components are never referenced.

Two modes:

- **Unused finder** — enumerate every component definition (`.vue/.tsx/.jsx`),
  scan the source tree, and list the components that nothing references.
- **Single check** — ask whether one named component is used anywhere, and
  where it first appears.

Matching is **whole-word** and Vue-aware: it detects both PascalCase tags /
imports (`<BaseButton>`, `import BaseButton`) and kebab-case tags
(`<base-button>`), so `BaseButton` is not confused with `BaseButtonGroup`. A
component's own definition file is excluded so it can't count as its own usage.

---

## Requirements

- **macOS** (the supported target for the zero-native beta).
- **Zig 0.16.0+** — the code uses the 0.16 `std.Io` filesystem API.
- **Node.js 20.19+ or 22.12+** — required by Vite 8 for the frontend.
- **[zero-native](https://zero-native.dev) CLI** on your `PATH` (native shell,
  dev server, packager). The build points at a local zero-native install;
  override the location with `-Dzero-native-path=/path/to/zero-native`.

---

## Run it

```bash
git clone https://github.com/clpowe/component-cleaner.git
cd component-cleaner

# Make sure zig 0.16, node 20.19+/22.12+, and the zero-native CLI are on PATH.
zig build run
```

A native window opens. Pick your **components folder** and **source root**,
then scan. To try it against the bundled fixtures, choose
`test-fixtures/components` and `test-fixtures` — `OldBanner` and
`UnusedWidget` are flagged as dead.

### Tests

```bash
zig build test --summary all
```

### Package a macOS app bundle

```bash
zig build package -Doptimize=ReleaseFast
# -> zig-out/package/component-cleaner-0.1.0-macos-ReleaseFast.app
```

> Use `zig build package`, not a bare `zero-native package` — the build step
> supplies the compiled binary and built frontend assets. Running the CLI
> directly produces an empty, unlaunchable stub.

---

## Architecture

```
src/scan.zig    Pure scanning core — no bridge imports, unit-tested in isolation.
                findUsage() and findUnused() + the whole-word/kebab matchers.
src/main.zig    Bridge handlers (native.scanComponent, native.scanUnused),
                JSON (de)serialization, App wiring.
src/runner.zig  zero-native runtime setup.
frontend/       Vue 3 + Vite UI; talks to the backend over window.zero.invoke.
test-fixtures/  components/ (incl. dead ones) + app/ consumers for tests.
```

The Zig core stays dependency-free and testable; the bridge layer is the only
part that touches zero-native. The frontend calls handlers by name and renders
the JSON result.

---

## Roadmap

- **v2.5 — import-path resolution.** Resolve `import X from "./Foo.vue"`
  specifiers to files and mark the imported component used. Fixes the most
  important correctness gap: components referenced only under an **aliased**
  import name are currently mis-reported as dead.
- **v3 — tree-sitter.** Parse SFC templates and scripts for tag- and
  import-accurate analysis, eliminating false positives from CSS classes,
  comments, and string literals. Higher cost (C bindings + Vue multi-grammar),
  so gated behind real demand.

---

## Limitations

This is a fast heuristic scanner, not a full resolver. Known gaps:

- **Aliased imports** (`import Btn from './BaseButton.vue'; <Btn/>`) are not
  detected — the component may be reported as unused even though it is used.
  **Review before deleting.** (Addressed by v2.5.)
- **Dynamic usage** (`<component :is="name">`, names built from strings) is not
  detected.
- **String/comment matches** can make a dead component look used (a CSS class
  `base-button`, a comment mentioning the name).
- **No transitive analysis** — a component used only by another *unused*
  component still counts as used.
- Self-exclusion is path-suffix based and assumes the components folder lives
  under the scanned source root.

---

## License

[MIT](LICENSE) © 2026 Christopher Powe
