import ApplicationServices
import Foundation

public struct SpacesLayout: Sendable {
    public struct Space: Hashable, Sendable {
        public let index: Int
        public let uuid: String?
        public let id64: Int?

        public init(index: Int, uuid: String?, id64: Int?) {
            self.index = index
            self.uuid = uuid
            self.id64 = id64
        }
    }

    public struct Monitor: Hashable, Sendable {
        public let displayIdentifier: String
        public let currentSpace: Space?
        public let spaces: [Space]

        public init(displayIdentifier: String, currentSpace: Space?, spaces: [Space]) {
            self.displayIdentifier = displayIdentifier
            self.currentSpace = currentSpace
            self.spaces = spaces
        }
    }

    public struct WindowAssignment: Hashable, Sendable {
        public let displayIdentifier: String
        public let space: Space

        public init(displayIdentifier: String, space: Space) {
            self.displayIdentifier = displayIdentifier
            self.space = space
        }
    }

    public let monitors: [Monitor]
    public let windowAssignments: [Int: WindowAssignment]
    public let usesSeparateSpaces: Bool

    public init(monitors: [Monitor], windowAssignments: [Int: WindowAssignment], usesSeparateSpaces: Bool) {
        self.monitors = monitors
        self.windowAssignments = windowAssignments
        self.usesSeparateSpaces = usesSeparateSpaces
    }
}

public final class SpaceService: Sendable {
    public init() {}

    public func currentLayout() throws -> SpacesLayout {
        let result = try Shell.run("/usr/bin/defaults", arguments: ["export", "com.apple.spaces", "-"])
        guard result.exitCode == 0 else {
            throw MacMirrorError.commandFailed(result.stderr.isEmpty ? "Unable to read com.apple.spaces." : result.stderr)
        }

        let data = Data(result.stdout.utf8)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return try parseLayout(plist)
    }

    func parseLayout(_ plist: [String: Any]?) throws -> SpacesLayout {
        let root = plist?["SpacesDisplayConfiguration"] as? [String: Any]
        let managementData = root?["Management Data"] as? [String: Any]
        let rawMonitors = managementData?["Monitors"] as? [[String: Any]] ?? []
        let rawSpaceProperties = root?["Space Properties"] as? [[String: Any]] ?? []

        var nameToWindowIDs: [String: [Int]] = [:]
        for property in rawSpaceProperties {
            let name = property["name"] as? String ?? ""
            let windows = (property["windows"] as? [NSNumber] ?? []).map(\.intValue)
            nameToWindowIDs[name] = windows
        }

        var windowAssignments: [Int: SpacesLayout.WindowAssignment] = [:]
        let monitors: [SpacesLayout.Monitor] = rawMonitors.map { monitor in
            let displayIdentifier = monitor["Display Identifier"] as? String ?? "Main"
            let spaces = monitor["Spaces"] as? [[String: Any]] ?? []
            let currentSpaceID = (monitor["Current Space"] as? [String: Any])?["id64"] as? NSNumber

            var currentSpace: SpacesLayout.Space?
            let orderedSpaces: [SpacesLayout.Space] = spaces.enumerated().map { index, space in
                let descriptor = SpacesLayout.Space(
                    index: index + 1,
                    uuid: normalizeUUID(space["uuid"] as? String),
                    id64: (space["id64"] as? NSNumber)?.intValue
                )

                if descriptor.id64 == currentSpaceID?.intValue {
                    currentSpace = descriptor
                }

                let windowKey = (space["uuid"] as? String) ?? ""
                for windowID in nameToWindowIDs[windowKey] ?? [] {
                    windowAssignments[windowID] = SpacesLayout.WindowAssignment(
                        displayIdentifier: displayIdentifier,
                        space: descriptor
                    )
                }

                return descriptor
            }

            return SpacesLayout.Monitor(
                displayIdentifier: displayIdentifier,
                currentSpace: currentSpace,
                spaces: orderedSpaces
            )
        }

        return SpacesLayout(
            monitors: monitors,
            windowAssignments: windowAssignments,
            usesSeparateSpaces: rawMonitors.count > 1
        )
    }

    public func validateNavigationShortcuts() throws {
        let result = try Shell.run("/usr/bin/defaults", arguments: ["export", "com.apple.symbolichotkeys", "-"])
        guard result.exitCode == 0 else {
            throw MacMirrorError.commandFailed(result.stderr.isEmpty ? "Unable to read space navigation shortcuts." : result.stderr)
        }

        let data = Data(result.stdout.utf8)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard navigationShortcutsEnabled(in: plist) else {
            throw MacMirrorError.unsupportedOperation(
                "Desktop navigation shortcuts are unavailable. Enable Mission Control's 'Move left a space' and 'Move right a space' shortcuts, then try again."
            )
        }
    }

