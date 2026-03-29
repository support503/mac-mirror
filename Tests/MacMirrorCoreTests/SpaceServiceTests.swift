import Testing
@testable import MacMirrorCore

struct SpaceServiceTests {
    @Test
    func navigationShortcutsRequireBothDirections() {
        let service = SpaceService()

        #expect(service.navigationShortcutsEnabled(in: [
            "AppleSymbolicHotKeys": [
                "79": hotkey(enabled: true, keyCode: 123),
                "81": hotkey(enabled: true, keyCode: 124),
            ]
        ]))

        #expect(service.navigationShortcutsEnabled(in: [
            "AppleSymbolicHotKeys": [
                "79": hotkey(enabled: true, keyCode: 123),
                "81": hotkey(enabled: false, keyCode: 124),
            ]
        ]) == false)
    }

    @Test
    func resolvedSpacePrefersUUIDOverIndex() throws {
        let service = SpaceService()
        let monitor = SpacesLayout.Monitor(
            displayIdentifier: "Main",
            currentSpace: SpacesLayout.Space(index: 1, uuid: nil, id64: 1),
            spaces: [
                SpacesLayout.Space(index: 1, uuid: nil, id64: 1),
                SpacesLayout.Space(index: 2, uuid: "SPACE-A", id64: 2),
                SpacesLayout.Space(index: 3, uuid: "SPACE-B", id64: 3),
            ]
        )

        let resolved = try #require(
            service.resolvedSpace(on: monitor, savedSpaceUUID: "SPACE-B", savedSpaceIndex: 2)
        )

        #expect(resolved.index == 3)
        #expect(resolved.uuid == "SPACE-B")
    }

    @Test
    func resolvedSpaceFallsBackToIndexForLegacySnapshots() throws {
        let service = SpaceService()
        let monitor = SpacesLayout.Monitor(
            displayIdentifier: "Main",
            currentSpace: SpacesLayout.Space(index: 1, uuid: nil, id64: 1),
            spaces: [
                SpacesLayout.Space(index: 1, uuid: nil, id64: 1),
                SpacesLayout.Space(index: 2, uuid: "SPACE-A", id64: 2),
            ]
        )

        let resolved = try #require(
            service.resolvedSpace(on: monitor, savedSpaceUUID: nil, savedSpaceIndex: 2)
        )

        #expect(resolved.index == 2)
        #expect(resolved.uuid == "SPACE-A")
    }

    @Test
    func directDesktopHotkeyReadsConfiguredShortcut() throws {
        let service = SpaceService()

        let hotkey = try #require(service.directDesktopHotkey(for: 3, in: [
            "AppleSymbolicHotKeys": [
                "120": hotkey(enabled: true, keyCode: 20, modifiers: 262144),
            ]
        ]))

        #expect(hotkey.keyCode == 20)
        #expect(hotkey.modifiers == 262144)
    }

    @Test
    func cgEventFlagsIncludeSecondaryFunctionWhenConfigured() {
        let service = SpaceService()
        let flags = service.cgEventFlags(from: 8650752)

        #expect(flags.contains(.maskControl))
        #expect(flags.contains(.maskSecondaryFn))
    }

    private func hotkey(enabled: Bool, keyCode: Int, modifiers: Int = 8650752) -> [String: Any] {
        [
            "enabled": enabled,
            "value": [
                "parameters": [65535, keyCode, modifiers],
            ],
        ]
    }
}
