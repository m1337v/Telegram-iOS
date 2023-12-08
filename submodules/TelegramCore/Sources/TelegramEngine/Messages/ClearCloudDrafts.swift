import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi


func _internal_clearCloudDraftsInteractively(postbox: Postbox, network: Network, accountPeerId: PeerId) -> Signal<Void, NoError> {
    return network.request(Api.functions.messages.getAllDrafts())
    |> retryRequest
    |> mapToSignal { updates -> Signal<Void, NoError> in
        return postbox.transaction { transaction -> Signal<Void, NoError> in
            struct Key: Hashable {
                var peerId: PeerId
                var threadId: Int64?
            }
            var keys = Set<Key>()
            switch updates {
                case let .updates(updates, users, chats, _, _):
                    let parsedPeers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                    
                    for update in updates {
                        switch update {
                            case let .updateDraftMessage(_, peer, topMsgId, _):
                                var threadId: Int64?
                                if let topMsgId = topMsgId {
                                    threadId = Int64(topMsgId)
                                }
                                keys.insert(Key(peerId: peer.peerId, threadId: threadId))
                            default:
                                break
                        }
                    }
                    updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                    
                    var signals: [Signal<Void, NoError>] = []
                    for key in keys {
                        _internal_updateChatInputState(transaction: transaction, peerId: key.peerId, threadId: key.threadId,  inputState: nil)
                        
                        if let peer = transaction.getPeer(key.peerId), let inputPeer = apiInputPeer(peer) {
                            var topMsgId: Int32?
                            if let threadId = key.threadId {
                                topMsgId = Int32(clamping: threadId)
                            }
                            var flags: Int32 = 0
                            var replyTo: Api.InputReplyTo?
                            if let topMsgId = topMsgId {
                                flags |= (1 << 0)
                                
                                var innerFlags: Int32 = 0
                                innerFlags |= 1 << 0
                                replyTo = .inputReplyToMessage(flags: innerFlags, replyToMsgId: 0, topMsgId: topMsgId, replyToPeerId: nil, quoteText: nil, quoteEntities: nil, quoteOffset: nil)
                            }
                            signals.append(network.request(Api.functions.messages.saveDraft(flags: flags, replyTo: replyTo, peer: inputPeer, message: "", entities: nil, media: nil))
                            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                                return .single(.boolFalse)
                            }
                            |> mapToSignal { _ -> Signal<Void, NoError> in
                                return .complete()
                            })
                        }
                    }
                    
                    return combineLatest(signals)
                    |> mapToSignal { _ -> Signal<Void, NoError> in
                        return .complete()
                    }
                default:
                    break
            }
            return .complete()
        } |> switchToLatest
    }
}
