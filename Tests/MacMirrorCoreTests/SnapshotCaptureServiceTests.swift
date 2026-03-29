import Foundation
import Testing
@testable import MacMirrorCore

struct SnapshotCaptureServiceTests {
    @Test
    func captureChromeTargetsIncludesOnlyLiveWindows() throws {
        let root = try makeChromeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeLocalState(
            to: root,
            profiles: [
                ("Default", "Work"),
                ("Profile 1", "Personal"),
            ]
        )
        try writeSessionFixture(SnapshotFixture.desktopOneArchive, profileDirectory: "Default", root: root)
        try writeSessionFixture(SnapshotFixture.secondaryArchive, profileDirectory: "Profile 1", root: root)

        let service = makeService(root: root)
        let targets = try service.captureChromeTargets(
            displays: [display(id: "DISPLAY-UUID-1", name: "Built-in Retina Display")],
            discoveredWindows: [
                chromeWindow(windowNumber: 4001, spaceIndex: 1, spaceUUID: nil),
            ],
            defaultSpaceIndex: 1
        )

        #expect(targets.count == 1)
        #expect(targets.first?.chromeProfileID == "Default")
        #expect(targets.first?.chromeProfileName == "Work")
        #expect(targets.first?.targetSpaceIndex == 1)
        #expect(targets.first?.targetSpaceUUID == nil)
    }

    @Test
    func captureChromeTargetsUsesSessionWindowNumbersWhenGeometriesMatch() throws {
        let root = try makeChromeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeLocalState(
            to: root,
            profiles: [
                ("Default", "Work"),
                ("Profile 1", "Personal"),
            ]
        )
        try writeSessionFixture(SnapshotFixture.desktopOneArchive, profileDirectory: "Default", root: root)
        try writeSessionFixture(SnapshotFixture.secondaryArchive, profileDirectory: "Profile 1", root: root)

        let service = makeService(root: root)
        let identicalGeometry = WindowGeometry(x: 50, y: 40, width: 1200, height: 900)
        let targets = try service.captureChromeTargets(
            displays: [
                display(id: "DISPLAY-UUID-1", name: "Built-in Retina Display"),
                display(id: "DISPLAY-UUID-2", name: "Studio Display"),
            ],
            discoveredWindows: [
                chromeWindow(
                    windowNumber: 4001,
                    title: "Primary Inbox",
                    frame: identicalGeometry,
                    displayID: "DISPLAY-UUID-1",
                    displayName: "Built-in Retina Display",
                    spaceIndex: 1,
                    spaceUUID: nil
                ),
                chromeWindow(
                    windowNumber: 4002,
                    title: "Secondary Window",
                    frame: identicalGeometry,
                    displayID: "DISPLAY-UUID-2",
                    displayName: "Studio Display",
                    spaceIndex: 3,
                    spaceUUID: "SPACE-UUID-2"
                ),
            ],
            defaultSpaceIndex: 1
        )

        let workTarget = try #require(targets.first(where: { $0.chromeProfileID == "Default" }))
        let personalTarget = try #require(targets.first(where: { $0.chromeProfileID == "Profile 1" }))

        #expect(workTarget.targetSpaceIndex == 1)
        #expect(workTarget.targetSpaceUUID == nil)
        #expect(workTarget.targetDisplayID == "DISPLAY-UUID-1")

        #expect(personalTarget.targetSpaceIndex == 3)
        #expect(personalTarget.targetSpaceUUID == "SPACE-UUID-2")
        #expect(personalTarget.targetDisplayID == "DISPLAY-UUID-2")
    }

    private func makeChromeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeService(root: URL) -> SnapshotCaptureService {
        let chromeProfileService = ChromeProfileService(
            chromeSupportDirectory: root,
            chromeApplicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )
        let sessionService = ChromeSessionMetadataService(chromeSupportDirectory: root)
        return SnapshotCaptureService(
            chromeProfileService: chromeProfileService,
            chromeSessionMetadataService: sessionService,
            displayService: DisplayService(),
            windowDiscoveryService: WindowDiscoveryService(),
            spaceService: SpaceService()
        )
    }

