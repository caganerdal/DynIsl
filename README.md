<p align="center">
  <img src="Resources/AppIcon-1024.png" width="112" alt="DynIsl icon">
</p>

<h1 align="center">DynIsl</h1>

<p align="center"><strong>Your notch has a job now.</strong><br>
A live island for the MacBook notch, plus a full system dashboard. Free, open source, native Swift.</p>

<p align="center">
  <a href="https://caganerdal.github.io/DynIsl/"><img src="https://img.shields.io/badge/Download_for_Mac-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for Mac"></a>
</p>

<p align="center">
  <a href="https://github.com/caganerdal/DynIsl/releases/latest"><img src="https://img.shields.io/github/v/release/caganerdal/DynIsl?label=release&color=30d158" alt="Latest release"></a>
  <a href="https://github.com/caganerdal/DynIsl/actions/workflows/build.yml"><img src="https://github.com/caganerdal/DynIsl/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

<p align="center"><a href="https://caganerdal.github.io/DynIsl/">Website</a> · <strong>English</strong> · <a href="README.tr.md">Türkçe</a></p>

<p align="center">
  <img src="docs/images/island.png" width="820" alt="DynIsl island expanded under the notch, showing battery history">
</p>

## What it does

Hover or click the notch and the island opens. It grows only as much as it needs and goes back when you leave.

| | |
|---|---|
| **Music** | Spotify and Apple Music with artwork, progress, controls, volume, shuffle and repeat. A glow in the cover's color. |
| **Meetings** | A countdown before calendar events and a join button for Zoom, Meet, Teams and Webex. |
| **Battery and AirPods** | Charging, health, cycles, a 24-hour graph, and AirPods battery when they connect. |
| **AI usage** | Your Claude 5-hour and weekly limits with reset times, Claude Code tokens by day, project and model, and alerts near the limit. |
| **Shelf** | Drop files on the island, AirDrop them, or convert images to JPG, shrink them, merge into one PDF, compress PDFs. All on-device. |
| **Keep awake** | For a while, until a time, while an app is open, even with the lid closed. Stops itself on low battery. |
| **Volume and brightness** | Five HUD styles that replace the system one: Classic, Minimal, Ring, Segmented, Liquid. |
| **Clipboard history** | Recent copies, kept on your Mac. Password managers are skipped; history clears when the screen locks. |
| **Live activities** | Downloads, screenshots, Focus mode, internet down and back, rain alerts, system warnings, a timer, and a cat that naps by the notch. |

<p align="center">
  <img src="docs/images/dashboard.png" width="820" alt="DynIsl system dashboard overview">
</p>

**System dashboard:** processor (per core), graphics, memory, storage, network and Wi-Fi, battery health, displays, Bluetooth and processes with Quit and Force Quit. Plus a speed test, desktop tidy-up by type and month, Downloads clean-up and file conversion, all with undo.

## Install

**Download** the latest DMG from the [website](https://caganerdal.github.io/DynIsl/) or [Releases](https://github.com/caganerdal/DynIsl/releases/latest), open it and drag DynIsl to Applications. It is signed with a Developer ID and notarized by Apple.

Needs macOS 14 Sonoma or later on an Apple silicon Mac. A MacBook with a notch is best; on other displays the island sits in the middle of the menu bar.

<details>
<summary><strong>Build from source</strong></summary>

You need Xcode or the Xcode Command Line Tools (Swift 5.9+).

```bash
git clone https://github.com/caganerdal/DynIsl.git
cd DynIsl
./build-app.sh install
```

`build-app.sh` builds `build/DynIsl.app` and, with `install`, copies it to `/Applications`. It signs with your Apple Development certificate if you have one; otherwise it creates a local "DynIsl Local" certificate in your keychain so macOS permissions survive rebuilds. `./build-app.sh dmg` makes a notarized DMG if you have a Developer ID.

To update a source install: `git pull && ./build-app.sh install`, or the **Update** button in Settings.
</details>

## Permissions

Every permission is optional. Skip one and only that feature stays off.

| Permission | Used for |
|---|---|
| Automation (Spotify, Music) | Showing and controlling the current song |
| Calendars | Upcoming meetings |
| Location | Weather, rounded to about 1 km |
| Bluetooth | AirPods connection and battery |
| Accessibility | Catching volume and brightness keys for the island's HUD |
| Full Disk Access | Reading the active Focus mode |

## Privacy

- No accounts, no analytics. History and measurements stay on your Mac.
- DynIsl goes online only for weather ([Open-Meteo](https://open-meteo.com), with a rounded location), Spotify artwork, a daily update check on GitHub (can be turned off) and speed tests you start.
- If Claude Code is installed, the AI tab runs its `/usage` command every 5 minutes through your own Claude Code login; it uses no tokens. Claude Code logs are read locally for token counts only, never conversation content.
- Clipboard text stays in memory; images go to a cache folder only your account can read. Everything is cleared when the screen locks and when the app quits.
- The island is hidden from screen sharing and recordings by default.

## Development

```bash
swift build
swift test
```

`@MainActor` services (music, battery, calendar, system sampling and so on) feed SwiftUI views that observe only what they show. CI builds and tests every push. Text lives in `Resources/Localizable.xcstrings` (Turkish source, English translation); run `./Tools/localize.sh` after adding text. See [CONTRIBUTING.md](CONTRIBUTING.md).

Brightness control loads macOS's private `DisplayServices` framework at runtime, which is why DynIsl isn't on the App Store. If it fails, the keys fall back to macOS.

## License

[MIT](LICENSE)

<sub>Apple, Mac, MacBook and macOS are trademarks of Apple Inc. This project is not affiliated with or endorsed by Apple. Spotify is a trademark of Spotify AB.</sub>
