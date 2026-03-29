import Foundation
import MacMirrorCore

@main
struct MacMirrorLogin {
    static func main() {
        let environment = AppEnvironment()
        Logger.log("mac-mirror-login starting.")
        Thread.sleep(forTimeInterval: 5)

        do {
            try environment.restoreCoordinator.restorePinnedSnapshot()
            Logger.log("Pinned snapshot restore complete.")
        } catch {
            Logger.log("Pinned snapshot restore failed: \(error.localizedDescription)")
            fputs("mac-mirror-login: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
