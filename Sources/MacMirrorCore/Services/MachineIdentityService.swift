import Foundation
import IOKit

public enum MachineIdentityService {
    public static func currentMachineIdentifier() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != IO_OBJECT_NULL else {
            return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        }
        defer { IOObjectRelease(service) }

        guard
            let value = IORegistryEntryCreateCFProperty(
                service,
                "IOPlatformUUID" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String
        else {
            return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        }
        return value
    }
}
