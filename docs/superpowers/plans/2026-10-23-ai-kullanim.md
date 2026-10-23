# AI Kullanımı Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Claude abonelik limitlerini (5 saat / 7 gün) ve Claude Code token kullanımını adada ve Sistem Paneli'nde göstermek; ChatGPT (Codex CLI) ve Gemini için yer hazırlamak.

**Architecture:** Saf kurallar `AIUsageRules` içinde (ayrıştırma, birleştirme, eşikler, settings.json düzenleme). `island claude-status` durum çubuğu komutu limitleri dosyaya yazar ve bildirim atar. `AIUsageStore` (MainActor) dosyayı, bildirimi ve arka plan `ClaudeLogScanner` sonuçlarını birleştirir.

**Tech Stack:** Swift 5 / SwiftUI, macOS 14, Swift Testing.

**Spec:** docs/superpowers/specs/2026-10-23-ai-kullanim-design.md

## Global Constraints
- Kod içinde yorum yok; yeni metinler TR kaynak + EN çeviri (Tools/localize.sh + çeviri betiği).
- Sohbet içeriği okunmaz; jsonl'den yalnızca usage, model, timestamp, cwd, message.id, requestId.
- `~/.claude/settings.json` düzenlemesi: yedek (`settings.json.dynisl-backup`), diğer anahtarlar korunur, yabancı `statusLine` üzerine yazılmaz.
- Paylaşılan dosya `~/Library/Application Support/DynamicIsland/ai-usage.json`, izin 0600, atomik yazım.

## Review Focus
- rate_limits yok (API kullanıcısı / ilk yanıttan önce) → durum çubuğu model adını basar, dosyadaki eski limitler silinmez.
- resets_at geçmiş pencere → %0 ve "açıldı" gösterilir, uyarı bir kez.
- Aynı mesajın jsonl'de tekrar eden satırları → bir kez sayılır.
- Yarım yazılmış son jsonl satırı → atlanır, sonraki taramada okunur.
- settings.json yok / bozuk JSON / başka statusLine → bağlan reddedilir, dosya bozulmaz.

---

### Task 1: AIUsageRules
**Files:** Create `Sources/DynIsl/AIUsageRules.swift`, Test `Tests/DynIslTests/AIUsageRulesTests.swift`
**Produces:**
- `struct LimitWindow: Codable, Equatable { usedPercent: Double; resetsAt: Date }`
- `struct ClaudeLimits: Codable, Equatable { fiveHour: LimitWindow?; sevenDay: LimitWindow?; model: String?; updatedAt: Date }`
- `AIUsageRules.parseStatus(_ data: Data, now: Date) -> ClaudeLimits?` (nil yalnızca JSON geçersizse)
- `AIUsageRules.statusLine(_ l: ClaudeLimits) -> String` → `"5s %23 · hafta %41"`, limit yoksa model adı, o da yoksa `"Claude"`
- `AIUsageRules.merge(old: ClaudeLimits?, new: ClaudeLimits) -> ClaudeLimits` (yeni pencere yoksa eski korunur)
- `AIUsageRules.effective(_ w: LimitWindow?, now: Date) -> LimitWindow?` (resetsAt <= now → used 0)
- `AIUsageRules.crossed(previous: Double, current: Double, thresholds: [Double]) -> Double?` (en yüksek geçilen eşik)
- `struct UsageRecord: Equatable { key: String; date: Date; project: String; model: String; input, output, cacheRead, cacheWrite: Int; var total }`
- `AIUsageRules.parseLogLine(_ line: Substring) -> UsageRecord?` (yalnızca type == assistant ve message.usage)
- `AIUsageRules.connect(settings: Data?, command: String) throws -> Data` / `disconnect(settings: Data, command: String) -> Data?`
- `AIUsageRules.parseCodex(_ line: Substring) -> (primary: LimitWindow?, secondary: LimitWindow?)?`

### Task 2: `island claude-status`
**Files:** Modify `Sources/DynIsl/CLI.swift`
- stdin → parseStatus → eski dosyayla merge → atomik yaz (0600) → `CLI.usageNotification` bildirimi (token'lı) → stdout statusLine.

### Task 3: ClaudeLogScanner + AIUsageStore
**Files:** Create `Sources/DynIsl/AIUsageStore.swift`, Test `Tests/DynIslTests/ClaudeLogScannerTests.swift`
- Scanner: dosya başına bayt konumu, yalnızca tam satırlar, `key` ile tekilleştirme, gün×proje×model toplamları, 30 gün.
- Store: `@Published limits, days, projects, codex, connected`; dosya + bildirim dinleme; tarama 60 sn sınırlı; eşik uyarıları `onChange`.

### Task 4: UI
**Files:** `IslandModel.swift` (IslandTab.ai, wiring), `IslandExpanded.swift`, `IslandCards.swift` (AICard), `Dashboard.swift` + `AIUsagePage.swift`, localization.

### Task 5: Doğrulama
- Tüm testler, derleme, gerçek Claude Code durum çubuğu girdisiyle `claude-status` denemesi, uygulama açılışı.
