# QuitProtect

A macOS utility that prevents accidental ⌘Q quits. Choose between double-press or hold-to-quit modes. Lives in your menu bar, stays out of your way.

## Requirements

- macOS 14 (Sonoma) or later

## Installation

Two formats on every release — both signed and notarised, pick whichever suits:

- **[Installer (`.pkg`)](https://github.com/PerpetualBeta/QuitProtect/releases/latest/download/QuitProtect.pkg)** — recommended for first-time installs. Double-click to run; macOS Installer places the app in `/Applications` without quarantine or App Translocation.
- **[Download (`.zip`)](https://github.com/PerpetualBeta/QuitProtect/releases/latest)** — unzip and drag `QuitProtect.app` to your Applications folder.

After installation:

1. Launch QuitProtect — a power icon appears in your menu bar
2. Grant Accessibility permission when prompted

## How It Works

QuitProtect intercepts ⌘Q before it reaches the frontmost application and requires you to confirm the quit with a deliberate action. A single accidental keypress won't close anything.

There are two protection modes:

### Double-press ⌘Q (default)

The first ⌘Q is consumed silently. Press ⌘Q again within the configured interval to actually quit. If you don't press again, nothing happens — the quit is blocked.

| Interval | Description |
|----------|-------------|
| 0.3s | Fast — requires quick double-tap |
| **0.4s** (default) | Balanced |
| 0.5s | Relaxed |
| 0.75s | Generous window |

### Hold ⌘Q

Hold ⌘Q for the configured duration to quit. Anything shorter is blocked.

| Duration | Description |
|----------|-------------|
| 0.5s | Quick hold |
| **1.0s** (default) | Balanced |
| 1.5s | Deliberate |
| 2.0s | Very deliberate |

## Menu Bar Icon

The power icon in the menu bar reflects the protection state:

- **Outlined**: Protection is inactive (waiting for permission or disabled)
- **Filled**: Protection is active

Click the icon to access:

- **Protection Active** — toggle protection on/off
- **Mode** — current quit mode
- **Quits blocked** — running count of prevented accidental quits
- **Settings** — configure mode, timing, and permissions
- **About** — version info and update check

## Settings

### Quit Mode

Switch between double-press and hold-to-quit using the radio buttons. The timing option below updates to match the selected mode.

### General

- **Accessibility** — permission status and grant button
- **Menu bar icon pill** — optional grey background for stronger contrast on busy or wallpaper-tinted menu bars (off by default)
- **Launch at Login** — start automatically when you log in
- **Auto-update** — check for new versions on a configurable schedule with optional automatic installation

## Permissions

### Accessibility (required)

Needed to intercept keyboard events before they reach applications.

- Prompted automatically on first launch
- Grant in: **System Settings → Privacy & Security → Accessibility**
- Without this, QuitProtect cannot intercept ⌘Q

## Self-exclusion

QuitProtect does not protect itself — you can always quit QuitProtect with a normal ⌘Q.

## Building from Source

QuitProtect uses Swift Package Manager. No Xcode project is required.

```bash
cd ~/Desktop/"Jorvik Software"/QuitProtect
./build.sh
open _BuildOutput/QuitProtect.app
```

The build script runs `swift build -c release`, then assembles the `.app` bundle in `_BuildOutput/` with the executable, icon, and Info.plist.

## How It Works (Technical)

QuitProtect installs a CGEvent tap at the head of the keyboard event pipeline. It monitors keyDown, keyUp, and flagsChanged events, filtering for ⌘Q specifically (keyCode 12 with only the Command modifier).

- **Double-press mode**: the first ⌘Q keyDown is consumed. A timer starts. If a second ⌘Q arrives within the interval, it passes through. If the timer expires, the quit is counted as blocked.
- **Hold mode**: ⌘Q keyDown events are consumed. Key repeat events are monitored to measure hold duration. Once the configured duration is reached, a synthetic ⌘Q is posted to actually quit the app. Releasing early counts as a blocked quit.

State is properly reset regardless of key release order (⌘ released before Q, Q released before ⌘, or simultaneous release).

## Troubleshooting

### ⌘Q isn't being intercepted

Make sure QuitProtect has **Accessibility** permission in System Settings → Privacy & Security → Accessibility. You may need to remove and re-add it if you've rebuilt the app.

### The menu bar icon stays outlined

The engine is waiting for Accessibility permission. Check System Settings → Privacy & Security → Accessibility and ensure QuitProtect is listed and enabled.

### Keys feel stuck after ⌘Q

This was fixed in v1.0 — the engine now resets state correctly when ⌘ is released before Q. If you experience this, ensure you're running the latest version.

---

QuitProtect is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
