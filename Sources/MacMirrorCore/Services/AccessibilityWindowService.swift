import AppKit
import ApplicationServices
import Foundation

public final class AccessibilityWindowService: Sendable {
    public init() {}

    public func applyWindowTarget(
        _ target: WindowTarget,
        bundleIdentifier: String,
        referenceWindow: DiscoveredWindow?
    ) throws {
        guard PermissionService.accessibilityAuthorized(promptIfNeeded: false) else {
            throw MacMirrorError.missingAccessibilityPermission
        }

        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return
        }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        guard let window = findMatchingWindow(in: appElement, referenceWindow: referenceWindow, target: target) else {
            return
        }

        try setValue(window, attribute: kAXPositionAttribute as String, value: AXValueCreate(.cgPoint, [target.geometry.x, target.geometry.y]))
        try setValue(window, attribute: kAXSizeAttribute as String, value: AXValueCreate(.cgSize, [target.geometry.width, target.geometry.height]))
        try setBoolean(window, attribute: kAXMinimizedAttribute as String, value: target.isMinimized)

        if target.isHidden {
            runningApp.hide()
        } else {
            runningApp.unhide()
            runningApp.activate(options: [.activateIgnoringOtherApps])
        }
    }

    public func clickChromeRestoreButtonIfPresent() {
        let script = """
        tell application "System Events"
            if not (exists process "Google Chrome") then return
            tell process "Google Chrome"
                repeat with w in windows
                    if exists button "Restore" of w then
                        click button "Restore" of w
                        return
                    end if
                    if exists button "Restore pages" of w then
                        click button "Restore pages" of w
                        return
                    end if
                end repeat
            end tell
        end tell
        """
        _ = try? Shell.run("/usr/bin/osascript", arguments: ["-e", script])
    }

    private func findMatchingWindow(
        in appElement: AXUIElement,
        referenceWindow: DiscoveredWindow?,
        target: WindowTarget
    ) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else {
            return nil
        }

        let axWindows = windows.compactMap { window -> (AXUIElement, WindowGeometry, String?)? in
            guard let frame = frame(for: window) else { return nil }
            return (window, frame, title(for: window))
        }

        let targetTitle = referenceWindow?.windowTitle ?? target.windowTitle
        return axWindows.min { lhs, rhs in
            score(window: lhs.1, title: lhs.2, target: target.geometry, targetTitle: targetTitle) <
            score(window: rhs.1, title: rhs.2, target: target.geometry, targetTitle: targetTitle)
        }?.0
    }

    private func score(window: WindowGeometry, title: String?, target: WindowGeometry, targetTitle: String?) -> Double {
        let framePenalty = window.distance(to: target)
        let titlePenalty: Double
        if let targetTitle, targetTitle.isEmpty == false, let title {
            titlePenalty = title.localizedCaseInsensitiveContains(targetTitle) ? 0 : 1_000
        } else {
            titlePenalty = 0
        }
        return framePenalty + titlePenalty
    }

    private func frame(for window: AXUIElement) -> WindowGeometry? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let point = extractPoint(from: positionValue),
            let size = extractSize(from: sizeValue)
        else {
            return nil
        }
        return WindowGeometry(x: point.x, y: point.y, width: size.width, height: size.height)
    }

    private func title(for window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func setValue(_ element: AXUIElement, attribute: String, value: AXValue?) throws {
        guard let value else { return }
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        guard result == .success else {
            throw MacMirrorError.commandFailed("Failed to set accessibility attribute \(attribute).")
        }
    }

    private func setBoolean(_ element: AXUIElement, attribute: String, value: Bool) throws {
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value as CFBoolean)
        guard result == .success else {
            throw MacMirrorError.commandFailed("Failed to set accessibility attribute \(attribute).")
        }
    }

    private func extractPoint(from value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func extractSize(from value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}

private func AXValueCreate(_ type: AXValueType, _ doubles: [Double]) -> AXValue? {
    switch type {
    case .cgPoint:
        var point = CGPoint(x: doubles[0], y: doubles[1])
        return AXValueCreate(type, &point)
    case .cgSize:
        var size = CGSize(width: doubles[0], height: doubles[1])
        return AXValueCreate(type, &size)
    default:
        return nil
    }
}

private extension WindowGeometry {
    func distance(to other: WindowGeometry) -> Double {
        abs(x - other.x) + abs(y - other.y) + abs(width - other.width) + abs(height - other.height)
    }
}
