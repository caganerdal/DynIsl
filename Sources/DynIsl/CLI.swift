import Foundation

enum CLI {
    static let notificationName = Notification.Name("local.dynamicisland.notify")

    static func runIfNeeded() -> Int32? {
        var args = Array(CommandLine.arguments.dropFirst())
        let invokedAsIsland = (CommandLine.arguments.first as NSString?)?.lastPathComponent == "island"
        args.removeAll { $0.hasPrefix("-psn_") || $0.hasPrefix("-NS") || $0 == "YES" }
        guard invokedAsIsland || args.first.map(["notify", "run", "claude-hook", "-h", "--help"].contains) == true else {
            return nil
        }
        if args.first == "notify" { args.removeFirst() }

        switch args.first {
        case "-h", "--help":
            print(help)
            return 0
        case "run":
            return run(Array(args.dropFirst()))
        case "claude-hook":
            return claudeHook()
        default:
            return notify(args)
        }
    }

    private static func notify(_ args: [String]) -> Int32 {
        var title = "Terminal", icon = "terminal.fill", tint = "white", duration = 4.0
        var sound = false
        var message: [String] = []
        var i = 0
        func value() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
        }
        while i < args.count {
            switch args[i] {
            case "-t", "--title": title = value() ?? title
            case "-i", "--icon": icon = value() ?? icon
            case "-c", "--color": tint = value() ?? tint
            case "-d", "--duration": duration = value().flatMap(Double.init) ?? duration
            case "-s", "--success": icon = "checkmark.circle.fill"; tint = "green"
            case "-e", "--error": icon = "xmark.octagon.fill"; tint = "red"
            case "--sound": sound = true
            default: message.append(args[i])
            }
            i += 1
        }
        guard !message.isEmpty else {
            FileHandle.standardError.write(Data((help + "\n").utf8))
            return 64
        }
        post(title: title, message: message.joined(separator: " "), icon: icon, tint: tint,
             duration: duration, sound: sound)
        return 0
    }

    private static func run(_ command: [String]) -> Int32 {
        guard !command.isEmpty else {
            FileHandle.standardError.write(Data("kullanım: island run <komut> [argümanlar]\n".utf8))
            return 64
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = command
        p.standardInput = FileHandle.standardInput
        p.standardOutput = FileHandle.standardOutput
        p.standardError = FileHandle.standardError
        let start = Date()
        do { try p.run() } catch {
            FileHandle.standardError.write(Data("island: \(command[0]) çalıştırılamadı: \(error.localizedDescription)\n".utf8))
            return 127
        }
        signal(SIGINT, SIG_IGN)
        p.waitUntilExit()
        let elapsed = Date().timeIntervalSince(start)
        let name = command.prefix(2).joined(separator: " ")
        let ok = p.terminationStatus == 0
        post(title: name,
             message: ok ? "Bitti · \(format(elapsed))" : "Hata (\(p.terminationStatus)) · \(format(elapsed))",
             icon: ok ? "checkmark.circle.fill" : "xmark.octagon.fill",
             tint: ok ? "green" : "red", duration: 5, sound: elapsed > 30)
        return p.terminationStatus
    }

    private static func format(_ t: TimeInterval) -> String {
        t < 60 ? "\(Int(t.rounded())) sn" : "\(Int(t) / 60) dk \(Int(t) % 60) sn"
    }

    private static func claudeHook() -> Int32 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let project = (json["cwd"] as? String).map { ($0 as NSString).lastPathComponent } ?? "Claude"
        switch json["hook_event_name"] as? String ?? "" {
        case "Stop":
            post(title: project, message: "Claude bitirdi", icon: "sparkle", tint: "orange", duration: 4, sound: false)
        case "Notification":
            post(title: project, message: shorten(json["message"] as? String ?? "Seni bekliyor"),
                 icon: "hand.raised.fill", tint: "orange", duration: 6, sound: true)
        default:
            break
        }
        return 0
    }

    private static func shorten(_ msg: String) -> String {
        let m = msg.lowercased()
        if m.contains("permission") { return "İzin bekliyor" }
        if m.contains("waiting for your input") || m.contains("idle") { return "Cevabını bekliyor" }
        return msg.count > 40 ? String(msg.prefix(38)) + "…" : msg
    }

    private static func post(title: String, message: String, icon: String, tint: String, duration: Double, sound: Bool) {
        DistributedNotificationCenter.default().postNotificationName(
            notificationName, object: nil,
            userInfo: ["title": title, "message": message, "icon": icon, "tint": tint,
                       "duration": duration, "sound": sound],
            deliverImmediately: true
        )
    }

    static let help = """
    island — DynIsl adasına bildirim gönder

      island "mesaj"                     basit bildirim
      island -t Başlık "mesaj"           başlıkla
      island -s "mesaj"                  başarı (yeşil ✓)
      island -e "mesaj"                  hata (kırmızı ✕)
      island -i <SF Symbol> -c <renk> "mesaj"
      island -d 6 --sound "mesaj"        6 sn göster, ses çal
      island run <komut...>              komutu çalıştır, bitince bildir

    renkler: white green red orange yellow blue purple pink teal
    """
}
