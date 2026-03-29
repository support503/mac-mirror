import AppKit
import CoreGraphics
import Foundation

public final class WindowDiscoveryService: Sendable {
    private let displayService: DisplayService
    private let spaceService: SpaceService

    public init(displayService: DisplayService = DisplayService(), spaceService: SpaceService = SpaceService()) {
        self.displayService = displayService
        self.spaceService = spaceService
    }

    public func runningApplications() -> [RunningApplicationInfo] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                app.bundleIdentifier != Bundle.main.bundleIdentifier
            }
            .map { app in
                RunningApplicationInfo(
                    pid: app.processIdentifier,
                    bundleIdentifier: app.bundleIdentifier,
                    displayName: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                    executablePath: app.executableURL?.path,
                    isHidden: app.isHidden,
                    isActive: app.isActive
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func discoverWindows() -> [DiscoveredWindow] {
        let currentDisplays = displayService.currentDisplays()
        let spacesLayout = try? spaceService.currentLayout()
        guard
            let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        return list.compactMap { raw -> DiscoveredWindow? in
            guard
                let layer = raw[kCGWindowLayer as String] as? Int,
                layer == 0,
                let ownerPID = raw[kCGWindowOwnerPID as String] as? Int32,
                let ownerName = raw[kCGWindowOwnerName as String] as? String,
                let windowNumber = raw[kCGWindowNumber as String] as? Int,
                let boundsDictionary = raw[kCGWindowBounds as String] as? NSDictionary,
                let cgRect = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            guard cgRect.width > 80, cgRect.height > 80 else {
                return nil
            }

            let geometry = WindowGeometry(
                x: cgRect.origin.x,
                y: cgRect.origin.y,
                width: cgRect.width,
                height: cgRect.height
            )

            let display = displayService.display(containing: geometry, displays: currentDisplays)

            return DiscoveredWindow(
                pid: ownerPID,
                windowNumber: windowNumber,
                ownerName: ownerName,
                windowTitle: raw[kCGWindowName as String] as? String,
                frame: geometry,
                layer: layer,
                isOnscreen: (raw[kCGWindowIsOnscreen as String] as? Bool) ?? false,
                displayID: display?.stableIdentifier,
                displayName: display?.localizedName,
                spaceIndex: spacesLayout?.windowAssignments[windowNumber]?.space.index,
                spaceUUID: spacesLayout?.windowAssignments[windowNumber]?.space.uuid
            )
        }
    }

    public func waitForWindow(
        bundleIdentifier: String,
        excluding existingWindowNumbers: Set<Int>,
        targetGeometry: WindowGeometry?,
        timeout: TimeInterval = 12
    ) -> DiscoveredWindow? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let windows = discoverWindows()
            let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleIdentifier }
            let pids = Set(runningApps.map(\.processIdentifier))
            let candidates = windows.filter { window in
                pids.contains(window.pid) && existingWindowNumbers.contains(window.windowNumber) == false
            }

            if let best = matchClosestWindow(in: candidates, targetGeometry: targetGeometry) {
                return best
            }

            Thread.sleep(forTimeInterval: 0.4)
        }
        return nil
    }

    public func frontmostRunningApplication(bundleIdentifier: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }

    private func matchClosestWindow(in windows: [DiscoveredWindow], targetGeometry: WindowGeometry?) -> DiscoveredWindow? {
        guard let targetGeometry else {
            return windows.sorted { $0.windowNumber > $1.windowNumber }.first
        }

        return windows.min {
            $0.frame.distance(to: targetGeometry) < $1.frame.distance(to: targetGeometry)
        }
    }
}

private extension WindowGeometry {
    func distance(to other: WindowGeometry) -> Double {
        abs(x - other.x) + abs(y - other.y) + abs(width - other.width) + abs(height - other.height)
    }
}
