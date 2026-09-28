import Foundation

struct SpeedResult: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let downMbps: Double
    let upMbps: Double
    let ping: Double
    let rpm: Double
    let interface: String?

    var responsivenessText: String {
        rpm >= 1000 ? "Yüksek" : rpm >= 300 ? "Orta" : "Düşük"
    }
}

@MainActor
final class SpeedTest: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var history: [SpeedResult] = []
    @Published private(set) var error: String?

    var last: SpeedResult? { history.first }
    var onFinished: ((SpeedResult) -> Void)?

    private var process: Process?
    private let key = "speedTestHistory"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let h = try? JSONDecoder().decode([SpeedResult].self, from: data) {
            history = h
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startedAt = Date()
        error = nil

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        p.arguments = ["-c", "-M", "20"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let status = proc.terminationStatus
            let reason = proc.terminationReason
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finish(data, status: status, cancelled: reason == .uncaughtSignal) }
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            isRunning = false
            self.error = "Hız testi başlatılamadı"
        }
    }

    func cancel() {
        process?.terminate()
    }

    private func finish(_ data: Data, status: Int32, cancelled: Bool) {
        isRunning = false
        startedAt = nil
        process = nil
        guard !cancelled else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dl = json["dl_throughput"] as? Double, let ul = json["ul_throughput"] as? Double else {
            error = status == 0 ? "Sonuç okunamadı" : "Bağlantı yok ya da test tamamlanamadı"
            return
        }
        let r = SpeedResult(
            date: Date(), downMbps: dl / 1_000_000, upMbps: ul / 1_000_000,
            ping: json["base_rtt"] as? Double ?? 0, rpm: json["responsiveness"] as? Double ?? 0,
            interface: json["interface_name"] as? String
        )
        history.insert(r, at: 0)
        if history.count > 20 { history.removeLast(history.count - 20) }
        if let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d, forKey: key) }
        onFinished?(r)
    }

    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
    }
}
