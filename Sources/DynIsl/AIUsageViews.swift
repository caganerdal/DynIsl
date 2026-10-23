import SwiftUI
import Charts

func tokens(_ n: Int) -> String {
    n.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(appLocale))
}

func resetText(_ date: Date, now: Date = Date()) -> String {
    let m = max(Int(date.timeIntervalSince(now) / 60), 0)
    if m < 60 { return String(localized: "\(m) dk sonra açılır") }
    if m < 24 * 60 { return String(localized: "\(m / 60) sa \(m % 60) dk sonra açılır") }
    return String(localized: "\(date.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(appLocale))) açılır")
}

func agoText(_ date: Date, now: Date = Date()) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = appLocale
    f.unitsStyle = .short
    return now.timeIntervalSince(date) < 60 ? String(localized: "şimdi") : f.localizedString(for: date, relativeTo: now)
}

func limitTint(_ p: Double) -> Color { p >= 95 ? .red : p >= 80 ? .orange : .green }

struct AICard: View {
    @EnvironmentObject private var ai: AIUsageStore
    @EnvironmentObject var model: IslandModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(alignment: .center, spacing: 18) {
                ring(ai.fiveHour, label: String(localized: "5S"), now: context.date)
                ring(ai.sevenDay, label: String(localized: "HFT"), now: context.date)
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("BUGÜN").font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
                        Spacer()
                        Button("Ayrıntılar ›") { DashboardWindow.show(model: model, page: .aiUsage) }
                            .buttonStyle(.pressable).font(.system(size: 10, weight: .semibold)).foregroundStyle(model.accent ?? .blue)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(tokens(ai.summary.today.total)).font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("token").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text("7 gün: \(tokens(ai.summary.week.total))")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    if let top = ai.summary.projects.first {
                        Text("En çok: \(top.name)").font(.system(size: 11)).lineLimit(1)
                    }
                    Text(footer(now: context.date)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func ring(_ w: LimitWindow?, label: String, now: Date) -> some View {
        let p = w?.usedPercent ?? 0
        return RingGauge(value: p / 100, label: label,
                         detail: w.map { $0.resetsAt > now && $0.usedPercent > 0 ? resetText($0.resetsAt, now: now) : pc(Int(p.rounded())) } ?? "—",
                         tint: w == nil ? .gray : limitTint(p))
            .help(w.map { pc(Int($0.usedPercent.rounded())) } ?? String(localized: "Claude Code'a bağlı değil"))
    }

    private func footer(now: Date) -> String {
        guard let l = ai.limits, l.hasData else {
            return ai.linked ? String(localized: "Claude Code'dan ilk veri bekleniyor") : String(localized: "Limitler için Ayrıntılar'dan bağlan")
        }
        return String(localized: "Claude · \(agoText(l.updatedAt, now: now)) güncellendi")
    }
}

struct AIUsagePage: View {
    @EnvironmentObject private var ai: AIUsageStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 16) {
                claudeCard(now: context.date)
                codeCard
                codexCard(now: context.date)
                Card(title: "Gemini", icon: "sparkles", tint: .blue) {
                    Text("Gemini aboneliğinin limitleri için resmî bir veri kaynağı yok. Google bir yol sunduğunda burada görünecek.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            ai.refreshLink()
            ai.refresh()
        }
    }

    private func claudeCard(now: Date) -> some View {
        Card(title: "Claude aboneliği", icon: "sparkle", tint: .orange) {
            HStack(spacing: 28) {
                limitBlock(ai.fiveHour, title: String(localized: "5 saatlik"), now: now)
                limitBlock(ai.sevenDay, title: String(localized: "Haftalık"), now: now)
                Spacer()
            }
            if let l = ai.limits, l.hasData {
                Text("Son güncelleme: \(agoText(l.updatedAt, now: now))\(l.model.map { " · \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Limitler Claude Code çalışırken gelir ve claude.ai ile ortaktır; yalnızca sohbet ediyorsan son bilinen değer gösterilir.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                if ai.linked {
                    Label("Claude Code'a bağlı", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Bağlantıyı kaldır") { ai.disconnect() }
                } else {
                    Label("Claude Code durum çubuğu üzerinden okunur", systemImage: "link").foregroundStyle(.secondary)
                    Spacer()
                    Button("Claude Code'a bağla") { ai.connect() }.buttonStyle(.borderedProminent)
                }
            }
            .font(.callout)
            if let m = ai.linkMessage {
                Text(m).font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Limit uyarıları", isOn: $ai.alertsEnabled)
            Text("5 saatlik limit \(pc(80)) ve \(pc(95)) olunca, haftalık limit \(pc(90)) olunca ve limit açılınca adada haber verir.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func limitBlock(_ w: LimitWindow?, title: String, now: Date) -> some View {
        let p = w?.usedPercent ?? 0
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke((w == nil ? Color.gray : limitTint(p)).opacity(0.18), lineWidth: 8)
                Circle().trim(from: 0, to: min(max(p / 100, 0.005), 1))
                    .stroke(w == nil ? .gray : limitTint(p), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(w == nil ? "—" : pc(Int(p.rounded()))).font(.system(size: 15, weight: .semibold).monospacedDigit())
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(w.map { $0.resetsAt > now ? resetText($0.resetsAt, now: now) : String(localized: "Açıldı") } ?? String(localized: "Veri yok"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var codeCard: some View {
        Card(title: "Claude Code kullanımı", icon: "terminal.fill", tint: .orange) {
            HStack(spacing: 24) {
                stat(String(localized: "Bugün"), ai.summary.today)
                stat(String(localized: "Son 7 gün"), ai.summary.week)
                Spacer()
                if ai.scanning { ProgressView().controlSize(.small) }
            }
            Chart(ai.summary.daily, id: \.day) { d in
                BarMark(x: .value("Gün", d.day, unit: .day), y: .value("Token", d.total))
                    .foregroundStyle(.orange.gradient)
            }
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Int.self) { Text(tokens(n)) } } } }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
            .frame(height: 140)
            if !ai.summary.projects.isEmpty {
                Divider()
                Text("Projeler (7 gün)").font(.subheadline.weight(.semibold))
                ForEach(ai.summary.projects.prefix(8), id: \.name) { row($0, of: ai.summary.week.total) }
                Divider()
                Text("Modeller (7 gün)").font(.subheadline.weight(.semibold))
                ForEach(ai.summary.models, id: \.name) { row($0, of: ai.summary.week.total) }
            }
            Text("Claude Code'un bu Mac'teki kayıtlarından hesaplanır; önbellekten okunan token'lar dahildir. Sohbet içeriği okunmaz.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: String, _ t: UsageTotals) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(tokens(t.total)).font(.title2.weight(.semibold).monospacedDigit())
            Text("girdi \(tokens(t.input)) · çıktı \(tokens(t.output)) · önbellek \(tokens(t.cacheRead + t.cacheWrite))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func row(_ n: AIUsageSummary.Named, of total: Int) -> some View {
        HStack {
            Text(n.name).lineLimit(1)
            Spacer()
            Text(tokens(n.total)).monospacedDigit().foregroundStyle(.secondary)
            Text(total > 0 ? pc(Int((Double(n.total) / Double(total) * 100).rounded())) : "—")
                .monospacedDigit().frame(width: 44, alignment: .trailing)
        }
        .font(.callout)
    }

    private func codexCard(now: Date) -> some View {
        Card(title: "ChatGPT", icon: "bubble.left.and.text.bubble.right.fill", tint: .green) {
            if let c = ai.codex {
                HStack(spacing: 28) {
                    limitBlock(AIUsageRules.effective(c.primary, now: now), title: String(localized: "Kısa dönem"), now: now)
                    limitBlock(AIUsageRules.effective(c.secondary, now: now), title: String(localized: "Haftalık"), now: now)
                    Spacer()
                }
                Text("Codex CLI kayıtlarından · \(agoText(c.updatedAt, now: now))").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Bağlı değil. ChatGPT aboneliğinin limitleri yalnızca Codex CLI kullanıldığında onun kayıtlarından okunabiliyor.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