    func navigationShortcutsEnabled(in plist: [String: Any]?) -> Bool {
        guard let hotkeys = plist?["AppleSymbolicHotKeys"] as? [String: Any] else {
            return false
        }
        return hotkeyEnabled("79", expectedKeyCode: 123, hotkeys: hotkeys) &&
            hotkeyEnabled("81", expectedKeyCode: 124, hotkeys: hotkeys)
    }

    public func mapMonitorsToDisplays(
        layout: SpacesLayout,
        currentDisplays: [DisplaySignature],
        discoveredWindows: [DiscoveredWindow]
    ) -> [String: SpacesLayout.Monitor] {
        guard let firstMonitor = layout.monitors.first else {
            return [:]
        }

        if layout.usesSeparateSpaces == false {
            return Dictionary(uniqueKeysWithValues: currentDisplays.map { ($0.stableIdentifier, firstMonitor) })
        }

        var mappings: [String: SpacesLayout.Monitor] = [:]
        var remainingMonitors = layout.monitors
        let orderedDisplays = sortDisplays(currentDisplays)

        if let primaryDisplay = orderedDisplays.first(where: \.isPrimary),
           let mainIndex = remainingMonitors.firstIndex(where: { $0.displayIdentifier == "Main" }) {
            mappings[primaryDisplay.stableIdentifier] = remainingMonitors.remove(at: mainIndex)
        }

        for display in orderedDisplays where mappings[display.stableIdentifier] == nil {
            if let monitorIndex = remainingMonitors.firstIndex(where: { $0.displayIdentifier == display.stableIdentifier }) {
                mappings[display.stableIdentifier] = remainingMonitors.remove(at: monitorIndex)
            }
        }

        var windowsByDisplay: [String: [DiscoveredWindow]] = [:]
        for window in discoveredWindows {
            guard let displayID = window.displayID else {
                continue
            }
            windowsByDisplay[displayID, default: []].append(window)
        }

        for display in orderedDisplays where mappings[display.stableIdentifier] == nil {
            let displayWindows = windowsByDisplay[display.stableIdentifier] ?? []
            let bestMatch = remainingMonitors
                .map { monitor in (monitor, score(monitor: monitor, windows: displayWindows)) }
                .max { lhs, rhs in lhs.1 < rhs.1 }

            if let bestMatch, bestMatch.1 > 0,
               let monitorIndex = remainingMonitors.firstIndex(of: bestMatch.0) {
                mappings[display.stableIdentifier] = remainingMonitors.remove(at: monitorIndex)
            }
        }

        for display in orderedDisplays where mappings[display.stableIdentifier] == nil {
            guard remainingMonitors.isEmpty == false else {
                break
            }
            mappings[display.stableIdentifier] = remainingMonitors.removeFirst()
        }

        return mappings
    }

    public func resolvedSpace(
        on monitor: SpacesLayout.Monitor,
        savedSpaceUUID: String?,
        savedSpaceIndex: Int
    ) -> SpacesLayout.Space? {
        if let savedSpaceUUID = normalizeUUID(savedSpaceUUID),
           let exact = monitor.spaces.first(where: { $0.uuid == savedSpaceUUID }) {
            return exact
        }

        if let indexed = monitor.spaces.first(where: { $0.index == savedSpaceIndex }) {
            return indexed
        }

        return nil
    }