    private func writeLocalState(
        to root: URL,
        profiles: [(directory: String, name: String)]
    ) throws {
        let infoCache = profiles.reduce(into: [String: [String: Any]]()) { result, profile in
            result[profile.directory] = [
                "name": profile.name,
                "active_time": 100,
            ]
        }

        let localState: [String: Any] = [
            "profile": [
                "info_cache": infoCache,
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: localState, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("Local State"))
    }

    private func writeSessionFixture(_ archive: String, profileDirectory: String, root: URL) throws {
        let sessionDirectory = root
            .appendingPathComponent(profileDirectory, isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let contents = Data("prefix \(archive) suffix".utf8)
        try contents.write(to: sessionDirectory.appendingPathComponent("Session_1"))
    }

    private func display(id: String, name: String) -> DisplaySignature {
        DisplaySignature(
            stableIdentifier: id,
            displayID: 1,
            localizedName: name,
            originX: 0,
            originY: 0,
            width: 1512,
            height: 982,
            isPrimary: true
        )
    }

    private func chromeWindow(
        windowNumber: Int,
        title: String = "Chrome",
        frame: WindowGeometry = WindowGeometry(x: 10, y: 10, width: 1200, height: 900),
        displayID: String = "DISPLAY-UUID-1",
        displayName: String = "Built-in Retina Display",
        spaceIndex: Int?,
        spaceUUID: String?
    ) -> DiscoveredWindow {
        DiscoveredWindow(
            pid: 1,
            windowNumber: windowNumber,
            ownerName: "Google Chrome",
            windowTitle: title,
            frame: frame,
            layer: 0,
            isOnscreen: true,
            displayID: displayID,
            displayName: displayName,
            spaceIndex: spaceIndex,
            spaceUUID: spaceUUID
        )
    }
}

private enum SnapshotFixture {
    static let desktopOneArchive = "YnBsaXN0MDDUAQIDBAUGMjtZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKtBwgJChMZGhskJSYsL1UkbnVsbF1QcmltYXJ5IEluYm94UNMLDA0ODxFWJGNsYXNzV05TLmtleXNaTlMub2JqZWN0c4AKoRCABKESgAfTCxQVFhcYXxASTlNTY3JlZW5MYXlvdXRTaXplXxAYTlNTY3JlZW5MYXlvdXRVVUlEU3RyaW5ngAuABoAFXkRJU1BMQVktVVVJRC0xW3sxNTEyLCA5ODJ91QscHR4fICEhIiNfEBxOU1dpbmRvd0xheW91dE1vdmVHZW5lcmF0aW9uXxAeTlNXaW5kb3dMYXlvdXRSZXNpemVHZW5lcmF0aW9uXxAfTlNXaW5kb3dMYXlvdXRTY3JlZW5MYXlvdXRGcmFtZV8QGU5TV2luZG93TGF5b3V0V2luZG93RnJhbWWADBAAgAiACV8QFXt7MCwgMH0sIHsxNTEyLCA5NDl9fV8QF3t7MTUsIDkxfSwgezEzMjIsIDg1OH190icoKSpYJGNsYXNzZXNaJGNsYXNzbmFtZaIqK1xOU0RpY3Rpb25hcnlYTlNPYmplY3TSJygtLqIuK15OU1NjcmVlbkxheW91dNInKDAxojErXk5TV2luZG93TGF5b3V01DM0NTY3ODk6V05TVGl0bGVeTlNXaW5kb3dOdW1iZXJfEBNOU1dpbmRvd1dvcmtzcGFjZUlEXxAeX05TV2luZG93TGFzdFVzZXJXaW5kb3dMYXlvdXRzgAERD6GAAoADEgABhqAACAARABsAJAApADIARABSAFgAZgBnAG4AdQB9AIgAigCMAI4AkACSAJkArgDJAMsAzQDPAN4A6gD1ARQBNQFXAXMBdQF3AXkBewGTAa0BsgG7AcYByQHWAd8B5AHnAfYB+wH+Ag0CFgIeAi0CQwJkAmYCaQJrAm0AAAAAAAACAQAAAAAAAAA8AAAAAAAAAAAAAAAAAAACcg=="
    static let secondaryArchive = "YnBsaXN0MDDUAQIDBAUGMjtZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKtBwgJChMZGhskJSYsL1UkbnVsbF8QEFNlY29uZGFyeSBXaW5kb3dcU1BBQ0UtVVVJRC0y0wsMDQ4PEVYkY2xhc3NXTlMua2V5c1pOUy5vYmplY3RzgAqhEIAEoRKAB9MLFBUWFxhfEBJOU1NjcmVlbkxheW91dFNpemVfEBhOU1NjcmVlbkxheW91dFVVSURTdHJpbmeAC4AGgAVeRElTUExBWS1VVUlELTJbezE1MTIsIDk4Mn3VCxwdHh8gISEiI18QHE5TV2luZG93TGF5b3V0TW92ZUdlbmVyYXRpb25fEB5OU1dpbmRvd0xheW91dFJlc2l6ZUdlbmVyYXRpb25fEB9OU1dpbmRvd0xheW91dFNjcmVlbkxheW91dEZyYW1lXxAZTlNXaW5kb3dMYXlvdXRXaW5kb3dGcmFtZYAMEACACIAJXxAVe3swLCAwfSwgezE1MTIsIDk0OX19XxAXe3syMiwgODR9LCB7MTM0NCwgODQzfX3SJygpKlgkY2xhc3Nlc1okY2xhc3NuYW1loiorXE5TRGljdGlvbmFyeVhOU09iamVjdNInKC0uoi4rXk5TU2NyZWVuTGF5b3V00icoMDGiMSteTlNXaW5kb3dMYXlvdXTUMzQ1Njc4OTpXTlNUaXRsZV5OU1dpbmRvd051bWJlcl8QE05TV2luZG93V29ya3NwYWNlSURfEB5fTlNXaW5kb3dMYXN0VXNlcldpbmRvd0xheW91dHOAAREPooACgAMSAAGGoAAIABEAGwAkACkAMgBEAFIAWABrAHgAfwCGAI4AmQCbAJ0AnwChAKMAqgC/ANoA3ADeAOAA7wD7AQYBJQFGAWgBhAGGAYgBigGMAaQBvgHDAcwB1wHaAecB8AH1AfgCBwIMAg8CHgInAi8CPgJUAnUCdwJ6AnwCfgAAAAAAAAIBAAAAAAAAADwAAAAAAAAAAAAAAAAAAAKD"
}
