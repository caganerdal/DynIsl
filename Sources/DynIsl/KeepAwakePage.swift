import SwiftUI

struct KeepAwakePage: View {
    @EnvironmentObject private var keepAwake: KeepAwake
    @EnvironmentObject private var lid: LidSleepControl
    @State private var untilTime = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    @State private var appID = ""
    @State private var apps: [(id: String, name: String)] = []
    @State private var permissionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if lid.recoveryNeeded {
                Card(title: "Uyku kapalı kaldı", icon: "exclamationmark.triangle.fill", tint: .orange) {
                    Text("DynIsl beklenmedik şekilde kapandığı için Mac'in uyku ayarı kapalı kaldı. Mac kapak kapalıyken bile uyumayacak.")
                        .font(.callout)
                    Button("Uykuyu yeniden aç…") { Task { _ = await lid.restoreSleepWithAdmin() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in statusCard }
            Card(title: "Süre", icon: "timer", tint: .orange) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(Array(KeepAwake.durations.enumerated()), id: \.offset) { _, d in
                        durationButton(d.title, d.value)
                    }
                }
                Divider()
                HStack {
                    Text("Şu saate kadar").foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: $untilTime, displayedComponents: .hourAndMinute).labelsHidden().frame(width: 90)
                    Button("Başlat") { keepAwake.start(.until(untilTime)) }
                }
                HStack {
                    Text("Uygulama açık kaldıkça").foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $appID) {
                        Text("Uygulama seç").tag("")
                        ForEach(apps, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().frame(width: 200)
                    Button("Başlat") { keepAwake.start(.whileApp(appID)) }.disabled(appID.isEmpty)
                }
            }
            Card(title: "Seçenekler", icon: "slider.horizontal.3", tint: .orange) {
                Toggle("Ekran kapanabilir", isOn: $keepAwake.allowDisplaySleep)
                Text("Mac çalışmaya devam eder, ekran macOS ayarına göre kararır; enerji tasarrufu sağlar.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Toggle("Kapak kapalıyken de uyanık tut", isOn: $keepAwake.lidClosedMode)
                    .disabled(!lid.isInstalled)
                lidPermissionRow
                if keepAwake.lidError {
                    Label("Kapak modu açılamadı. İzni yeniden vermeyi dene.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Divider()
                Stepper(value: $keepAwake.batteryThreshold, in: 5...50, step: 5) {
                    HStack {
                        Text("Pil bu seviyeye inince kapat")
                        Spacer()
                        Text(pc(keepAwake.batteryThreshold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Text("Yalnızca pildeyken geçerli. Kapak kapalıyken Mac çantada ısınabilir; bu sınır pilin bitmesini ve aşırı ısınmayı önler.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: loadApps)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in loadApps() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in loadApps() }
    }

    private var statusCard: some View {
        Card {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.orange.opacity(0.15), lineWidth: 6)
                    if let fraction = remainingFraction {
                        Circle().trim(from: 0, to: fraction)
                            .stroke(.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Image(systemName: keepAwake.lidActive ? "laptopcomputer" : keepAwake.isActive ? "cup.and.saucer.fill" : "moon.zzz.fill")
                        .font(.title2).foregroundStyle(keepAwake.isActive ? .orange : .secondary)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(keepAwake.isActive ? "Uyanık" : "Kapalı").font(.title2.weight(.semibold))
                    Text(statusLine).foregroundStyle(.secondary)
                }
                Spacer()
                if keepAwake.isActive {
                    Button("Kapat") { keepAwake.stop() }.controlSize(.large)
                } else {
                    Button("Süresiz başlat") { keepAwake.start(.indefinite) }.buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
        }
    }

    @ViewBuilder private var lidPermissionRow: some View {
        HStack {
            if lid.isInstalled {
                Label("İzin verildi", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                Spacer()
                Button("İzni kaldır") {
                    Task {
                        let ok = await lid.uninstall()
                        permissionMessage = ok ? nil : String(localized: "İzin kaldırılmadı.")
                        if ok { keepAwake.lidClosedMode = false }
                    }
                }
            } else {
                Label("Bir kez yönetici izni gerekiyor", systemImage: "lock.shield").foregroundStyle(.secondary)
                Spacer()
                Button("İzin ver…") {
                    Task {
                        let ok = await lid.install()
                        permissionMessage = ok ? nil : String(localized: "İzin verilmedi.")
                        if ok { keepAwake.reapply() }
                    }
                }
            }
        }
        .font(.callout)
        .disabled(lid.working)
        Text(permissionMessage ?? String(localized: "macOS şifre penceresi açılır. Sisteme yalnızca uykuyu açıp kapatma komutu eklenir; izin buradan tamamen kaldırılabilir."))
            .font(.caption).foregroundStyle(.secondary)
    }

    private func durationButton(_ title: String, _ value: KeepAwakeDuration) -> some View {
        let selected = keepAwake.isActive && keepAwake.duration == value
        return Button { keepAwake.start(value) } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .orange : nil)
    }

    private var statusLine: String {
        guard keepAwake.isActive else { return String(localized: "Mac normal şekilde uyuyabilir") }
        var parts = [KeepAwake.label(keepAwake.duration)]
        if let r = keepAwake.remainingText { parts.append(r) }
        if keepAwake.lidActive { parts.append(String(localized: "kapak kapalıyken de")) }
        if keepAwake.allowDisplaySleep { parts.append(String(localized: "ekran kapanabilir")) }
        return parts.joined(separator: " · ")
    }

    private var remainingFraction: Double? {
        guard let end = keepAwake.endDate, case .minutes(let m) = keepAwake.duration, m > 0 else { return nil }
        return min(max(end.timeIntervalSinceNow / Double(m * 60), 0), 1)
    }

    private func loadApps() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { a in a.bundleIdentifier.map { (id: $0, name: a.localizedName ?? $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
