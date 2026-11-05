# Mtile on macOS: setup guide for Copilot

> **Note:** written when Mtile still lived inside the Wtile repo (branch `mh/macos-port`). It's
> now its own project at the repo root here; the Wtile-side rules below no longer apply.

> **For the Copilot agent:** read this whole file, then work through the steps in order. You
> may run commands and fix code. **Never `git push`.** Commit locally only, on branch
> `mh/macos-port`.

## Background

- This repo is **Wtile**, a dwm-style tiling window manager for Windows (C#, `src/Wtile`).
  Branch `mh/macos-port` adds **Mtile**, a native Swift port for macOS:
  - `Package.swift` at the repo root
  - the app in `src/Mtile`
  - XCTest tests in `tests/Mtile.Tests`
- The Swift code was written on Windows and has **never been compiled**. Expect a few compile
  errors on the first build. Fixing them is the main job.
- Read `README.md` before starting. It covers the design, config sharing and the
  known differences from Wtile.

## Ground rules

1. **Never push.** Don't change remotes or open PRs.
2. **Keep the structure.** `src/Mtile` mirrors `src/Wtile` folder for folder, and
   `tests/Mtile.Tests` mirrors `tests/Wtile.Tests`. Don't move or rename files or folders.
3. **Keep the config shared.** `docs/config.sample.yaml` is read unchanged by both Wtile and
   Mtile:
   - Don't rename any keys.
   - macOS-only behaviour goes in `macos:` blocks or `general.macosWinKey`.
   - If you edit the sample, regenerate `src/Mtile/Config/DefaultConfig.swift`. It embeds the
     sample verbatim, and the test `testDefaultConfigMatchesSampleFile` checks that they match.
4. **Make the smallest fix for each compile error.** Don't rewrite working logic just to make
   an error go away. If a test fails, first work out whether the test or the code is wrong.
   The layout maths must stay pixel-identical to Wtile, including banker's rounding.
5. **Don't touch the Windows side** (`src/Wtile`, `tests/Wtile.Tests`, `Wtile.slnx`). It can't
   be built on a Mac.
6. **Commit after each milestone**, using the `Co-authored-by: Copilot` trailer.

## Step 1: Prepare the environment

```sh
xcode-select -p || xcode-select --install   # Command Line Tools (or a full Xcode 15+)
swift --version                              # needs Swift 5.9 or newer
sw_vers                                      # needs macOS 13 or newer
git status && git branch --show-current      # should print mh/macos-port, clean tree
```

If `swift --version` fails, or reports a version older than 5.9:
- install or update Xcode from the App Store, then
- run `sudo xcode-select -s /Applications/Xcode.app` and
- run `sudo xcodebuild -license accept`.

## Step 2: Build and fix compile errors

```sh
swift package resolve        # fetches Yams (internet needed once)
swift build 2>&1 | tee /tmp/mtile-build.log
```

Repeat until the build is clean. Each time:
1. Read the **first** errors in the log; later ones are often caused by earlier ones.
2. Fix them.
3. Rebuild.

Likely trouble spots:
- the `#if os(macOS)` files: `Core/WindowInspector.swift`, `Core/WindowEventTracker.swift`,
  `Hotkeys/HotkeyManager.swift`, `Bar/BarWindow.swift`, `Core/TrayIcon.swift`,
  `Core/LaunchOnBoot.swift`, `Program.swift`
- AX/CG API signatures, CGFloat vs Double conversions, and `@convention(c)` callbacks
- main-actor isolation warnings (warnings are fine)

If `swift test` can't import the executable target, split the package into two targets:
- a library target `MtileCore` holding everything except `Program.swift`;
- a thin executable target `Mtile` holding only `Program.swift`.

Keep the folder paths unchanged when you do this. Use `exclude:`/`sources:` in `Package.swift`
rather than moving files.

Commit once the build is clean: `Mtile: fix compile errors found on first macOS build`.

## Step 3: Run the tests

```sh
swift test 2>&1 | tee /tmp/mtile-test.log
```

There are about 140 tests:
- layouts, config, hotkeys, commands, bar renderer, process launcher;
- `WindowManagerTests`, which runs against a fake backend.

Fix the failures, following ground rule 4, then commit.

## Step 4: First live run (needs the human)

```sh
swift build -c release
.build/release/Mtile
```

**Grant Accessibility access:**
- macOS will prompt for it. If it doesn't, open **System Settings → Privacy & Security →
  Accessibility** and enable the app Mtile was launched from (Terminal, iTerm, or VS Code).
  When run from a terminal, that terminal app is the one that gets the permission.
- Mtile waits until access is granted, showing a **Mtile ⚠** menu-bar item meanwhile.
- If hotkeys don't fire, also check **Privacy & Security → Input Monitoring** for the same app.
- For `launchOnBoot`, the binary itself needs the permission, and a plain `swift build` changes
  its identity on every build. Build with `scripts/build-mtile.sh` (re-signs with a stable
  identity) and grant Accessibility to `.build/release/Mtile` once.

**Config file:**
- The config lives at `~/.config/mtile/config.yaml`. Mtile creates it on first run, as a copy
  of `docs/config.sample.yaml`.
- A Windows `%APPDATA%\Wtile\config.yaml` can be copied there unchanged.

**Default keys:** "Win" = ⌥ Option. Set `general.macosWinKey: command` to use ⌘ instead.

| Keys | Action |
|---|---|
| ⌥J / ⌥K | Focus next / previous window |
| ⌥1 … ⌥9 | View tag 1–9 |
| ⌥⇧1 … ⌥⇧9 | Move window to tag 1–9 |
| ⌥⇧T | Open Terminal |
| ⌥Q | Close window |
| ⌥⇧B | Toggle bar |
| ⌥⇧R | Reload config |
| ⌥⇧C | Open config |
| **⌥⇧Q** | **Quit Mtile** (restores every window to the screen) |

**Emergency exit:** press Ctrl+C in the terminal running Mtile. This also restores parked
windows.

## Step 5: Live test checklist

Open three or four normal windows (Safari, Terminal, TextEdit) and check each item:

- [ ] Windows tile master-stack under the bar, and the bar shows tags, layout symbol, title and
      clock.
- [ ] Opening and closing windows re-tiles them.
- [ ] Focus keys move focus, and the bar title follows.
- [ ] Switching tags parks the hidden windows off-screen at a corner, and they come back when
      you switch back.
- [ ] Moving a window to another tag hides it and leaves the rest re-tiled.
- [ ] Layout switching works (see `hotkeys:` in the config for the layout keys).
- [ ] Clicking a tag in the bar switches to it.
- [ ] The tray / menu-bar icon menu works.
- [ ] Reload picks up an edited config, such as a changed `borderGap`.
- [ ] With an external display, both displays get a bar and windows tile per display.
- [ ] Quitting with ⌥⇧Q, and separately with Ctrl+C, puts every window back on screen.

For each failure:
1. Record the symptom.
2. Find the cause; the terminal shows Mtile's log output.
3. Make the fix and add a test where the logic is testable (the WindowManager logic is,
   through `tests/Mtile.Tests/Support/FakeBackend.swift`).
4. Rebuild, re-run `swift test`, and live-test again.
5. Commit.

**Always quit Mtile before rebuilding**, and make sure you're running the new binary.

## Step 6: Report back

Summarise:
- which compile and test fixes were needed;
- which checklist items pass and which fail;
- any open problems.

Leave everything committed on `mh/macos-port`, unpushed. The human will bring the branch back
to the Windows machine.

To bundle the work for transfer, create a git bundle. The human can fetch from it on Windows.

```sh
git bundle create ~/Desktop/mtile-mac.bundle 4eb5a59..mh/macos-port
```