    @discardableResult
    public func switchToSpace(
        savedSpaceUUID: String?,
        savedSpaceIndex: Int,
        onDisplayID displayID: String,
        currentDisplays: [DisplaySignature],
        discoveredWindowsProvider: () -> [DiscoveredWindow]
    ) throws -> SpacesLayout.Space {
        try validateNavigationShortcuts()

        var layout = try currentLayout()
        var monitorMappings = mapMonitorsToDisplays(
            layout: layout,
            currentDisplays: currentDisplays,
            discoveredWindows: discoveredWindowsProvider()
        )

        guard let monitor = monitorMappings[displayID] ?? layout.monitors.first else {
            throw MacMirrorError.unsupportedOperation("Unable to determine the current Desktop layout.")
        }

        guard let targetSpace = resolvedSpace(on: monitor, savedSpaceUUID: savedSpaceUUID, savedSpaceIndex: savedSpaceIndex) else {
            throw MacMirrorError.commandFailed(
                "Desktop \(savedSpaceIndex) is unavailable for display \(displayID). Re-save the snapshot after arranging your desktops."
            )
        }

        if currentSpace(on: displayID, mappings: monitorMappings) == targetSpace {
            return targetSpace
        }

        if layout.usesSeparateSpaces,
           let display = currentDisplays.first(where: { $0.stableIdentifier == displayID }) {
            try focus(display: display)
        }

        let maximumSteps = max(12, targetSpace.index + 2)
        for _ in 0..<maximumSteps {
            let currentSpace = currentSpace(on: displayID, mappings: monitorMappings) ?? layout.monitors.first?.currentSpace
            guard let currentSpace else {
                throw MacMirrorError.unsupportedOperation("Unable to determine the active Desktop.")
            }

            if currentSpace == targetSpace {
                return targetSpace
            }

            let keyCode = targetSpace.index > currentSpace.index ? 124 : 123
            try sendKeyCode(keyCode, modifiers: ["control down"])
            Thread.sleep(forTimeInterval: 0.45)

            layout = try currentLayout()
            monitorMappings = mapMonitorsToDisplays(
                layout: layout,
                currentDisplays: currentDisplays,
                discoveredWindows: discoveredWindowsProvider()
            )
        }

        let finalSpace = currentSpace(on: displayID, mappings: monitorMappings) ?? layout.monitors.first?.currentSpace
        throw MacMirrorError.commandFailed(
            "Unable to switch to Desktop \(targetSpace.index). Final desktop was \(finalSpace?.index ?? 0)."
        )
    }

    public func spaceIndex(forWindowNumber windowNumber: Int) -> Int? {
        (try? currentLayout().windowAssignments[windowNumber]?.space.index) ?? nil
    }

    public func spaceUUID(forWindowNumber windowNumber: Int) -> String? {
        (try? currentLayout().windowAssignments[windowNumber]?.space.uuid) ?? nil
    }

    private func currentSpace(
        on displayID: String,
        mappings: [String: SpacesLayout.Monitor]
    ) -> SpacesLayout.Space? {
        mappings[displayID]?.currentSpace ?? mappings.values.first?.currentSpace
    }

    private func sortDisplays(_ displays: [DisplaySignature]) -> [DisplaySignature] {
        displays.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary
            }
            if lhs.originX == rhs.originX {
                return lhs.originY < rhs.originY
            }
            return lhs.originX < rhs.originX
        }
    }

    private func score(monitor: SpacesLayout.Monitor, windows: [DiscoveredWindow]) -> Int {
        windows.reduce(into: 0) { score, window in
            if monitor.spaces.contains(where: { matches(space: $0, window: window) }) {
                score += 1
            }
        }
    }

    private func matches(space: SpacesLayout.Space, window: DiscoveredWindow) -> Bool {
        if let spaceUUID = space.uuid, let windowSpaceUUID = normalizeUUID(window.spaceUUID) {
            return spaceUUID == windowSpaceUUID
        }
        return space.index == window.spaceIndex
    }

    private func hotkeyEnabled(
        _ key: String,
        expectedKeyCode: Int,
        hotkeys: [String: Any]
    ) -> Bool {
        guard
            let entry = hotkeys[key] as? [String: Any],
            let enabled = entry["enabled"] as? Bool,
            enabled,
            let value = entry["value"] as? [String: Any],
            let parameters = value["parameters"] as? [NSNumber],
            parameters.count >= 2
        else {
            return false
        }

        return parameters[1].intValue == expectedKeyCode
    }

    private func focus(display: DisplaySignature) throws {
        let point = CGPoint(
            x: display.rect.midX,
            y: display.rect.midY
        )

        CGWarpMouseCursorPosition(point)
        guard
            let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ),
            let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
        else {
            throw MacMirrorError.commandFailed("Unable to focus display \(display.localizedName).")
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.2)
    }

    private func sendKeyCode(_ keyCode: Int, modifiers: [String]) throws {
        let modifierList = modifiers.joined(separator: ", ")
        let source = """
        tell application "System Events"
            key code \(keyCode) using {\(modifierList)}
        end tell
        """
        let result = try Shell.run("/usr/bin/osascript", arguments: ["-e", source])
        guard result.exitCode == 0 else {
            throw MacMirrorError.commandFailed(result.stderr.isEmpty ? "Failed to send Desktop shortcut." : result.stderr)
        }
    }

    private func normalizeUUID(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
