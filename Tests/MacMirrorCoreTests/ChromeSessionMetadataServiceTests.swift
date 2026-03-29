import Foundation
import Testing
@testable import MacMirrorCore

struct ChromeSessionMetadataServiceTests {
    @Test
    func parsesDesktopOneSessionMetadata() throws {
        let service = ChromeSessionMetadataService()
        let parsed = try service.parseSessionData(
            Data("header \(Fixture.desktopOneArchive) trailer".utf8),
            profileDirectory: "Default"
        )
        let metadata = try #require(parsed)

        #expect(metadata.profileDirectory == "Default")
        #expect(metadata.windowNumber == 4001)
        #expect(metadata.windowTitle == "Primary Inbox")
        #expect(metadata.workspaceUUID == nil)
        #expect(metadata.screenLayoutUUID == "DISPLAY-UUID-1")
        #expect(metadata.frame?.x == 15)
        #expect(metadata.frame?.y == 91)
        #expect(metadata.frame?.width == 1322)
        #expect(metadata.frame?.height == 858)
    }

    @Test
    func parsesNonPrimaryWorkspaceSessionMetadata() throws {
        let service = ChromeSessionMetadataService()
        let parsed = try service.parseSessionData(
            Data("prefix \(Fixture.secondaryArchive) suffix".utf8),
            profileDirectory: "Profile 1"
        )
        let metadata = try #require(parsed)

        #expect(metadata.profileDirectory == "Profile 1")
        #expect(metadata.windowNumber == 4002)
        #expect(metadata.windowTitle == "Secondary Window")
        #expect(metadata.workspaceUUID == "SPACE-UUID-2")
        #expect(metadata.screenLayoutUUID == "DISPLAY-UUID-2")
        #expect(metadata.frame?.x == 22)
        #expect(metadata.frame?.y == 84)
        #expect(metadata.frame?.width == 1344)
        #expect(metadata.frame?.height == 843)
    }
}

private enum Fixture {
    static let desktopOneArchive = "YnBsaXN0MDDUAQIDBAUGMjtZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKtBwgJChMZGhskJSYsL1UkbnVsbF1QcmltYXJ5IEluYm94UNMLDA0ODxFWJGNsYXNzV05TLmtleXNaTlMub2JqZWN0c4AKoRCABKESgAfTCxQVFhcYXxASTlNTY3JlZW5MYXlvdXRTaXplXxAYTlNTY3JlZW5MYXlvdXRVVUlEU3RyaW5ngAuABoAFXkRJU1BMQVktVVVJRC0xW3sxNTEyLCA5ODJ91QscHR4fICEhIiNfEBxOU1dpbmRvd0xheW91dE1vdmVHZW5lcmF0aW9uXxAeTlNXaW5kb3dMYXlvdXRSZXNpemVHZW5lcmF0aW9uXxAfTlNXaW5kb3dMYXlvdXRTY3JlZW5MYXlvdXRGcmFtZV8QGU5TV2luZG93TGF5b3V0V2luZG93RnJhbWWADBAAgAiACV8QFXt7MCwgMH0sIHsxNTEyLCA5NDl9fV8QF3t7MTUsIDkxfSwgezEzMjIsIDg1OH190icoKSpYJGNsYXNzZXNaJGNsYXNzbmFtZaIqK1xOU0RpY3Rpb25hcnlYTlNPYmplY3TSJygtLqIuK15OU1NjcmVlbkxheW91dNInKDAxojErXk5TV2luZG93TGF5b3V01DM0NTY3ODk6V05TVGl0bGVeTlNXaW5kb3dOdW1iZXJfEBNOU1dpbmRvd1dvcmtzcGFjZUlEXxAeX05TV2luZG93TGFzdFVzZXJXaW5kb3dMYXlvdXRzgAERD6GAAoADEgABhqAACAARABsAJAApADIARABSAFgAZgBnAG4AdQB9AIgAigCMAI4AkACSAJkArgDJAMsAzQDPAN4A6gD1ARQBNQFXAXMBdQF3AXkBewGTAa0BsgG7AcYByQHWAd8B5AHnAfYB+wH+Ag0CFgIeAi0CQwJkAmYCaQJrAm0AAAAAAAACAQAAAAAAAAA8AAAAAAAAAAAAAAAAAAACcg=="
    static let secondaryArchive = "YnBsaXN0MDDUAQIDBAUGMjtZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKtBwgJChMZGhskJSYsL1UkbnVsbF8QEFNlY29uZGFyeSBXaW5kb3dcU1BBQ0UtVVVJRC0y0wsMDQ4PEVYkY2xhc3NXTlMua2V5c1pOUy5vYmplY3RzgAqhEIAEoRKAB9MLFBUWFxhfEBJOU1NjcmVlbkxheW91dFNpemVfEBhOU1NjcmVlbkxheW91dFVVSURTdHJpbmeAC4AGgAVeRElTUExBWS1VVUlELTJbezE1MTIsIDk4Mn3VCxwdHh8gISEiI18QHE5TV2luZG93TGF5b3V0TW92ZUdlbmVyYXRpb25fEB5OU1dpbmRvd0xheW91dFJlc2l6ZUdlbmVyYXRpb25fEB9OU1dpbmRvd0xheW91dFNjcmVlbkxheW91dEZyYW1lXxAZTlNXaW5kb3dMYXlvdXRXaW5kb3dGcmFtZYAMEACACIAJXxAVe3swLCAwfSwgezE1MTIsIDk0OX19XxAXe3syMiwgODR9LCB7MTM0NCwgODQzfX3SJygpKlgkY2xhc3Nlc1okY2xhc3NuYW1loiorXE5TRGljdGlvbmFyeVhOU09iamVjdNInKC0uoi4rXk5TU2NyZWVuTGF5b3V00icoMDGiMSteTlNXaW5kb3dMYXlvdXTUMzQ1Njc4OTpXTlNUaXRsZV5OU1dpbmRvd051bWJlcl8QE05TV2luZG93V29ya3NwYWNlSURfEB5fTlNXaW5kb3dMYXN0VXNlcldpbmRvd0xheW91dHOAAREPooACgAMSAAGGoAAIABEAGwAkACkAMgBEAFIAWABrAHgAfwCGAI4AmQCbAJ0AnwChAKMAqgC/ANoA3ADeAOAA7wD7AQYBJQFGAWgBhAGGAYgBigGMAaQBvgHDAcwB1wHaAecB8AH1AfgCBwIMAg8CHgInAi8CPgJUAnUCdwJ6AnwCfgAAAAAAAAIBAAAAAAAAADwAAAAAAAAAAAAAAAAAAAKD"
}
