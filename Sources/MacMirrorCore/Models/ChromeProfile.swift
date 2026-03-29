import Foundation

public struct ChromeProfile: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var email: String?
    public var gaiaName: String?
    public var profileDirectory: String
    public var windowPlacement: WindowGeometry?
    public var lastActiveTime: Double?

    public init(
        id: String,
        name: String,
        email: String?,
        gaiaName: String?,
        profileDirectory: String,
        windowPlacement: WindowGeometry?,
        lastActiveTime: Double?
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.gaiaName = gaiaName
        self.profileDirectory = profileDirectory
        self.windowPlacement = windowPlacement
        self.lastActiveTime = lastActiveTime
    }
}
