import Foundation
import MacMirrorCore

@main
struct MacMirrorLogin {
    static func main() {
        let environment = AppEnvironment()
        Logger.log("mac-mirror-login starting.")
        Thread.sleep(forTimeInterval: 5)

        do {
            let report = try environment.restoreCoordinator.restorePinnedSnapshot()
            Logger.log("Pinned snapshot restore complete. \(report.summaryLine)")
            for failure in report.failedTargets {
                Logger.log("Pinned snapshot restore failure \(failure.targetDescription): \(failure.message ?? "Unknown error")")
            }
        } catch {
            Logger.log("Pinned snapshot restore failed: \(error.localizedDescription)")
            fputs("mac-mirror-login: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
