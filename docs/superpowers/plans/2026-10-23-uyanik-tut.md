# Uyanık Tut (gelişmiş) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the Mac awake with flexible durations and conditions, including with the lid closed, controlled from a new System Dashboard page, the island and the menu bar.

**Architecture:** `KeepAwake` (existing service) gains modes, new duration kinds and a battery safety check. A new `LidSleepControl` wraps the one-time sudoers setup and `sudo -n /usr/bin/pmset -a disablesleep 0|1`. Pure decision logic lives in `KeepAwakeRules` so it can be unit tested. UI: new `KeepAwakePage` in the dashboard, small additions to the island System tab and the menu bar menu.

**Tech Stack:** Swift 5.9 package, SwiftUI, IOKit power assertions, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-23-uyanik-tut-design.md`

## Global Constraints

- No code comments; match existing style (`@MainActor` `ObservableObject` services, Turkish UI strings).
- New UI strings in Turkish, then `./Tools/localize.sh`, then English translations in `Resources/Localizable.xcstrings`.
- sudoers file: `/etc/sudoers.d/dynisl`, allows only `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1` for the current user, validated with `visudo -cf` before install.
- Battery safety default threshold: 20 %.
- Durations: Süresiz, 15 dk, 30 dk, 1 sa, 2 sa, 4 sa, 8 sa, "Şu saate kadar", "Uygulama açık kaldıkça".
- `disablesleep 0` must run on stop, expiry, battery cut-off, app quit, and on launch when the crash-recovery flag is set.

## Review Focus

1. "Şu saate kadar" with a time earlier than now: means that time tomorrow, not an instant stop.
2. Chosen app quits or was never running: keep-awake stops with an island notice, not a silent forever-on.
3. Battery at or below threshold while on AC power: must NOT stop (only on battery).
4. Lid mode requested but setup missing or `sudo -n` fails: normal keep-awake still starts, lid toggle shows "izin gerekli", no crash.
5. App killed while lid mode on: next launch restores `disablesleep 0`.

---

### Task 1: KeepAwakeRules (pure logic) + tests

**Files:**
- Create: `Sources/DynIsl/KeepAwakeRules.swift`
- Test: `Tests/DynIslTests/KeepAwakeRulesTests.swift`

**Interfaces:**
- Produces:
  - `enum KeepAwakeDuration: Equatable { case indefinite, minutes(Int), until(Date), whileApp(String) }` (`whileApp` holds a bundle identifier)
  - `enum KeepAwakeRules`
    - `static func endDate(for: KeepAwakeDuration, now: Date, calendar: Calendar) -> Date?` — `.until(t)` with t ≤ now returns t + 1 day (same clock time tomorrow); `.indefinite`/`.whileApp` return nil.
    - `static func shouldStopForBattery(level: Int, onBattery: Bool, threshold: Int) -> Bool` — true only when `onBattery && level <= threshold`.
    - `static func sudoersContent(user: String) -> String` — exactly `"\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"`.
    - `static func sleepDisabled(fromPmsetOutput: String) -> Bool` — true when a line matches `SleepDisabled` followed by `1`.

- [ ] **Step 1: Write failing tests** `endDateMinutes` (30 → now+1800), `endDateUntilFuture`, `endDateUntilPastMeansTomorrow` (now 23:00, until 07:00 today → 07:00 next day), `indefiniteHasNoEnd`, `batteryStopsOnlyOnBattery` (15/true/20 → true; 15/false/20 → false; 21/true/20 → false; 20/true/20 → true), `sudoersLine` (user "ali" → exact string above), `parsesSleepDisabled` (" SleepDisabled\t\t1" → true, "SleepDisabled 0" → false, "" → false).
- [ ] **Step 2: Run** `swift test --filter KeepAwakeRulesTests` → FAIL (types missing).
- [ ] **Step 3: Implement** the enum and functions in `KeepAwakeRules.swift`.
- [ ] **Step 4: Run** `swift test` → all pass.
- [ ] **Step 5: Commit** "Uyanık Tut kuralları ve testleri".

### Task 2: LidSleepControl

**Files:**
- Create: `Sources/DynIsl/LidSleepControl.swift`

**Interfaces:**
- Consumes: `KeepAwakeRules.sudoersContent(user:)`, `KeepAwakeRules.sleepDisabled(fromPmsetOutput:)`
- Produces: `@MainActor final class LidSleepControl: ObservableObject`
  - `@Published private(set) var isInstalled: Bool` (file `/etc/sudoers.d/dynisl` exists)
  - `func install() async -> Bool` — writes content to a temp file, then one `NSAppleScript` `do shell script "... with administrator privileges"` that runs `/usr/sbin/visudo -cf <tmp> && /usr/bin/install -m 0440 -o root -g wheel <tmp> /etc/sudoers.d/dynisl`; refresh `isInstalled`.
  - `func uninstall() async -> Bool` — admin `rm -f /etc/sudoers.d/dynisl` and `pmset -a disablesleep 0`.
  - `nonisolated func setDisabled(_ on: Bool) -> Bool` — runs `/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1|0`, returns exit status == 0.
  - `nonisolated func currentlyDisabled() -> Bool` — `pmset -g` output through `sleepDisabled(fromPmsetOutput:)`.
  - Crash flag: UserDefaults key `lidSleepEngaged`; `setDisabled(true)` sets it, `setDisabled(false)` clears it; `func recoverIfNeeded()` runs `setDisabled(false)` when flag is set.

- [ ] **Step 1:** Implement; admin AppleScript runs off the main thread (detached task), results applied on main.
- [ ] **Step 2: Verify** `swift build -c release` passes; manual check later in Task 5.
- [ ] **Step 3: Commit** "Kapak modu için pmset yardımcısı".

### Task 3: KeepAwake service upgrade

**Files:**
- Modify: `Sources/DynIsl/KeepAwake.swift`
- Modify: `Sources/DynIsl/IslandModel.swift` (wiring)
- Modify: `Sources/DynIsl/AppDelegate.swift` (stop on quit)

**Interfaces:**
- Consumes: `KeepAwakeDuration`, `KeepAwakeRules`, `LidSleepControl`
- Produces on `KeepAwake`:
  - `@Published private(set) var duration: KeepAwakeDuration`, `@Published var allowDisplaySleep: Bool` (UserDefaults `keepAwakeAllowDisplaySleep`), `@Published var lidClosedMode: Bool` (UserDefaults `keepAwakeLidMode`), `@Published var batteryThreshold: Int` (UserDefaults `keepAwakeBatteryThreshold`, default 20), `@Published private(set) var lidActive: Bool`, `@Published private(set) var lidError: Bool`
  - `func start(_ duration: KeepAwakeDuration)` (replaces `start(minutes:)`; update menu bar callers), `func stop(reason: StopReason)` with `enum StopReason { case user, expired, battery, appQuit }`
  - `let lid = LidSleepControl()`
  - `static let durations: [(title: String, value: KeepAwakeDuration)]` = the 7 fixed ones from Global Constraints.
- Behavior: assertions use only `kIOPMAssertPreventUserIdleSystemSleep` when `allowDisplaySleep`; lid mode calls `lid.setDisabled(true)` after assertions, sets `lidError` on failure; `.whileApp` observes `NSWorkspace.didTerminateApplicationNotification` and stops with `.appQuit` (also stops immediately if the app isn't running); battery check via existing `BatteryAnalytics` level/externalPower each time it changes (subscribe in IslandModel) calling `shouldStopForBattery`; every stop path calls `lid.setDisabled(false)` when `lidActive`. On launch `lid.recoverIfNeeded()`. `applicationWillTerminate` calls `keepAwake.stop(reason: .user)`.
- Island notices: battery stop → title "Pil azaldı", trailing "Uyanık tut kapandı"; app quit → app name + "kapandı, uyanık tut bitti".

- [ ] **Step 1:** Implement and update callers (`AppDelegate` menu, `IslandCards` pill).
- [ ] **Step 2: Verify** `swift build -c release` and `swift test` pass.
- [ ] **Step 3: Commit** "Uyanık Tut: modlar, yeni süreler, pil güvenliği, kapak modu".

### Task 4: UI — dashboard page, island, menu bar, localization

**Files:**
- Create: `Sources/DynIsl/KeepAwakePage.swift`
- Modify: `Sources/DynIsl/Dashboard.swift` (`DashboardPage` new case `.keepAwake`, title "Uyanık Tut", icon "cup.and.saucer.fill", section Bağlantı ve Güç), `Sources/DynIsl/IslandCards.swift` (pill shows remaining time and a laptop icon when `lidActive`), `Sources/DynIsl/AppDelegate.swift` (menu: new durations, "Ekran kapanabilir", "Kapak kapalıyken de" toggles), `Resources/Localizable.xcstrings`

- Page content: status card (active/inactive, remaining time ring for timed durations, mode line), duration buttons grid, "Şu saate kadar" `DatePicker(.hourAndMinute)` + Başlat, "Uygulama açık kaldıkça" picker over `NSWorkspace.shared.runningApplications` with `.regular` activation policy, toggles "Ekran kapanabilir", "Kapak kapalıyken de", lid permission row (status, "İzin ver…" / "İzni kaldır"), battery threshold stepper 5…50 step 5, explanatory caption about heat risk.
- [ ] **Step 1:** Implement page and integrations.
- [ ] **Step 2:** `./Tools/localize.sh`, add English for every new key, recompile catalog; zero untranslated.
- [ ] **Step 3: Verify** build, tests, and screenshots of the page and island pill.
- [ ] **Step 4: Commit** "Uyanık Tut sayfası ve arayüz".

### Task 5: Manual verification with the user

- [ ] Install permission once (user enters password in the macOS dialog), confirm `pmset -g` shows `SleepDisabled 1` while lid mode is on and `0` after stop.
- [ ] User closes the lid for ~1 minute with music playing; music keeps playing.
- [ ] Kill the app with lid mode on; relaunch; `SleepDisabled` back to 0.
- [ ] Bump `VERSION` to 0.7.0, commit.
