import ApplicationServices
import Darwin
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

struct SpaceHotkey: Equatable, Sendable {
    let keyCode: Int
    let modifiers: Int
}

private typealias SkyLightConnectionID = UInt32
private typealias SkyLightMainConnectionIDFunction = @convention(c) () -> SkyLightConnectionID
private typealias SkyLightCopyManagedDisplaySpacesFunction = @convention(c) (SkyLightConnectionID) -> Unmanaged<CFArray>?
private typealias SkyLightManagedDisplaySetCurrentSpaceFunction = @convention(c) (SkyLightConnectionID, CFString, UInt64) -> Int32
private typealias SkyLightCopySpacesForWindowsFunction = @convention(c) (SkyLightConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?

private struct SkyLightFunctions {
    let mainConnectionID: SkyLightMainConnectionIDFunction
    let copyManagedDisplaySpaces: SkyLightCopyManagedDisplaySpacesFunction
    let managedDisplaySetCurrentSpace: SkyLightManagedDisplaySetCurrentSpaceFunction
    let copySpacesForWindows: SkyLightCopySpacesForWindowsFunction
}

public final class SpaceService: Sendable {
    public init() {}

    public func currentLayout() throws -> SpacesLayout {
        if let skyLightLayout = try loadSkyLightLayout() {
            return skyLightLayout
        }

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
        if skyLightFunctions != nil {
            return
        }

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
        return hotkeyDescriptor("79", expectedKeyCode: 123, hotkeys: hotkeys) != nil &&
            hotkeyDescriptor("81", expectedKeyCode: 124, hotkeys: hotkeys) != nil
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
        let hotkeyPlist = try symbolicHotkeyPlist()
        let navigationHotkeys = try navigationHotkeys(in: hotkeyPlist)

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

        if try switchViaSkyLight(to: targetSpace, on: monitor) {
            layout = try currentLayout()
            monitorMappings = mapMonitorsToDisplays(
                layout: layout,
                currentDisplays: currentDisplays,
                discoveredWindows: discoveredWindowsProvider()
            )

            if currentSpace(on: displayID, mappings: monitorMappings) == targetSpace {
                Logger.log(
                    "Private Space API switch reached Desktop \(targetSpace.index) on \(monitor.displayIdentifier)."
                )
                return targetSpace
            }

            Logger.log(
                """
                Private Space API switch did not verify Desktop \(targetSpace.index). \
                Current desktop is \(currentSpace(on: displayID, mappings: monitorMappings)?.index ?? 0).
                """
            )
        }

        if layout.usesSeparateSpaces,
           let display = currentDisplays.first(where: { $0.stableIdentifier == displayID }) {
            try focus(display: display)
        }

        if let directHotkey = directDesktopHotkey(for: targetSpace.index, in: hotkeyPlist) {
            Logger.log(
                "Using direct desktop hotkey for Desktop \(targetSpace.index): keyCode=\(directHotkey.keyCode) modifiers=\(directHotkey.modifiers)"
            )
            let directAttempts = 3
            for attempt in 1...directAttempts {
                try sendHotkey(directHotkey)
                Thread.sleep(forTimeInterval: 0.45)

                layout = try currentLayout()
                monitorMappings = mapMonitorsToDisplays(
                    layout: layout,
                    currentDisplays: currentDisplays,
                    discoveredWindows: discoveredWindowsProvider()
                )

                if currentSpace(on: displayID, mappings: monitorMappings) == targetSpace {
                    return targetSpace
                }
                Logger.log(
                    "Direct desktop hotkey attempt \(attempt) did not reach Desktop \(targetSpace.index). Current desktop is \(currentSpace(on: displayID, mappings: monitorMappings)?.index ?? 0)."
                )
            }
        }

        if try switchViaMissionControl(to: targetSpace.index) {
            layout = try currentLayout()
            monitorMappings = mapMonitorsToDisplays(
                layout: layout,
                currentDisplays: currentDisplays,
                discoveredWindows: discoveredWindowsProvider()
            )

            if currentSpace(on: displayID, mappings: monitorMappings) == targetSpace {
                Logger.log("Mission Control switch reached Desktop \(targetSpace.index).")
                return targetSpace
            }

            Logger.log(
                "Mission Control fallback did not reach Desktop \(targetSpace.index). Current desktop is \(currentSpace(on: displayID, mappings: monitorMappings)?.index ?? 0)."
            )
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

            let hotkey = targetSpace.index > currentSpace.index ? navigationHotkeys.right : navigationHotkeys.left
            try sendHotkey(hotkey)
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

    private func hotkeyDescriptor(
        _ key: String,
        expectedKeyCode: Int,
        hotkeys: [String: Any]
    ) -> SpaceHotkey? {
        guard
            let entry = hotkeys[key] as? [String: Any],
            let enabled = entry["enabled"] as? Bool,
            enabled,
            let value = entry["value"] as? [String: Any],
            let parameters = value["parameters"] as? [NSNumber],
            parameters.count >= 2
        else {
            return nil
        }

        guard parameters[1].intValue == expectedKeyCode else {
            return nil
        }

        return SpaceHotkey(
            keyCode: parameters[1].intValue,
            modifiers: parameters.count >= 3 ? parameters[2].intValue : 0
        )
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

    private func sendHotkey(_ hotkey: SpaceHotkey) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(hotkey.keyCode),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(hotkey.keyCode),
                keyDown: false
              )
        else {
            throw MacMirrorError.commandFailed("Failed to create Desktop shortcut events.")
        }

        let flags = cgEventFlags(from: hotkey.modifiers)
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        usleep(50_000)
        keyUp.post(tap: .cghidEventTap)
    }

    private var skyLightFunctions: SkyLightFunctions? {
        SkyLightLoader.shared
    }

    private func loadSkyLightLayout() throws -> SpacesLayout? {
        guard let skyLight = skyLightFunctions else {
            return nil
        }

        let connection = skyLight.mainConnectionID()
        guard let rawMonitors = skyLight.copyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }

        let monitors = parseSkyLightMonitors(rawMonitors)
        let spaceLookup: [Int: (String, SpacesLayout.Space)] = Dictionary(uniqueKeysWithValues: monitors.flatMap { monitor in
            monitor.spaces.compactMap { space in
                guard let id64 = space.id64 else {
                    return nil
                }
                return (id64, (monitor.displayIdentifier, space))
            }
        })

        let rawWindows = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
        let windowNumbers = rawWindows.compactMap { raw -> Int? in
            guard let windowNumber = raw[kCGWindowNumber as String] as? Int else {
                return nil
            }
            return windowNumber
        }

        var windowAssignments: [Int: SpacesLayout.WindowAssignment] = [:]
        for windowNumber in windowNumbers {
            guard
                let spaceIDs = skyLight.copySpacesForWindows(
                    connection,
                    7,
                    [NSNumber(value: windowNumber)] as CFArray
                )?.takeRetainedValue() as? [NSNumber],
                let spaceID = spaceIDs.first?.intValue,
                let assignment = spaceLookup[spaceID]
            else {
                continue
            }

            windowAssignments[windowNumber] = SpacesLayout.WindowAssignment(
                displayIdentifier: assignment.0,
                space: assignment.1
            )
        }

        return SpacesLayout(
            monitors: monitors,
            windowAssignments: windowAssignments,
            usesSeparateSpaces: rawMonitors.count > 1
        )
    }

    private func parseSkyLightMonitors(_ rawMonitors: [[String: Any]]) -> [SpacesLayout.Monitor] {
        rawMonitors.map { monitor in
            let displayIdentifier = monitor["Display Identifier"] as? String ?? "Main"
            let rawCurrentSpace = monitor["Current Space"] as? [String: Any]
            let currentSpaceID = numericSpaceIdentifier(in: rawCurrentSpace)
            let spaces = (monitor["Spaces"] as? [[String: Any]] ?? []).enumerated().map { index, rawSpace in
                SpacesLayout.Space(
                    index: index + 1,
                    uuid: normalizeUUID(rawSpace["uuid"] as? String),
                    id64: numericSpaceIdentifier(in: rawSpace)
                )
            }
            let currentSpace = spaces.first(where: { $0.id64 == currentSpaceID })
            return SpacesLayout.Monitor(
                displayIdentifier: displayIdentifier,
                currentSpace: currentSpace,
                spaces: spaces
            )
        }
    }

    private func numericSpaceIdentifier(in rawSpace: [String: Any]?) -> Int? {
        if let id64 = (rawSpace?["id64"] as? NSNumber)?.intValue {
            return id64
        }
        if let managedSpaceID = (rawSpace?["ManagedSpaceID"] as? NSNumber)?.intValue {
            return managedSpaceID
        }
        return nil
    }

    private func switchViaSkyLight(
        to targetSpace: SpacesLayout.Space,
        on monitor: SpacesLayout.Monitor
    ) throws -> Bool {
        guard let targetSpaceID = targetSpace.id64, let skyLight = skyLightFunctions else {
            return false
        }

        let connection = skyLight.mainConnectionID()
        let result = skyLight.managedDisplaySetCurrentSpace(
            connection,
            monitor.displayIdentifier as CFString,
            UInt64(targetSpaceID)
        )
        Logger.log(
            """
            Attempted private Space API switch display=\(monitor.displayIdentifier) \
            targetSpaceID=\(targetSpaceID) desktopIndex=\(targetSpace.index) rc=\(result)
            """
        )

        guard result == 0 else {
            return false
        }

        Thread.sleep(forTimeInterval: 0.45)
        return true
    }

    private func normalizeUUID(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func symbolicHotkeyPlist() throws -> [String: Any]? {
        let result = try Shell.run("/usr/bin/defaults", arguments: ["export", "com.apple.symbolichotkeys", "-"])
        guard result.exitCode == 0 else {
            throw MacMirrorError.commandFailed(result.stderr.isEmpty ? "Unable to read space navigation shortcuts." : result.stderr)
        }

        let data = Data(result.stdout.utf8)
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private func navigationHotkeys(in plist: [String: Any]?) throws -> (left: SpaceHotkey, right: SpaceHotkey) {
        guard let hotkeys = plist?["AppleSymbolicHotKeys"] as? [String: Any],
              let left = hotkeyDescriptor("79", expectedKeyCode: 123, hotkeys: hotkeys),
              let right = hotkeyDescriptor("81", expectedKeyCode: 124, hotkeys: hotkeys) else {
            throw MacMirrorError.unsupportedOperation(
                "Desktop navigation shortcuts are unavailable. Enable Mission Control's 'Move left a space' and 'Move right a space' shortcuts, then try again."
            )
        }
        return (left, right)
    }

    func directDesktopHotkey(for desktopIndex: Int, in plist: [String: Any]?) -> SpaceHotkey? {
        guard (1...9).contains(desktopIndex),
              let hotkeys = plist?["AppleSymbolicHotKeys"] as? [String: Any] else {
            return nil
        }

        let key = String(117 + desktopIndex)
        let expectedKeyCode = 17 + desktopIndex
        return hotkeyDescriptor(key, expectedKeyCode: expectedKeyCode, hotkeys: hotkeys)
    }

    func cgEventFlags(from modifiers: Int) -> CGEventFlags {
        var flags: CGEventFlags = []

        if modifiers & 0x1_0000 != 0 {
            flags.insert(.maskAlphaShift)
        }
        if modifiers & 0x2_0000 != 0 {
            flags.insert(.maskShift)
        }
        if modifiers & 0x4_0000 != 0 {
            flags.insert(.maskControl)
        }
        if modifiers & 0x8_0000 != 0 {
            flags.insert(.maskAlternate)
        }
        if modifiers & 0x10_0000 != 0 {
            flags.insert(.maskCommand)
        }
        if modifiers & 0x20_0000 != 0 {
            flags.insert(.maskNumericPad)
        }
        if modifiers & 0x40_0000 != 0 {
            flags.insert(.maskHelp)
        }
        if modifiers & 0x80_0000 != 0 {
            flags.insert(.maskSecondaryFn)
        }

        return flags
    }

    private func switchViaMissionControl(to desktopIndex: Int) throws -> Bool {
        let desktopName = "Desktop \(desktopIndex)"
        Logger.log("Attempting Mission Control fallback for \(desktopName).")

        let openResult = try Shell.run("/usr/bin/open", arguments: ["-a", "Mission Control"])
        guard openResult.exitCode == 0 else {
            Logger.log("Mission Control open failed: \(openResult.stderr)")
            return false
        }

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let frame = try missionControlButtonFrame(named: desktopName) {
                let clickPoint = CGPoint(x: frame.midX, y: frame.midY)
                try click(point: clickPoint)
                Thread.sleep(forTimeInterval: 0.9)
                return true
            }
            Thread.sleep(forTimeInterval: 0.15)
        }

        Logger.log("Mission Control fallback could not find button \(desktopName).")
        return false
    }

    private func missionControlButtonFrame(named desktopName: String) throws -> CGRect? {
        let script = """
        tell application "System Events"
            tell process "Dock"
                if not (exists group "Mission Control") then return ""
                set desktopButton to button "\(desktopName)" of list 1 of group "Spaces Bar" of UI element 1 of group "Mission Control"
                set p to position of desktopButton
                set s to size of desktopButton
                return (item 1 of p as string) & "," & (item 2 of p as string) & "," & (item 1 of s as string) & "," & (item 2 of s as string)
            end tell
        end tell
        """

        let result = try Shell.run("/usr/bin/osascript", arguments: ["-e", script])
        guard result.exitCode == 0 else {
            return nil
        }

        let parts = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard parts.count == 4 else {
            return nil
        }

        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    private func click(point: CGPoint) throws {
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
            throw MacMirrorError.commandFailed("Unable to click Mission Control desktop button.")
        }

        mouseDown.post(tap: .cghidEventTap)
        usleep(50_000)
        mouseUp.post(tap: .cghidEventTap)
    }
}

private enum SkyLightLoader {
    static let shared: SkyLightFunctions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else {
            return nil
        }

        guard
            let mainConnectionIDSymbol = dlsym(handle, "CGSMainConnectionID"),
            let copyManagedDisplaySpacesSymbol = dlsym(handle, "CGSCopyManagedDisplaySpaces"),
            let managedDisplaySetCurrentSpaceSymbol = dlsym(handle, "CGSManagedDisplaySetCurrentSpace"),
            let copySpacesForWindowsSymbol = dlsym(handle, "CGSCopySpacesForWindows")
        else {
            return nil
        }

        return SkyLightFunctions(
            mainConnectionID: unsafeBitCast(mainConnectionIDSymbol, to: SkyLightMainConnectionIDFunction.self),
            copyManagedDisplaySpaces: unsafeBitCast(
                copyManagedDisplaySpacesSymbol,
                to: SkyLightCopyManagedDisplaySpacesFunction.self
            ),
            managedDisplaySetCurrentSpace: unsafeBitCast(
                managedDisplaySetCurrentSpaceSymbol,
                to: SkyLightManagedDisplaySetCurrentSpaceFunction.self
            ),
            copySpacesForWindows: unsafeBitCast(
                copySpacesForWindowsSymbol,
                to: SkyLightCopySpacesForWindowsFunction.self
            )
        )
    }()
}
