<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="DynIsl icon">
</p>

<h1 align="center">DynIsl</h1>

<p align="center"><a href="https://github.com/caganerdal/DynIsl/actions/workflows/build.yml"><img src="https://github.com/caganerdal/DynIsl/actions/workflows/build.yml/badge.svg" alt="Build"></a> <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a> <img src="https://img.shields.io/badge/macOS-14%2B-black.svg" alt="macOS 14+"></p>

<p align="center">An island for the MacBook notch, plus a full system dashboard.<br>Native Swift and SwiftUI. Everything runs on your Mac.</p>

<p align="center"><strong>English</strong> · <a href="README.tr.md">Türkçe</a></p>

<p align="center">
  <img src="docs/images/island.png" width="820" alt="DynIsl island expanded under the notch">
</p>

<p align="center">
  <img src="docs/images/dashboard.png" width="820" alt="DynIsl system dashboard">
</p>

---

## Features

### The island
- **Music:** Spotify and Apple Music with artwork, progress, play/pause/skip, volume, shuffle and repeat; favorite and dislike in Apple Music. Smooth transitions between songs and a glow in the artwork's color.
- **Volume and brightness HUD:** replaces the macOS HUD (optional) with five styles: Classic, Minimal, Ring, Segmented and Liquid. Step size of 2, 5 or 10 percent.
- **Live activities:** charging and battery, AirPods connection and battery warnings, calendar meetings with a countdown, Focus mode, download progress, screenshot preview, internet down / back, rain alerts and system alerts.
- **Tabs:** music, calendar, shelf and AirDrop, clipboard history, system usage and battery analytics.
- **Shelf with conversions:** drop files on the island; convert images to JPG, shrink them, merge images and PDFs into one PDF, or compress PDFs, all on-device.
- **Presentation mode:** silences the island and hides desktop icons while Keynote or PowerPoint is presenting or the screen is mirrored.
- **Accent color:** the macOS accent, the current song's color, or your own.
- **Island cat:** sleeps next to the notch, dances to music, gets tired on low battery and sweats when the Mac is under load.
- **Timer**, and an `island` command for your own notifications from the terminal (including Claude Code hooks).

### System dashboard
- CPU (per core), GPU, memory, storage, network and Wi-Fi, battery health, displays, Bluetooth devices and processes, with search and Quit / Force Quit.
- Internet speed test using macOS's built-in `networkQuality`.
- Desktop tidy-up: sorts desktop files into folders by type and month, with undo.
- File conversion: images to JPG, shrinking, one PDF from many files, PDF compression.
- Downloads clean-up: lists installers, archives and other downloads you haven't opened in a long time; moves the ones you pick to the Trash, with undo.

### Menu bar
- Live CPU and RAM usage.
- Keep awake: prevents sleep indefinitely or for 30 minutes to 4 hours.

## Requirements

- macOS 14 Sonoma or later
- Xcode or the Xcode Command Line Tools (Swift 5.9+)
- A MacBook with a notch is recommended; on other displays the island sits in the middle of the menu bar.

## Install

```bash
git clone https://github.com/caganerdal/DynIsl.git
cd DynIsl
./build-app.sh install
```

`build-app.sh` builds the app into `build/DynIsl.app` and, with `install`, copies it to `/Applications`. It signs with your **Apple Development** certificate if you have one. Otherwise, on first install it adds a local signing certificate named "DynIsl Local" to your keychain so macOS permissions survive updates. macOS asks for your keychain password on each build so `codesign` can use that key; choosing "Allow" instead of "Always Allow" is safer.

Build only:

```bash
./build-app.sh
```

## Updating

The app checks GitHub for a new release once a day and tells you on the island. Use the **Update** button in Settings › General › Updates, or run:

```bash
cd DynIsl
git pull
./build-app.sh install
```

## Permissions

Every permission is optional. Without it, only the related feature is off.

| Permission | Used for |
|---|---|
| Automation (Spotify, Music) | Showing and controlling the current song |
| Calendars | Upcoming meetings |
| Location | Weather (rounded to about 1 km) |
| Bluetooth | AirPods connection and battery activities |
| Accessibility | Catching volume and brightness keys to show the island's HUD (only media and brightness keys) |
| Full Disk Access | Reading the active Focus mode (macOS keeps it in a protected folder) |

## Terminal command

Installing adds `~/.local/bin/island`. If that folder isn't in your `PATH`, add `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc`.

```bash
island "Build finished"
island -s "Tests passed"
island -e "Deploy failed"
island run npm test
```

Only your own `island` command can post to the island: each notification carries a per-user key that the app checks.

## Privacy

- Everything runs on your Mac; analytics, measurements and history never leave it.
- The app only connects to the internet for weather ([Open-Meteo](https://open-meteo.com), with a rounded location), Spotify artwork, a daily update check (GitHub, reads the latest version number only; can be turned off) and speed tests you start (Apple servers).
- Clipboard history stays on this Mac: text in memory, images in a temporary cache folder only your account can read. Copies from password managers are skipped, and the history is cleared when the screen locks, when the app quits and when it starts.
- The island is hidden from screen sharing and recordings by default.

## Development

```bash
swift build
swift test
```

The code is split into `@MainActor` services (music, battery, calendar, system sampling and so on) and SwiftUI views that observe only the services they show. CI builds the app and runs the tests on every push. See [CONTRIBUTING.md](CONTRIBUTING.md).

Text lives in `Resources/Localizable.xcstrings` (Turkish source, English translation). After adding text, run `./Tools/localize.sh`.

## Notes

- Brightness control loads macOS's private `DisplayServices` framework at runtime, so the app isn't suitable for the App Store. If it fails, the brightness keys fall back to macOS.
- The app is signed with the hardened runtime.

## License

[MIT](LICENSE)

---

Apple, Mac, MacBook and macOS are trademarks of Apple Inc. This project is not affiliated with or endorsed by Apple. Spotify is a trademark of Spotify AB.
