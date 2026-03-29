import Testing
@testable import MacMirrorCore

struct SnapshotSummaryTests {
    @Test
    func snapshotSummariesIncludeTargetCounts() {
        let snapshot = Snapshot(
            name: "Desk Setup",
            machineIdentifier: "machine-1",
            displaySignatures: [],
            windowTargets: [
                makeTarget(kind: .chromeProfile),
                makeTarget(kind: .chromeProfile),
                makeTarget(kind: .applicationWindow),
            ]
        )

        #expect(snapshot.targetCount == 3)
        #expect(snapshot.chromeTargetCount == 2)
        #expect(snapshot.applicationTargetCount == 1)
        #expect(snapshot.shortTargetSummary == "3 targets • 2 Chrome")
        #expect(snapshot.detailedTargetSummary == "3 targets, 2 Chrome, 1 app window")
    }

    private func makeTarget(kind: WindowTargetKind) -> WindowTarget {
        WindowTarget(
            kind: kind,
            applicationName: kind == .chromeProfile ? "Google Chrome" : "Notes",
            bundleIdentifier: kind == .chromeProfile ? "com.google.Chrome" : "com.apple.Notes",
            executablePath: nil,
            chromeProfileID: kind == .chromeProfile ? "Profile 1" : nil,
            chromeProfileName: kind == .chromeProfile ? "Work" : nil,
            windowTitle: nil,
            launchOrder: 0,
            geometry: WindowGeometry(x: 0, y: 0, width: 500, height: 400),
            targetDisplayID: "main",
            targetDisplayName: "Main",
            targetSpaceIndex: 1,
            isHidden: false,
            isMinimized: false
        )
    }
}
