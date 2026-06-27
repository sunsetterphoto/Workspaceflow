# Workspaceflow

**macOS-style dynamic workspaces for KDE Plasma 6 (Wayland).**

Maximize a window — it moves onto its own, automatically created workspace right
next to your desktop. Restore or close it — that workspace disappears again.
Just like "Spaces" on the Mac, but for KWin.

Workspaceflow is a pure KWin script: no daemon, no third-party dependencies,
no `sudo`.

---

## Behavior

- **Maximizing** a window → a new virtual desktop is created directly to the
  right of the permanent desktop, the window moves there, and focus follows.
  Order: `Desktop │ newest │ … │ oldest`.
- **Restoring** (un-maximizing) **or closing** → the workspace dissolves, the
  window returns to the permanent desktop, and the remaining workspaces shift
  over.
- The **permanent desktop always stays on the far left** and is never removed.

Non-maximized windows all live together on the permanent desktop — as usual.

## Gestures

| Gesture (touchpad) | Action |
|---|---|
| **3 fingers left/right** | Move between the desktop and workspaces |
| **4 fingers up** | Open the overview of all workspaces |

> **Why 4 fingers for the overview?** The finger count of these gestures is
> **hard-wired into the KWin 6 compositor** and cannot be changed via
> configuration: switch desktops = 3 fingers horizontal, overview = 4 fingers
> up. Workspaceflow uses these built-in gestures unchanged (which is also close
> to macOS, where many system gestures are 4-finger). `install.sh` only makes
> sure the overview effect is enabled (`overviewEnabled=true`), so the 4-finger
> gesture works without any extra step.
>
> Remapping it to 3 fingers up would only be possible through an external
> gesture daemon (e.g. `libinput-gestures`) and was deliberately left out to
> keep Workspaceflow dependency-free and low-maintenance.

Alternatively, **`Meta`+`W`** opens the overview from the keyboard.

## Requirements

- KDE Plasma 6 / KWin 6 on **Wayland** (developed and tested on 6.7)
- Standard KDE tools: `kpackagetool6`, `kwriteconfig6`/`kreadconfig6`,
  `qdbus6` (or `qdbus-qt6` as a fallback)

No other dependencies.

## Installation

```bash
git clone https://github.com/sunsetterphoto/Workspaceflow
cd Workspaceflow
./install.sh
```

No `sudo` required, idempotent (safe to run repeatedly). `install.sh`:

1. installs the KWin script package into `~/.local/share/kwin/scripts/workspaceflow`,
2. enables it in `~/.config/kwinrc` (`workspaceflowEnabled=true`),
3. ensures the overview effect is on (`overviewEnabled=true`),
4. reloads the KWin configuration (active immediately, no logout needed),
5. sets up the optional auto-update timer (see below).

### Recommended: a single base desktop

You get the cleanest "macOS flow" with **one** permanent virtual desktop — then
every maximize creates exactly one workspace next to it. Configure it under
*System Settings → Window Management → Virtual Desktops* (set the count to 1).
Multiple fixed desktops work too, but the dynamic workspaces then interleave
between them.

## Uninstallation

```bash
./uninstall.sh
```

Disables the script and removes the package and the auto-update timer. Your other
KDE settings are left untouched.

## Configuration — ignore list

Window classes that should **not** get their own workspace (e.g. apps you'd
rather keep on the main desktop) go into `~/.config/kwinrc`:

```ini
[Script-workspaceflow]
IgnoreClasses=firefox,Xmessage
```

Comma- or newline-separated. Then reconfigure KWin:

```bash
qdbus6 org.kde.KWin /KWin reconfigure   # or qdbus-qt6
```

Find an app's window class with `qdbus6 org.kde.KWin /KWin queryWindowInfo`
(then click the window) or via `xprop WM_CLASS`.

> **Note:** A graphical settings UI is included (`contents/config/`), but the
> binding of the KDE settings dialog to the correct kwinrc section is not yet
> fully verified. The direct kwinrc method above is the reliable one.

## Persistence & updates

Workspaceflow lives entirely in user space
(`~/.local/share/kwin/scripts/` and `~/.config/kwinrc`). **System and Plasma
updates do not overwrite these files.** The 4-finger gesture it relies on is
KWin's built-in default and is preserved across updates.

Should an update ever disable the overview effect, the next run of `install.sh`
(`overviewEnabled=true`) restores it — the auto-update timer does this
automatically.

## Auto-update

`install.sh` sets up a systemd **user** timer that keeps Workspaceflow current
and re-applies its settings in a self-healing way:

- **Schedule:** daily (`OnCalendar=daily`, `Persistent=true`,
  `RandomizedDelaySec=1h`)
- **Action:** `git pull --ff-only` in the project directory, then `install.sh`
- **Requirement:** the repo checked out at
  `~/Schreibtisch/PublicGitHub/Workspaceflow` (path baked into the systemd unit)

The units are **copied** into `~/.config/systemd/user/` (not symlinked — for
Fedora/SELinux compatibility). Disable anytime with
`systemctl --user disable --now workspaceflow-update.timer`.

## Known limitations

- **Multi-monitor:** Virtual desktops in Plasma span all monitors; a per-monitor
  space (like macOS in "Displays have separate Spaces" mode) is not possible
  with the KWin API.
- **Windows that start maximized** don't fire a `maximizedChanged` signal and so
  don't get their own workspace. Restore once and re-maximize to create it.
  (Deliberate v0.1 decision.)

## Development & testing

Tests run **exclusively in an isolated, nested KWin session** with its own D-Bus
and its own `XDG_CONFIG_HOME` — the running live session is never touched:

```bash
./test/task-9-e2e.sh          # full end-to-end scenario
./test/invariant-desktop0.sh  # permanent desktop stays stable
```

The scripts launch KWin via
`dbus-run-session -- kwin_wayland --virtual --xwayland …` and check the behavior
against the real script log.

## License

MIT — see [LICENSE](LICENSE).
