import Foundation
import Testing
@testable import JournalCore

struct AwakeTests {
    @Test func sessionStartExtendAndFormatCountdown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = AwakeSession.start(duration: 7200, now: now, keepDisplayAwake: false)
        #expect(session.remaining(at: now) == 7200)
        #expect(!session.isExpired(at: now))
        #expect(session.formattedRemaining(at: now) == "2h")
        #expect(session.formattedRemaining(at: now.addingTimeInterval(100)) == "1h 59m")
        #expect(session.formattedRemaining(at: now.addingTimeInterval(7170)) == "<1m")
        #expect(session.isExpired(at: now.addingTimeInterval(7200)))
        #expect(session.formattedRemaining(at: now.addingTimeInterval(7200)) == "0m")

        let extended = session.extended(by: 1800, now: now.addingTimeInterval(600))
        #expect(extended.endsAt == now.addingTimeInterval(9000))
    }

    @Test func sessionClampsDurationToMax() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let huge = AwakeSession.start(duration: AwakeSession.maxDuration * 10, now: now)
        #expect(huge.remaining(at: now) == AwakeSession.maxDuration)

        let tiny = AwakeSession.start(duration: 5, now: now)
        #expect(tiny.remaining(at: now) == 60)
    }

    @Test func floorRulesEndSessionOnLowBatteryOrCriticalThermal() {
        let config = AwakeConfig(keepDisplayAwake: false, lowPowerOnLidClose: true, lowPowerFloor: 40, endFloor: 10, thermalRules: true)

        #expect(AwakeFloorRules.evaluate(
            batteryPercent: 10, isCharging: false, thermal: .nominal, wasHot: false, lidClosed: false, lowPowerSetByUs: true, config: config
        ) == [.endSession(.batteryFloor)])

        // Charging prevents battery floor end
        #expect(AwakeFloorRules.evaluate(
            batteryPercent: 8, isCharging: true, thermal: .nominal, wasHot: false, lidClosed: false, lowPowerSetByUs: false, config: config
        ) == [])

        // Critical thermal ends even while charging
        #expect(AwakeFloorRules.evaluate(
            batteryPercent: 90, isCharging: true, thermal: .critical, wasHot: true, lidClosed: false, lowPowerSetByUs: false, config: config
        ) == [.endSession(.thermalCritical)])
    }

    @Test func floorRulesToggleLowPowerForBatteryThermalAndLid() {
        let config = AwakeConfig(keepDisplayAwake: false, lowPowerOnLidClose: true, lowPowerFloor: 40, endFloor: 10, thermalRules: true)

        // Below 40% on battery enables LPM
        #expect(AwakeFloorRules.evaluate(
            batteryPercent: 35, isCharging: false, thermal: .nominal, wasHot: false, lidClosed: false, lowPowerSetByUs: false, config: config
        ) == [.enableLowPower])

        // Plugged back in disables LPM we set
        #expect(AwakeFloorRules.evaluate(
            batteryPercent: 35, isCharging: true, thermal: .nominal, wasHot: false, lidClosed: false, lowPowerSetByUs: true, config: config
        ) == [.disableLowPower])

        // Lid closed enables LPM even on power when configured
        #expect(AwakeFloorRules.evaluate(
            batteryPercent: 95, isCharging: true, thermal: .nominal, wasHot: false, lidClosed: true, lowPowerSetByUs: false, config: config
        ) == [.enableLowPower])

        // Thermal hysteresis: stays on at fair if wasHot, drops at nominal
        #expect(AwakeFloorRules.evaluate(
            batteryPercent: 95, isCharging: true, thermal: .fair, wasHot: true, lidClosed: false, lowPowerSetByUs: true, config: config
        ) == [])
        #expect(AwakeFloorRules.evaluate(
            batteryPercent: 95, isCharging: true, thermal: .nominal, wasHot: false, lidClosed: false, lowPowerSetByUs: true, config: config
        ) == [.disableLowPower])
    }

    @Test func pmsetParsersHandleMacOS14Through27Outputs() {
        let pmsetG = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         sleep                1
        """
        #expect(PmsetParser.readSleepDisabled(pmsetG) == true)
        #expect(PmsetParser.readSleepDisabled(" SleepDisabled  0\n") == false)
        #expect(PmsetParser.readSleepDisabled("Currently in use:\n sleep 1") == nil)

        let customOld = """
        Battery Power:
         lowpowermode         1
        AC Power:
         lowpowermode         0
        """
        #expect(PmsetParser.parseLowPowerMode(customOld) == true)

        let customNew = """
        Battery Power:
         powermode            0
        AC Power:
         powermode            2
        """
        #expect(PmsetParser.parseLowPowerMode(customNew) == false)

        let highPower = """
        Battery Power:
         powermode            2
        """
        #expect(PmsetParser.parseLowPowerMode(highPower) == nil)
    }

    @Test func parsesAwakeCLIDurationsAndCommands() {
        #expect(AwakeCLIParser.parseDuration("30m") == 1800)
        #expect(AwakeCLIParser.parseDuration("2h") == 7200)
        #expect(AwakeCLIParser.parseDuration("1h30m") == 5400)
        #expect(AwakeCLIParser.parseDuration("1d") == 86400)
        #expect(AwakeCLIParser.parseDuration("7200") == 7200)
        #expect(AwakeCLIParser.parseDuration("0m") == nil)
        #expect(AwakeCLIParser.parseDuration("bogus") == nil)

        #expect(AwakeCLIParser.parse(subcommandArguments: ["start", "2h"]) == .success(.start(seconds: 7200)))
        #expect(AwakeCLIParser.parse(subcommandArguments: ["extend", "30m"]) == .success(.extend(seconds: 1800)))
        #expect(AwakeCLIParser.parse(subcommandArguments: ["stop"]) == .success(.stop))
        #expect(AwakeCLIParser.parse(subcommandArguments: ["status", "--json"]) == .success(.status(json: true)))
        #expect(AwakeCLIParser.parse(subcommandArguments: ["backstop"]) == .success(.backstop))

        if case .failure = AwakeCLIParser.parse(subcommandArguments: ["start", "10s"]) {
            // expected: below 1 minute minimum
        } else {
            Issue.record("expected start < 1m to fail")
        }
    }
}
