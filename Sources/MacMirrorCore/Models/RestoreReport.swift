import Foundation

public struct RestoreTargetResult: Hashable, Sendable {
    public let targetID: UUID
    public let kind: WindowTargetKind
    public let applicationName: String
    public let chromeProfileID: String?
    public let chromeProfileName: String?
    public let succeeded: Bool
    public let message: String?

    public init(
        targetID: UUID,
        kind: WindowTargetKind,
        applicationName: String,
        chromeProfileID: String?,
        chromeProfileName: String?,
        succeeded: Bool,
        message: String? = nil
    ) {
        self.targetID = targetID
        self.kind = kind
        self.applicationName = applicationName
        self.chromeProfileID = chromeProfileID
        self.chromeProfileName = chromeProfileName
        self.succeeded = succeeded
        self.message = message
    }

    public var targetDescription: String {
        if kind == .chromeProfile {
            if let chromeProfileName, chromeProfileName.isEmpty == false {
                if let chromeProfileID, chromeProfileID.isEmpty == false {
                    return "\(applicationName) [\(chromeProfileName) • \(chromeProfileID)]"
                }
                return "\(applicationName) [\(chromeProfileName)]"
            }
            if let chromeProfileID, chromeProfileID.isEmpty == false {
                return "\(applicationName) [\(chromeProfileID)]"
            }
        }
        return applicationName
    }
}

public struct RestoreReport: Hashable, Sendable {
    public let snapshotID: UUID
    public let snapshotName: String
    public let results: [RestoreTargetResult]

    public init(snapshotID: UUID, snapshotName: String, results: [RestoreTargetResult]) {
        self.snapshotID = snapshotID
        self.snapshotName = snapshotName
        self.results = results
    }

    public var totalTargets: Int {
        results.count
    }

    public var restoredCount: Int {
        results.filter(\.succeeded).count
    }

    public var failedCount: Int {
        totalTargets - restoredCount
    }

    public var failedTargets: [RestoreTargetResult] {
        results.filter { $0.succeeded == false }
    }

    public var summaryLine: String {
        if failedCount == 0 {
            return "Restored \(restoredCount) of \(totalTargets) targets."
        }
        return "Restored \(restoredCount) of \(totalTargets) targets. \(failedCount) failed."
    }
}
