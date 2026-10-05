import AppKit
import CoreLocation
import SwiftUI

struct WeatherNow: Equatable {
    var temperature: Int
    var high: Int
    var low: Int
    var code: Int
    var isDay: Bool
    var place: String?

    var symbol: String { WeatherService.symbol(for: code, isDay: isDay) }
    var summary: String { WeatherService.describe(code) }
}

@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var now: WeatherNow?
    @Published private(set) var status: String?

    var onActivity: ((IslandActivity) -> Void)?
    var manualCity = "" { didSet { if manualCity != oldValue { coordinate = nil; refresh() } } }

    private let manager = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?
    private var placeName: String?
    private var timer: Timer?
    private var rainWarnedUntil = Date.distantPast

    private var started = false

    func start() {
        guard !started else { refresh(); return }
        started = true
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        refresh()
        timer = Timer.repeating(every: 20 * 60) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        if let c = coordinate {
            fetch(c)
        } else if !manualCity.trimmingCharacters(in: .whitespaces).isEmpty {
            geocode(manualCity)
        } else {
            switch manager.authorizationStatus {
            case .notDetermined:
                NSApp.activate(ignoringOtherApps: true)
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorized:
                manager.requestLocation()
            default:
                status = String(localized: "Konum izni yok — Ayarlar'dan şehir gir")
            }
        }
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.refresh() } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let c = CLLocationCoordinate2D(latitude: (loc.coordinate.latitude * 100).rounded() / 100,
                                       longitude: (loc.coordinate.longitude * 100).rounded() / 100)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.coordinate = c
                self.fetch(c)
                self.reverseGeocode(loc)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.status = String(localized: "Konum alınamadı") }
        }
    }

    private func reverseGeocode(_ loc: CLLocation) {
        CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: appLocale) { [weak self] marks, _ in
            let name = marks?.first.flatMap { $0.locality ?? $0.administrativeArea }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.placeName = name
                    self?.now?.place = name
                }
            }
        }
    }

    private func geocode(_ city: String) {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "tr")]
        URLSession.shared.dataTask(with: comps.url!) { [weak self] data, _, _ in
            let result = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["results"] as? [[String: Any]]
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let r = result?.first, let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else {
                        self.status = String(localized: "“\(city)” bulunamadı")
                        return
                    }
                    self.placeName = r["name"] as? String
                    let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    self.coordinate = c
                    self.fetch(c)
                }
            }
        }.resume()
    }

    private func fetch(_ c: CLLocationCoordinate2D) {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", c.latitude)),
            .init(name: "longitude", value: String(format: "%.2f", c.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day,precipitation"),
            .init(name: "minutely_15", value: "precipitation"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "forecast_minutely_15", value: "4"),
            .init(name: "timezone", value: "auto"),
        ]
        URLSession.shared.dataTask(with: comps.url!) { [weak self] data, _, error in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(json, failed: error != nil) }
            }
        }.resume()
    }

    private func apply(_ json: [String: Any]?, failed: Bool) {
        guard let json, let cur = json["current"] as? [String: Any],
              let temp = cur["temperature_2m"] as? Double, let code = cur["weather_code"] as? Int else {
            status = failed ? String(localized: "Hava durumu alınamadı") : status
            return
        }
        let daily = json["daily"] as? [String: Any]
        let high = (daily?["temperature_2m_max"] as? [Double])?.first ?? temp
        let low = (daily?["temperature_2m_min"] as? [Double])?.first ?? temp
        now = WeatherNow(temperature: Int(temp.rounded()), high: Int(high.rounded()), low: Int(low.rounded()),
                         code: code, isDay: (cur["is_day"] as? Int ?? 1) == 1, place: placeName)
        status = nil

        let nowRain = cur["precipitation"] as? Double ?? 0
        let upcoming = (json["minutely_15"] as? [String: Any])?["precipitation"] as? [Double] ?? []
        if nowRain < 0.1, let idx = upcoming.firstIndex(where: { $0 >= 0.2 }), Date() > rainWarnedUntil {
            rainWarnedUntil = Date().addingTimeInterval(3 * 3600)
            let minutes = max(idx * 15, 5)
            onActivity?(.init(icon: "cloud.rain.fill", tint: .cyan, title: String(localized: "Yağmur"), trailing: String(localized: "~\(minutes) dk sonra")))
        }
    }

    nonisolated static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    nonisolated static func describe(_ code: Int) -> String {
        switch code {
        case 0: return String(localized: "Bulutsuz")
        case 1: return String(localized: "Az bulutlu")
        case 2: return String(localized: "Parçalı bulutlu")
        case 3: return String(localized: "Çok bulutlu")
        case 45, 48: return String(localized: "Sisli")
        case 51...57: return String(localized: "Çiseleme")
        case 61...67: return String(localized: "Yağmurlu")
        case 71...77: return String(localized: "Karlı")
        case 80...82: return String(localized: "Sağanak")
        case 85, 86: return String(localized: "Kar sağanağı")
        case 95...99: return String(localized: "Gök gürültülü")
        default: return "—"
        }
    }
}
