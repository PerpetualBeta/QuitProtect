# QuitProtect

A macOS utility that prevents accidental `command` `Q` quits. Choose between double-press or hold-to-quit modes. Lives in your menu bar, stays out of your way.

## Requirements

- macOS 14 (Sonoma) or later

## Installation

Two formats on every release — both signed and notarised, pick whichever suits:

- **[Installer (`.pkg`)](https://github.com/PerpetualBeta/QuitProtect/releases/latest/download/QuitProtect.pkg)** — recommended for first-time installs. Double-click to run; macOS Installer places the app in `/Applications` without quarantine or App Translocation.
- **[Download (`.zip`)](https://github.com/PerpetualBeta/QuitProtect/releases/latest)** — unzip and drag `QuitProtect.app` to your Applications folder.

Or install it with [Homebrew](https://brew.sh):

```sh
brew install --cask perpetualbeta/jorvik/quitprotect
```

After installation:

1. Launch QuitProtect — a power icon appears in your menu bar
2. Grant Accessibility permission when prompted

## How It Works

QuitProtect intercepts `command` `Q` before it reaches the frontmost application and requires you to confirm the quit with a deliberate action. A single accidental keypress won't close anything.

There are two protection modes:

### Double-press `command` `Q` (default)

The first `command` `Q` is consumed silently. Press `command` `Q` again within the configured interval to actually quit. If you don't press again, nothing happens — the quit is blocked.

Optionally, enable **Show quit guidance** in Settings to display a non-activating overlay after the first press. The overlay reminds you to press `command` `Q` again without taking focus away from the app you were using.

| Interval | Description |
|----------|-------------|
| 0.3s | Fast — requires quick double-tap |
| **0.4s** (default) | Balanced |
| 0.5s | Relaxed |
| 0.75s | Generous window |

### Hold `command` `Q`

Hold `command` `Q` for the configured duration to quit. Anything shorter is blocked.

When **Show quit guidance** is enabled, the overlay appears on the initial press and dismisses when the gesture is completed or cancelled.

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
- **Show quit guidance** — a small overlay on the first `command` `Q` telling you what to do next, off by default. It does not take focus from the app you were using, and it disappears the moment the gesture completes or lapses rather than lingering
- **Show icon in menu bar** — hides the power icon in the menu bar while QuitProtect keeps running in the background, still protecting against accidental quits. Your choice persists across launches, including login auto-start. *Shown only on macOS 14–15 — on macOS 26 (Tahoe) and later, use System Settings → Menu Bar, which provides this natively.*
- **Menu bar icon pill** — optional grey background for stronger contrast on busy or wallpaper-tinted menu bars (off by default)
- **Launch at Login** — start automatically when you log in

If you've hidden the menu bar icon and want it back, simply re-open QuitProtect from your Applications folder — it reappears immediately.

Auto-updates are handled by Sparkle. Use the **Check for Updates…** entry in the right-click menu to check on demand; Sparkle's prompt offers an "Automatically download and install updates in the future" checkbox the first time an update is available.

## Languages

QuitProtect follows your macOS language preference. English and **Simplified Chinese** (简体中文) are
included; every other language, Traditional Chinese among them, falls back to English.

Simplified Chinese was contributed by [RSS1102](https://github.com/RSS1102).

## Permissions

### Accessibility (required)

Needed to intercept keyboard events before they reach applications.

- Prompted automatically on first launch
- Grant in: **System Settings → Privacy & Security → Accessibility**
- Without this, QuitProtect cannot intercept `command` `Q`

## Self-exclusion

QuitProtect does not protect itself — you can always quit QuitProtect with a normal `command` `Q`.

## Quitting

Click the power icon in the menu bar and choose **Quit QuitProtect**. If you've hidden that icon, re-open QuitProtect from your Applications folder first to bring it back, then quit from the menu.

## Building from Source

QuitProtect uses Swift Package Manager. No Xcode project is required.

The build is driven by the shared [`release.mk`](https://github.com/PerpetualBeta/jorvik-release) Make include, so `jorvik-release` has to be checked out **beside this repo** — the Makefile looks for it at `../jorvik-release/`. macOS ships GNU Make 3.81 as `make`, which is too old, so `gmake` comes from [Homebrew](https://brew.sh).

```bash
brew install make   # GNU Make 4+, if you do not already have gmake
git clone https://github.com/PerpetualBeta/jorvik-release.git
git clone https://github.com/PerpetualBeta/QuitProtect.git
cd QuitProtect
gmake build
open .build/QuitProtect.app
```

## How It Works (Technical)

QuitProtect installs a CGEvent tap at the head of the keyboard event pipeline. It monitors keyDown, keyUp, and flagsChanged events, filtering for `command` `Q` specifically (keyCode 12 with only the Command modifier).

- **Double-press mode**: the first `command` `Q` keyDown is consumed. A timer starts. If a second `command` `Q` arrives within the interval, it passes through. If the timer expires, the quit is counted as blocked.
- **Hold mode**: `command` `Q` keyDown events are consumed. Key repeat events are monitored to measure hold duration. Once the configured duration is reached, a synthetic `command` `Q` is posted to actually quit the app. Releasing early counts as a blocked quit.

State is properly reset regardless of key release order (`command` released before `Q`, `Q` released before `command`, or simultaneous release).

## Troubleshooting

### `command` `Q` isn't being intercepted

Make sure QuitProtect has **Accessibility** permission in System Settings → Privacy & Security → Accessibility. You may need to remove and re-add it if you've rebuilt the app.

### The menu bar icon stays outlined

The engine is waiting for Accessibility permission. Check System Settings → Privacy & Security → Accessibility and ensure QuitProtect is listed and enabled.

### Keys feel stuck after `command` `Q`

This was fixed in v1.0 — the engine now resets state correctly when `command` is released before `Q`. If you experience this, ensure you're running the latest version.

## Acknowledgements

[RSS1102](https://github.com/RSS1102) contributed the Simplified Chinese localisation and the quit guidance
overlay.

The localisation went further than translation: the string handling moved into the shared JorvikKit toolkit,
so every other Jorvik app can now be localised the same way. That part was unasked-for and is the more
valuable of the two.

The overlay is worth a word too. Its first revision padded the on-screen time with tuned constants; the
version that shipped removed them, because once the engine reports when a gesture resolves there is nothing
left to guess — only a single minimum readable duration, which is derived from legibility rather than taste.
Diagnosing *why* a constant exists before naming it is the harder half, and rarer.

---

QuitProtect is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
