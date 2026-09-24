import AppKit
import Darwin
import Dispatch

if CommandLine.arguments.contains("--fake-game") {
    dispatchMain()
} else if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run())
} else if CommandLine.arguments.contains("--probe-live") {
    exit(SelfTest.probeLive())
} else if CommandLine.arguments.contains("--probe-discord") {
    exit(SelfTest.probeDiscord())
} else if CommandLine.arguments.contains("--probe-override") {
    exit(SelfTest.probeOverride())
} else if CommandLine.arguments.contains("--launch-boosteroid-presence-mode") {
    exit(SelfTest.launchBoosteroidInPresenceMode())
} else if CommandLine.arguments.contains("--probe-activity-filter") {
    exit(SelfTest.probeBoosteroidActivityFilter())
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
