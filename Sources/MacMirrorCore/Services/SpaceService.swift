import ApplicationServices
import Foundation

public struct SpacesLayout: Sendable {
    public struct Monitor: Sendable {
        public let displayIdentifier: String
        public let currentSpaceIndex: Int?
        public let spaces: [String]
    }

    public let monitors: [Monitor]
    public let windowToSpaceIndex: [Int: Int]
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

        var windowToSpaceIndex: [Int: Int] = [:]
        let monitors: [SpacesLayout.Monitor] = rawMonitors.map { monitor in
            let displayIdentifier = monitor["Display Identifier"] as? String ?? "Main"
            let spaces = monitor["Spaces"] as? [[String: Any]] ?? []
            let currentSpaceID = (monitor["Current Space"] as? [String: Any])?["id64"] as? NSNumber

            var orderedKeys: [String] = []
            var currentSpaceIndex: Int?

            for (index, space) in spaces.enumerated() {
                let uuid = (space["uuid"] as? String) ?? ""
                let key = uuid
                orderedKeys.append(key)
                if currentSpaceID == (space["id64"] as? NSNumber) {
                    currentSpaceIndex = index + 1
                }

                for windowID in nameToWindowIDs[key] ?? [] {
                    windowToSpaceIndex[windowID] = index + 1
                }
            }

            return SpacesLayout.Monitor(
                displayIdentifier: displayIdentifier,
                currentSpaceIndex: currentSpaceIndex,
                spaces: orderedKeys
            )
        }

        return SpacesLayout(monitors: monitors, windowToSpaceIndex: windowToSpaceIndex)
    }

    public func switchToSpace(_ targetIndex: Int) throws {
        guard targetIndex > 0 else { return }

        if (1...9).contains(targetIndex) {
            try sendControlDigitShortcut(targetIndex)
            return
        }

        guard let current = try? currentLayout().monitors.first?.currentSpaceIndex else {
            throw MacMirrorError.unsupportedOperation("Unable to determine the current Space index.")
        }

        let delta = targetIndex - current
        guard delta != 0 else { return }

        let keyCode = delta > 0 ? 124 : 123
        for _ in 0..<abs(delta) {
            try sendKeyCode(keyCode, modifiers: ["control down"])
            Thread.sleep(forTimeInterval: 0.35)
        }
    }

    public func spaceIndex(forWindowNumber windowNumber: Int) -> Int? {
        (try? currentLayout().windowToSpaceIndex[windowNumber]) ?? nil
    }

    private func sendControlDigitShortcut(_ digit: Int) throws {
        let keyCodes: [Int: Int] = [
            1: 18,
            2: 19,
            3: 20,
            4: 21,
            5: 23,
            6: 22,
            7: 26,
            8: 28,
            9: 25,
        ]
        guard let keyCode = keyCodes[digit] else {
            return
        }
        try sendKeyCode(keyCode, modifiers: ["control down"])
        Thread.sleep(forTimeInterval: 0.5)
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
            throw MacMirrorError.commandFailed(result.stderr.isEmpty ? "Failed to send Space shortcut." : result.stderr)
        }
    }
}
