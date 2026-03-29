import Foundation
import Testing
@testable import MacMirrorCore

struct SnapshotStoreTests {
    @Test
    func snapshotRoundTrip() throws {
        let snapshot = Snapshot(
            name: "Desk Setup",
            machineIdentifier: "machine-1",
            displaySignatures: [
                DisplaySignature(
                    stableIdentifier: "display-1",
                    displayID: 1,
                    localizedName: "Studio Display",
                    originX: 0,
                    originY: 0,
                    width: 2560,
                    height: 1440,
                    isPrimary: true
                )
            ],
            windowTargets: [
                WindowTarget(
                    kind: .chromeProfile,
                    applicationName: "Google Chrome",
                    bundleIdentifier: "com.google.Chrome",
                    executablePath: "/Applications/Google Chrome.app",
                    chromeProfileID: "Profile 1",
                    chromeProfileName: "Work",
                    windowTitle: "Inbox",
                    launchOrder: 0,
                    geometry: WindowGeometry(x: 10, y: 20, width: 1000, height: 900),
                    targetDisplayID: "display-1",
                    targetDisplayName: "Studio Display",
                    targetSpaceIndex: 2,
                    isHidden: false,
                    isMinimized: false
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(Snapshot.self, from: data)

        #expect(decoded.name == "Desk Setup")
        #expect(decoded.windowTargets.first?.chromeProfileID == "Profile 1")
        #expect(decoded.windowTargets.first?.targetSpaceIndex == 2)
    }
}
