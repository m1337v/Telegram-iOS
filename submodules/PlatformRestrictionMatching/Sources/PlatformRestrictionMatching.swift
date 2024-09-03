import Foundation
import TelegramCore
import Postbox

public extension Message {
    // Override to always return false for testing, indicating no content is restricted
    func isRestricted(platform: String, contentSettings: ContentSettings) -> Bool {
        return false  // No restrictions applied
    }
    
    // Override to return nil for testing, indicating no restriction reason
    func restrictionReason(platform: String, contentSettings: ContentSettings) -> String? {
        return nil  // No restriction reason
    }
}

public extension RestrictedContentMessageAttribute {
    // Override to always return nil for testing, indicating no platform-specific restriction text
    func platformText(platform: String, contentSettings: ContentSettings) -> String? {
        return nil  // No restriction text
    }
}
