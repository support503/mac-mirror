import Testing
@testable import MacMirrorCore

struct DisplayMappingTests {
    @Test
    func choosesClosestFallbackDisplay() {
        let service = DisplayService()
        let saved = [
            DisplaySignature(
                stableIdentifier: "saved-1",
                displayID: 1,
                localizedName: "Display A",
                originX: 0,
                originY: 0,
                width: 2560,
                height: 1440,
                isPrimary: true
            ),
            DisplaySignature(
                stableIdentifier: "saved-2",
                displayID: 2,
                localizedName: "Display B",
                originX: 2560,
                originY: 0,
                width: 1920,
                height: 1080,
                isPrimary: false
            ),
        ]
        let current = [
            DisplaySignature(
                stableIdentifier: "current-1",
                displayID: 3,
                localizedName: "Display A",
                originX: 0,
                originY: 0,
                width: 2560,
                height: 1440,
                isPrimary: true
            )
        ]

        let mappings = service.mapDisplays(saved: saved, current: current)
        #expect(mappings["saved-1"]?.current.localizedName == "Display A")
        #expect(mappings["saved-2"]?.current.localizedName == "Display A")
        #expect(mappings["saved-2"]?.usedFallback == true)
    }
}
