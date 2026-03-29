import AppKit
import CoreGraphics
import Foundation

public final class DisplayService: Sendable {
    public init() {}

    public func currentDisplays() -> [DisplaySignature] {
        NSScreen.screens.compactMap { screen -> DisplaySignature? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            let displayID = CGDirectDisplayID(truncating: number)
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)
                .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
                ?? "display-\(displayID)"
            let frame = screen.frame
            return DisplaySignature(
                stableIdentifier: uuid,
                displayID: displayID,
                localizedName: screen.localizedName,
                originX: frame.origin.x,
                originY: frame.origin.y,
                width: frame.width,
                height: frame.height,
                isPrimary: screen == NSScreen.main
            )
        }
    }

    public func display(containing geometry: WindowGeometry, displays: [DisplaySignature]) -> DisplaySignature? {
        let center = CGPoint(x: geometry.x + (geometry.width / 2), y: geometry.y + (geometry.height / 2))
        if let directHit = displays.first(where: { $0.rect.contains(center) }) {
            return directHit
        }

        return displays.min {
            center.distance(to: $0.rect.center) < center.distance(to: $1.rect.center)
        }
    }

    public func mapDisplays(saved: [DisplaySignature], current: [DisplaySignature]) -> [String: DisplayMapping] {
        var mappings: [String: DisplayMapping] = [:]
        var usedCurrentIDs = Set<String>()

        for savedDisplay in saved {
            if let exact = current.first(where: { $0.stableIdentifier == savedDisplay.stableIdentifier }) {
                mappings[savedDisplay.stableIdentifier] = DisplayMapping(saved: savedDisplay, current: exact, usedFallback: false)
                usedCurrentIDs.insert(exact.stableIdentifier)
                continue
            }

            let fallback = current
                .filter { usedCurrentIDs.contains($0.stableIdentifier) == false }
                .min { candidateA, candidateB in
                    displayDistance(savedDisplay, candidateA) < displayDistance(savedDisplay, candidateB)
                } ?? current.first

            if let fallback {
                mappings[savedDisplay.stableIdentifier] = DisplayMapping(saved: savedDisplay, current: fallback, usedFallback: true)
                usedCurrentIDs.insert(fallback.stableIdentifier)
            }
        }

        return mappings
    }

    private func displayDistance(_ lhs: DisplaySignature, _ rhs: DisplaySignature) -> Double {
        let sizeDelta = abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
        let originDelta = abs(lhs.originX - rhs.originX) + abs(lhs.originY - rhs.originY)
        return sizeDelta + originDelta + (lhs.localizedName == rhs.localizedName ? 0 : 500)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> Double {
        let dx = Double(x - point.x)
        let dy = Double(y - point.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
