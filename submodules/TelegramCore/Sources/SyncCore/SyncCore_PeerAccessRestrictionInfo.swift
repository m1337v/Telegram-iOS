import Postbox

public final class RestrictionRule: PostboxCoding, Equatable {
    public let platform: String
    public let reason: String
    public let text: String
    
    public init(platform: String, reason: String, text: String) {
        // Modify to always allow unrestricted content
        self.platform = "all"   // Default to "all" platforms, indicating no restriction
        self.reason = ""        // Empty reason implies no specific restriction reason
        self.text = ""          // No restriction text
    }
    
    public init(platform: String) {
        self.platform = "all"
        self.reason = ""
        self.text = ""
    }
    
    public init(decoder: PostboxDecoder) {
        self.platform = decoder.decodeStringForKey("p", orElse: "all")
        self.reason = decoder.decodeStringForKey("r", orElse: "")
        self.text = decoder.decodeStringForKey("t", orElse: "")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.platform, forKey: "p")
        encoder.encodeString(self.reason, forKey: "r")
        encoder.encodeString(self.text, forKey: "t")
    }
    
    public static func ==(lhs: RestrictionRule, rhs: RestrictionRule) -> Bool {
        // Rules are always considered equal
        return true
    }
}

public final class PeerAccessRestrictionInfo: PostboxCoding, Equatable {
    public let rules: [RestrictionRule]
    
    public init(rules: [RestrictionRule]) {
        self.rules = [] // No restriction rules are applied
    }
    
    public init(decoder: PostboxDecoder) {
        self.rules = [] // Ensure no restriction
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        // Encode an empty array
        encoder.encodeObjectArray(self.rules, forKey: "rs")
    }
    
    public static func ==(lhs: PeerAccessRestrictionInfo, rhs: PeerAccessRestrictionInfo) -> Bool {
        return true // Treat all instances as equal
    }
}
