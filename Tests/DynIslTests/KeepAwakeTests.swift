import Foundation
import Testing
@testable import DynIsl

@MainActor
struct KeepAwakeTests {
    @Test func refusesToStartBelowBatteryThreshold() {
        let k = KeepAwake()
        k.batteryThreshold = 20
        k.batteryState = { (level: 15, onBattery: true) }
        k.start(.minutes(30))
        #expect(!k.isActive)
    }

    @Test func startsBelowThresholdWhenPluggedIn() {
        let k = KeepAwake()
        k.batteryThreshold = 20
        k.batteryState = { (level: 15, onBattery: false) }
        k.start(.minutes(30))
        #expect(k.isActive)
        k.stop()
        #expect(!k.isActive)
    }

    @Test func raisingThresholdAboveLevelStops() {
        let k = KeepAwake()
        k.batteryThreshold = 10
        k.batteryState = { (level: 30, onBattery: true) }
        k.start(.indefinite)
        #expect(k.isActive)
        k.batteryThreshold = 40
        #expect(!k.isActive)
    }
}
