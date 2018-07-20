import Foundation
#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
    import MtProtoKitMac
#else
    import Postbox
    import SwiftSignalKit
    import MtProtoKitDynamic
#endif

private final class ManagedSynchronizeSavedStickersOperationsHelper {
    var operationDisposables: [Int32: Disposable] = [:]
    
    func update(_ entries: [PeerMergedOperationLogEntry]) -> (disposeOperations: [Disposable], beginOperations: [(PeerMergedOperationLogEntry, MetaDisposable)]) {
        var disposeOperations: [Disposable] = []
        var beginOperations: [(PeerMergedOperationLogEntry, MetaDisposable)] = []
        
        var hasRunningOperationForPeerId = Set<PeerId>()
        var validMergedIndices = Set<Int32>()
        for entry in entries {
            if !hasRunningOperationForPeerId.contains(entry.peerId) {
                hasRunningOperationForPeerId.insert(entry.peerId)
                validMergedIndices.insert(entry.mergedIndex)
                
                if self.operationDisposables[entry.mergedIndex] == nil {
                    let disposable = MetaDisposable()
                    beginOperations.append((entry, disposable))
                    self.operationDisposables[entry.mergedIndex] = disposable
                }
            }
        }
        
        var removeMergedIndices: [Int32] = []
        for (mergedIndex, disposable) in self.operationDisposables {
            if !validMergedIndices.contains(mergedIndex) {
                removeMergedIndices.append(mergedIndex)
                disposeOperations.append(disposable)
            }
        }
        
        for mergedIndex in removeMergedIndices {
            self.operationDisposables.removeValue(forKey: mergedIndex)
        }
        
        return (disposeOperations, beginOperations)
    }
    
    func reset() -> [Disposable] {
        let disposables = Array(self.operationDisposables.values)
        self.operationDisposables.removeAll()
        return disposables
    }
}

private func withTakenOperation(postbox: Postbox, peerId: PeerId, tag: PeerOperationLogTag, tagLocalIndex: Int32, _ f: @escaping (Transaction, PeerMergedOperationLogEntry?) -> Signal<Void, NoError>) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Signal<Void, NoError> in
        var result: PeerMergedOperationLogEntry?
        transaction.operationLogUpdateEntry(peerId: peerId, tag: tag, tagLocalIndex: tagLocalIndex, { entry in
            if let entry = entry, let _ = entry.mergedIndex, entry.contents is SynchronizeSavedStickersOperation  {
                result = entry.mergedEntry!
                return PeerOperationLogEntryUpdate(mergedIndex: .none, contents: .none)
            } else {
                return PeerOperationLogEntryUpdate(mergedIndex: .none, contents: .none)
            }
        })
        
        return f(transaction, result)
        } |> switchToLatest
}

func managedSynchronizeSavedStickersOperations(postbox: Postbox, network: Network, revalidationContext: MediaReferenceRevalidationContext) -> Signal<Void, NoError> {
    return Signal { _ in
        let tag: PeerOperationLogTag = OperationLogTags.SynchronizeSavedStickers
        
        let helper = Atomic<ManagedSynchronizeSavedStickersOperationsHelper>(value: ManagedSynchronizeSavedStickersOperationsHelper())
        
        let disposable = postbox.mergedOperationLogView(tag: tag, limit: 10).start(next: { view in
            let (disposeOperations, beginOperations) = helper.with { helper -> (disposeOperations: [Disposable], beginOperations: [(PeerMergedOperationLogEntry, MetaDisposable)]) in
                return helper.update(view.entries)
            }
            
            for disposable in disposeOperations {
                disposable.dispose()
            }
            
            for (entry, disposable) in beginOperations {
                let signal = withTakenOperation(postbox: postbox, peerId: entry.peerId, tag: tag, tagLocalIndex: entry.tagLocalIndex, { transaction, entry -> Signal<Void, NoError> in
                    if let entry = entry {
                        if let operation = entry.contents as? SynchronizeSavedStickersOperation {
                            return synchronizeSavedStickers(transaction: transaction, postbox: postbox, network: network, revalidationContext: revalidationContext, operation: operation)
                        } else {
                            assertionFailure()
                        }
                    }
                    return .complete()
                })
                |> then(postbox.transaction { transaction -> Void in
                    let _ = transaction.operationLogRemoveEntry(peerId: entry.peerId, tag: tag, tagLocalIndex: entry.tagLocalIndex)
                })
                
                disposable.set(signal.start())
            }
        })
        
        return ActionDisposable {
            let disposables = helper.with { helper -> [Disposable] in
                return helper.reset()
            }
            for disposable in disposables {
                disposable.dispose()
            }
            disposable.dispose()
        }
    }
}

private enum SaveStickerError {
    case generic
    case invalidReference
}

private func synchronizeSavedStickers(transaction: Transaction, postbox: Postbox, network: Network, revalidationContext: MediaReferenceRevalidationContext, operation: SynchronizeSavedStickersOperation) -> Signal<Void, NoError> {
    switch operation.content {
        case let .add(id, accessHash, fileReference):
            guard let fileReference = fileReference else {
                return .complete()
            }
            
            let saveSticker: (Data) -> Signal<Api.Bool, SaveStickerError> = { fileReference in
                return network.request(Api.functions.messages.faveSticker(id: .inputDocument(id: id, accessHash: accessHash, fileReference: Buffer(data: fileReference)), unfave: .boolFalse))
                |> mapError { error -> SaveStickerError in
                    if error.errorDescription.hasPrefix("FILEREF_INVALID") || error.errorDescription.hasPrefix("FILE_REFERENCE_") {
                        return .invalidReference
                    }
                    return .generic
                }
            }
            
            let initialSignal: Signal<Api.Bool, SaveStickerError>
            if let reference = (fileReference.media.resource as? CloudDocumentMediaResource)?.fileReference {
                initialSignal = saveSticker(reference)
            } else {
                initialSignal = .fail(.invalidReference)
            }
            
            return initialSignal
            |> `catch` { error -> Signal<Api.Bool, SaveStickerError> in
                switch error {
                    case .generic:
                        return .fail(.generic)
                    case .invalidReference:
                        return revalidateMediaResourceReference(postbox: postbox, network: network, revalidationContext: revalidationContext, info: TelegramCloudMediaResourceFetchInfo(reference: fileReference.resourceReference(fileReference.media.resource)), resource: fileReference.media.resource)
                        |> mapError { _ -> SaveStickerError in
                            return .generic
                        }
                        |> mapToSignal { reference -> Signal<Api.Bool, SaveStickerError> in
                            return saveSticker(reference)
                        }
                }
            }
            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                return .complete()
            }
            |> mapToSignal { _ -> Signal<Void, NoError> in
                return .complete()
            }
        case let .remove(id, accessHash):
            return network.request(Api.functions.messages.faveSticker(id: .inputDocument(id: id, accessHash: accessHash, fileReference: Buffer()), unfave: .boolTrue))
                |> `catch` { _ -> Signal<Api.Bool, NoError> in
                    return .single(.boolFalse)
                }
                |> mapToSignal { _ -> Signal<Void, NoError> in
                    return .complete()
            }
        case .sync:
            return managedSavedStickers(postbox: postbox, network: network)
    }
}
