# Component Cleaner — User Acceptance Tests

Manual UAT pack for the unused-component finder and single-component check.

**Baseline for this pass**

| # | Decision | Value |
|---|----------|-------|
| Q1 | Build form under test | Dev run (`zig build run` + Vite) |
| Q2 | Acceptance audience | External Vue devs (first-run clarity + errors in scope) |
| Q3 | Heuristic limits | Known-limitations — documented mis-report is the *expected* result |
| Q4 | Modes in scope | Both — unused-finder + single-check |

**Standing assumptions:** macOS host with Zig 0.16 + Node 20.19/22.12+ + the
zero-native CLI on `PATH`; system WebView (not CEF); test data is the bundled
`test-fixtures/` plus a few added trigger files for the edge cases.

---

## Pre-flight (automated, against the real scan code)

Backend logic behind UAT-02–07 was exercised against `test-fixtures` before the
manual pass:

- UAT-02/03 ✓ — 4 components; OldBanner + UnusedWidget flagged; BaseButton
  (Pascal+import) and BaseCard (kebab) not flagged.
- UAT-05/06 ✓ — `BaseButton` → used; `NopeNotHere` → unused.
- UAT-07 — surfaced a defect (single-check matched the prefix `BaseButt`);
  `findUsage` was switched to whole-word matching and a regression test added.
- UAT-04 — premise corrected: `app/` holds component files, so it is not an
  empty state.

GUI-only steps (UAT-00/01/08/09) remain manual — they need native window and
file-dialog interaction.

---

## Personas

- **Maya — Primary cleaner.** Mid-level Vue dev, large SFC codebase, wants dead
  components found before a refactor. Cares about a correct unused list and
  clear paths. Drives the happy paths.
- **Devon — First-timer.** Tech-curious, not a Vue expert, evaluating the tool
  cold. Drives discoverability, empty/invalid input, error clarity.
- **Sam — Skeptical reviewer.** Senior dev who verifies before deleting. Drives
  correctness and the known-limitation edge cases; treats false reports as a
  trust risk.

---

## Scenarios

Format: **Pre** = preconditions, **Steps**, **Expect**. Concrete data is
`test-fixtures/`.

### Setup

**UAT-00 — Launch**
- Pre: repo cloned; Zig 0.16, Node 22, zero-native on `PATH`.
- Steps: run `zig build run` (with node + zig on `PATH`).
- Expect: native window "Component Cleaner" opens, dark theme, header + two
  "Choose…" rows + a disabled "Find unused" button.

### Unused-finder (Maya)

**UAT-01 — Folder pickers populate**
- Steps: 1) Choose… on Components folder → `test-fixtures/components`.
  2) Choose… on Source root → `test-fixtures`.
- Expect: each row shows the chosen absolute path; "Find unused" enables.

**UAT-02 — Scan finds the dead components**
- Pre: UAT-01 done.
- Steps: click **Find unused**.
- Expect: brief "Scanning…"; then "4 components scanned", badge "2 unused";
  list shows **OldBanner** and **UnusedWidget** with paths; BaseButton/BaseCard
  absent.

**UAT-03 — Kebab + Pascal both count as used**
- Expect (within UAT-02): BaseButton (Pascal tag + import) and BaseCard (kebab
  `<base-card>`) are *not* listed unused. Confirms both matchers.

**UAT-04 — Empty-state (no component files)**
- Pre: Components folder = a directory with no `.vue/.tsx/.jsx` (e.g. `assets`);
  Source root = `test-fixtures`.
- Steps: Find unused.
- Expect: "0 components scanned" and the empty-state message, no list, no crash.
- Note: pointing Components at `test-fixtures/app` instead yields **2**
  components (App.vue, HomePage.vue *are* component files), both flagged unused
  — not an empty state. Use a component-less folder for the empty case.

### Single-check (Maya)

**UAT-05 — Known component reported used**
- Pre: Source root = `test-fixtures`.
- Steps: type `BaseButton`, click **Check** (or Enter).
- Expect: "Used — first reference in …" with a real file path.

**UAT-06 — Absent component reported unused**
- Steps: type `NopeNotHere`, Check.
- Expect: "Appears unused — safe to remove."

**UAT-07 — Whole-word precision**
- Pre: Source root = `test-fixtures`.
- Steps: Check `BaseButt` (a prefix of BaseButton).
- Expect: "Appears unused" — a prefix does **not** match (no false positive).
- Note: single-check shares the unused-finder's whole-word matcher; enforced by
  the `findUsage matches whole words only` regression test. (Earlier the
  single-check used substring matching and wrongly reported this as used — fixed.)

### First-run / error handling (Devon)

**UAT-08 — Buttons gated until inputs ready**
- Steps: fresh launch, do nothing.
- Expect: "Find unused" disabled until both folders chosen; "Check" disabled
  until a name is typed *and* a source root is chosen.

**UAT-09 — Cancel the folder dialog**
- Steps: click Choose…, then cancel the OS dialog.
- Expect: prior path unchanged, no error line, app responsive.

**UAT-10 — Nonexistent / unreadable source root**
- Pre: set an invalid dir (pick a folder, delete it before scanning; or a path
  with no read permission).
- Steps: Find unused / Check.
- Expect: red error line `handler_failed: …` (or similar `code: message`); app
  stays usable. Acceptance: a readable error, not a silent hang or crash.

### Known limitations — mis-report is the EXPECTED result (Sam)

Each needs a trigger file. Create it, then scan with
Components = `test-fixtures/components`, Source root = `test-fixtures`.

**UAT-11 — Alias import (expected false "unused")**
- Setup: add `test-fixtures/components/AliasOnly.vue` (any simple component);
  add `test-fixtures/app/UsesAlias.vue` with
  `import Aliased from "../components/AliasOnly.vue"` and `<Aliased/>`.
- Expect: **AliasOnly listed as unused** (local name `Aliased` ≠ file name).
  PASS = matches documented limitation; logged as a v2.5 target.

**UAT-12 — Dynamic `:is` (expected miss)**
- Setup: reference a dead component only via `<component :is="'OldBanner'" />`.
- Expect: **OldBanner still listed unused**. PASS = documented miss.

**UAT-13 — String/comment false "used"**
- Setup: in an app file add a comment `<!-- unused-widget retired -->` or a CSS
  class `unused-widget`.
- Expect: **UnusedWidget reported used** (drops off the list). PASS = documented
  false positive.

---

## Success criteria

**Acceptance gate (all must hold):**
1. UAT-00–UAT-09 pass exactly as specified.
2. UAT-02/03 correctness: exactly OldBanner + UnusedWidget flagged;
   BaseButton/BaseCard never flagged.
3. UAT-05/06/07: single-check verdicts correct; prefix non-match holds.
4. UAT-10: every failure surfaces a readable `code: message`, never a hang or
   crash.
5. UAT-11/12/13: behavior **matches the README Limitations section**. Behavior
   that differs from what's documented is a fail.

**Quality bars**
- No unhandled promise rejection or blank result on any path.
- Scan of `test-fixtures` returns visibly fast (<1s); no UI freeze beyond the
  progress state.
- Paths shown are absolute and copy-readable.

**Out of scope this pass:** packaged `.app`, Linux, CEF, transitive-usage
analysis.
