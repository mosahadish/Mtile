# Mtile — a macOS tiling window manager inspired by Wtile

> **Inspired by [Wtile](https://github.com/HollowThorn/Wtile).** Mtile is the macOS sibling of
> Wtile, the dwm-style tiling window manager for Windows. It started as a port of Wtile's code to
> Swift and keeps Wtile's design: the same layouts, commands, tags, bar and hotkeys, and **the
> same `config.yaml`**. If you know Wtile, you already know Mtile.
>
> Original Wtile (Windows): [HollowThorn/Wtile](https://github.com/HollowThorn/Wtile) · My fork:
> [mosahadish/Wtile](https://github.com/mosahadish/Wtile)

Mtile is a native Swift re-implementation, not a wrapper. Its folders mirror Wtile's `src/Wtile`
one-to-one (`Bar/`, `Commands/`, `Config/`, `Core/`, `Hotkeys/`, `Launcher/`, `Layouts/`), and
the tests in `tests/Mtile.Tests` mirror `tests/Wtile.Tests`, so a fix or feature in one is easy
to carry over to the other.

> **Status:** experimental, in daily use on macOS. **Bugs are expected** — please open an issue
> if you hit one. It used to live inside the Wtile repo and is
> now its own project. `docs/config.sample.yaml` is a copy of Wtile's and must stay identical to it.

## Build & test

Requires macOS 13+ and Xcode 15+ (or a Swift 5.9+ toolchain). From the repo root:

```sh
swift build -c release
swift test
.build/release/Mtile
```

On first launch, macOS asks for the **Accessibility** permission (System Settings → Privacy &
Security → Accessibility). Mtile waits until you grant it. It needs this permission to move and
resize other apps' windows and to read global hotkeys. While it waits, a **Mtile ⚠** menu-bar
item links to the settings pane, and `~/Library/Logs/Mtile.log` names the binary to allow.

### Permission after a rebuild / at login

Started from a terminal, Mtile borrows the terminal's permission. Started at login (the
`launchOnBoot` LaunchAgent), the Mtile binary needs the permission itself. `swift build` signs
ad hoc, so each rebuild gives the binary a new identity: the grant stops matching and macOS also
refuses to `launchctl kickstart` the agent until the next login. Build with
`scripts/build-mtile.sh` instead. It re-signs the binary with a fixed code-signing identity
(`MTILE_SIGN_IDENTITY`, or the first one in your keychain; a self-signed certificate is enough),
so you only have to grant Accessibility once.

## Configuration: one file for both platforms

Mtile reads `~/.config/mtile/config.yaml` (or `$XDG_CONFIG_HOME/mtile/config.yaml`). On first run
it writes the default there. The default is byte-for-byte the same as
[`docs/config.sample.yaml`](docs/config.sample.yaml). You can copy or symlink your
Windows `%APPDATA%\Wtile\config.yaml` there unchanged.

- **Modifier keys.** `general.macosWinKey` sets which Mac key acts as "Win":
  - `option` (default): Win = ⌥ Option, Alt = ⌘ Command. This keeps ⌘-shortcuts (⌘S, ⌘Q,
    ⌘1…) working in every app.
  - `command`: Win = ⌘ Command, Alt = ⌥ Option.
  - Wtile ignores this key.
- **Per-platform overrides.** Any `hotkeys`, `blacklist` or `tagRules` entry can carry a
  `macos:` block. Mtile uses it to replace that entry's fields, and `enabled: false` drops the
  entry on macOS. Wtile ignores `macos:` blocks.

  ```yaml
  - keys: "Win+Shift+T"
    command: spawn
    args: ["wt.exe"]
    macos:
      args: ["open", "-a", "Terminal", "."]
  ```
- **`spawn` targets.** A trailing `.exe` is dropped. If what's left is a path or a command on
  `PATH`, Mtile runs it directly. Otherwise Mtile opens it as an app by name (`open -a`). This
  lets `firefox.exe` launch Firefox.app.
- **Rule matching.** `processName` matches any of the app's names: display name (`Safari`),
  executable name, or bundle ID (`com.apple.Safari`). `className` matches the window's
  Accessibility subrole (e.g. `AXStandardWindow`). All of these are case-insensitive regexes,
  as on Windows.

## Differences from Wtile

| Wtile feature | Mtile |
|---|---|
| `toggle-taskbar` | Hides the Dock instead of the taskbar, and tiling reclaims its space. It turns on Dock auto-hide with a 1000-second reveal delay and restarts the Dock, so the Dock no longer pops up on hover. Your previous Dock settings are saved to `~/Library/Application Support/Mtile/dock-restore.json` and restored when you toggle again or quit Mtile. If Mtile crashes, they're restored on its next toggle or quit. The hidden/shown choice is remembered (`~/Library/Application Support/Mtile/dock-hidden`): quitting still shows the Dock, and the next start hides it again. |
| `app-launcher` | Lists `PATH` executables plus `.app` bundles under `/Applications`, `/System/Applications` and `~/Applications` (instead of Start Menu shortcuts). Picks are started with `open`, so command-line tools run in the default terminal. The `elevated` argument is accepted but has no effect. |
| `hideTitlebars`, focused border, `rememberState` | Ignored. macOS has no public API for stripping other apps' title bars. |
| Bar segments | All of Wtile's segments work, including `cpu`, `memory`, `battery`, `network` and `volume`, with the same `bar.modules` format strings. `memory` is Activity Monitor's "Memory Used" (app + wired + compressed). `volume` follows the current default output device. Mtile also has a `gpu` segment (format `"GPU {0}%"`) that Wtile doesn't. Add it to `bar.segments` to use it. Wtile logs that segment name as unknown and skips it. |
| `bar.notch` (Mtile only) | On a display with a notch, a top bar sits in the menu-bar strip beside the notch, at the strip's height (`bar.height` is ignored there). The window title stops at the notch's left edge. Set `notch: false` to keep the bar below the strip. |
| Hidden tags | Windows on hidden tags are parked off-screen at a display corner (the AeroSpace approach), not minimised. |
| `launchOnBoot: user`/`admin` | Both start Mtile at login. From an `.app` bundle this registers a login item via `SMAppService`. A bare binary (e.g. `.build/release/Mtile`) instead writes `~/Library/LaunchAgents/com.hollowthorn.mtile.plist` pointing at itself, logging to `~/Library/Logs/Mtile.log`; `off` removes it. The binary started at login needs its own Accessibility permission, which macOS may drop after a rebuild. |

One macOS Space per display is assumed. Turn off "Displays have separate Spaces" if windows end
up on the wrong display.

## Credits

Mtile exists because of **[Wtile](https://github.com/HollowThorn/Wtile)**. Wtile's design, config
format, command set and layout maths (pixel-identical, including banker's rounding) are the
blueprint Mtile follows. I keep a fork of it at
[mosahadish/Wtile](https://github.com/mosahadish/Wtile). Wtile in turn is inspired by [dwm](https://dwm.suckless.org/).
