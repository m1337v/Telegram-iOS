import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

func _internal_toggleMessageCopyProtection(account: Account, peerId: PeerId, enabled: Bool) -> Signal<Void, NoError> {
    return .complete()
}
