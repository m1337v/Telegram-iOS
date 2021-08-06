import Foundation
import UIKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import SearchBarNode
import SearchUI
import ContactListUI
import ChatListUI
import SegmentedControlNode

final class PeerSelectionControllerNode: ASDisplayNode {
    private let context: AccountContext
    private let present: (ViewController, Any?) -> Void
    private let presentInGlobalOverlay: (ViewController, Any?) -> Void
    private let dismiss: () -> Void
    private let filter: ChatListNodePeersFilter
    private let hasGlobalSearch: Bool
    
    private var presentationInterfaceState: ChatPresentationInterfaceState
    private var interfaceInteraction: ChatPanelInterfaceInteraction?
    
    var inProgress: Bool = false {
        didSet {
            
        }
    }
    
    var navigationBar: NavigationBar?
    
    private let toolbarBackgroundNode: NavigationBackgroundNode?
    private let toolbarSeparatorNode: ASDisplayNode?
    private let segmentedControlNode: SegmentedControlNode?
    
    private var textInputPanelNode: PeerSelectionTextInputPanelNode?
    
    var contactListNode: ContactListNode?
    let chatListNode: ChatListNode
    
    private var contactListActive = false
    
    private var searchDisplayController: SearchDisplayController?
    
    private var containerLayout: (ContainerViewLayout, CGFloat, CGFloat)?
    
    var contentOffsetChanged: ((ListViewVisibleContentOffset) -> Void)?
    var contentScrollingEnded: ((ListView) -> Bool)?
    
    var requestActivateSearch: (() -> Void)?
    var requestDeactivateSearch: (() -> Void)?
    var requestOpenPeer: ((Peer) -> Void)?
    var requestOpenDisabledPeer: ((Peer) -> Void)?
    var requestOpenPeerFromSearch: ((Peer) -> Void)?
    var requestOpenMessageFromSearch: ((Peer, MessageId) -> Void)?
    var requestSend: (([Peer], [PeerId: Peer], NSAttributedString, PeerSelectionControllerSendMode) -> Void)?
    
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    
    private var readyValue = Promise<Bool>()
    var ready: Signal<Bool, NoError> {
        return self.readyValue.get()
    }
    
    init(context: AccountContext, filter: ChatListNodePeersFilter, hasChatListSelector: Bool, hasContactSelector: Bool, hasGlobalSearch: Bool, createNewGroup: (() -> Void)?, present: @escaping (ViewController, Any?) -> Void,  presentInGlobalOverlay: @escaping (ViewController, Any?) -> Void, dismiss: @escaping () -> Void) {
        self.context = context
        self.present = present
        self.presentInGlobalOverlay = presentInGlobalOverlay
        self.dismiss = dismiss
        self.filter = filter
        self.hasGlobalSearch = hasGlobalSearch
        
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData
        
        self.presentationInterfaceState = ChatPresentationInterfaceState(chatWallpaper: .builtin(WallpaperSettings()), theme: self.presentationData.theme, strings: self.presentationData.strings, dateTimeFormat: self.presentationData.dateTimeFormat, nameDisplayOrder: self.presentationData.nameDisplayOrder, limitsConfiguration: self.context.currentLimitsConfiguration.with { $0 }, fontSize: self.presentationData.chatFontSize, bubbleCorners: self.presentationData.chatBubbleCorners, accountPeerId: self.context.account.peerId, mode: .standard(previewing: false), chatLocation: .peer(PeerId(0)), subject: nil, peerNearbyData: nil, greetingData: nil, pendingUnpinnedAllMessages: false, activeGroupCallInfo: nil, hasActiveGroupCall: false, importState: nil)
        
        if hasChatListSelector && hasContactSelector {
            self.toolbarBackgroundNode = NavigationBackgroundNode(color: self.presentationData.theme.rootController.navigationBar.blurredBackgroundColor)
            
            self.toolbarSeparatorNode = ASDisplayNode()
            self.toolbarSeparatorNode?.backgroundColor = self.presentationData.theme.rootController.navigationBar.separatorColor
            
            let items = [
                self.presentationData.strings.DialogList_TabTitle,
                self.presentationData.strings.Contacts_TabTitle
            ]
            self.segmentedControlNode = SegmentedControlNode(theme: SegmentedControlTheme(theme: self.presentationData.theme), items: items.map { SegmentedControlItem(title: $0) }, selectedIndex: 0)
        } else {
            self.toolbarBackgroundNode = nil
            self.toolbarSeparatorNode = nil
            self.segmentedControlNode = nil
        }
        
        var chatListcategories: [ChatListNodeAdditionalCategory] = []
        
        if let _ = createNewGroup {
            chatListcategories.append(ChatListNodeAdditionalCategory(id: 0, icon: PresentationResourcesItemList.createGroupIcon(self.presentationData.theme), title: self.presentationData.strings.PeerSelection_ImportIntoNewGroup, appearance: .action))
        }
       
        self.chatListNode = ChatListNode(context: context, groupId: .root, previewing: false, fillPreloadItems: false, mode: .peers(filter: filter, isSelecting: false, additionalCategories: chatListcategories, chatListFilters: nil), theme: self.presentationData.theme, fontSize: presentationData.listsFontSize, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, nameSortOrder: presentationData.nameSortOrder, nameDisplayOrder: presentationData.nameDisplayOrder, disableAnimations: true)
        
        super.init()
        
        self.setViewBlock({
            return UITracingLayerView()
        })
        
        self.chatListNode.additionalCategorySelected = { _ in
            createNewGroup?()
        }
        
        self.backgroundColor = self.presentationData.theme.chatList.backgroundColor
        
        self.chatListNode.selectionCountChanged = { [weak self] count in
            self?.textInputPanelNode?.updateSendButtonEnabled(count > 0, animated: true)
        }
        self.chatListNode.accessibilityPageScrolledString = { row, count in
            return presentationData.strings.VoiceOver_ScrollStatus(row, count).string
        }
        
        self.chatListNode.activateSearch = { [weak self] in
            self?.requestActivateSearch?()
        }
        
        self.chatListNode.peerSelected = { [weak self] peer, _, _, _ in
            self?.chatListNode.clearHighlightAnimated(true)
            self?.requestOpenPeer?(peer)
        }
        
        self.chatListNode.disabledPeerSelected = { [weak self] peer in
            self?.requestOpenDisabledPeer?(peer)
        }
        
        self.chatListNode.contentOffsetChanged = { [weak self] offset in
            guard let strongSelf = self else {
                return
            }
            if strongSelf.chatListNode.supernode != nil {
                strongSelf.contentOffsetChanged?(offset)
            }
        }
        
        self.chatListNode.contentScrollingEnded = { [weak self] listView in
            return self?.contentScrollingEnded?(listView) ?? false
        }
        
        self.addSubnode(self.chatListNode)
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                let previousTheme = strongSelf.presentationData.theme
                let previousStrings = strongSelf.presentationData.strings
                strongSelf.presentationData = presentationData
                if previousTheme !== presentationData.theme || previousStrings !== presentationData.strings {
                    strongSelf.updateThemeAndStrings()
                }
            }
        })
        
        if hasChatListSelector && hasContactSelector {
            self.segmentedControlNode!.selectedIndexChanged = { [weak self] index in
                self?.indexChanged(index)
            }
            
            self.addSubnode(self.toolbarBackgroundNode!)
            self.addSubnode(self.toolbarSeparatorNode!)
            self.addSubnode(self.segmentedControlNode!)
        }
        
        if !hasChatListSelector && hasContactSelector {
            self.indexChanged(1)
        }
     
        self.interfaceInteraction = ChatPanelInterfaceInteraction(cloudMessages: { _ in }, copyForwardMessages: { _ in }, setupReplyMessage: { _, _ in
        }, setupEditMessage: { _, _ in
        }, beginMessageSelection: { _, _ in
        }, deleteSelectedMessages: {
        }, reportSelectedMessages: {
        }, reportMessages: { _, _ in
        }, blockMessageAuthor: { _, _ in
        }, deleteMessages: { _, _, f in
            f(.default)
        }, forwardSelectedMessages: {
        }, forwardCurrentForwardMessages: {
        }, forwardMessages: { _ in
        }, shareSelectedMessages: {
        }, updateTextInputStateAndMode: { [weak self] f in
            if let strongSelf = self {
                strongSelf.updateChatPresentationInterfaceState(animated: true, { state in
                    let (updatedState, updatedMode) = f(state.interfaceState.effectiveInputState, state.inputMode)
                    return state.updatedInterfaceState { interfaceState in
                        return interfaceState.withUpdatedEffectiveInputState(updatedState)
                    }.updatedInputMode({ _ in updatedMode })
                })
            }
        }, updateInputModeAndDismissedButtonKeyboardMessageId: { [weak self] f in
            if let strongSelf = self {
                strongSelf.updateChatPresentationInterfaceState(animated: true, {
                    let (updatedInputMode, updatedClosedButtonKeyboardMessageId) = f($0)
                    return $0.updatedInputMode({ _ in return updatedInputMode }).updatedInterfaceState({
                        $0.withUpdatedMessageActionsState({ value in
                            var value = value
                            value.closedButtonKeyboardMessageId = updatedClosedButtonKeyboardMessageId
                            return value
                        })
                    })
                })
            }
        }, openStickers: {
        }, editMessage: {
        }, beginMessageSearch: { _, _ in
        }, dismissMessageSearch: {
        }, updateMessageSearch: { _ in
        }, openSearchResults: {
        }, navigateMessageSearch: { _ in
        }, openCalendarSearch: {
        }, toggleMembersSearch: { _ in
        }, navigateToMessage: { _, _, _, _ in
        }, navigateToChat: { _ in
        }, navigateToProfile: { _ in
        }, openPeerInfo: {
        }, togglePeerNotifications: {
        }, sendContextResult: { _, _, _, _ in
            return false
        }, sendBotCommand: { _, _ in
        }, sendBotStart: { _ in
        }, botSwitchChatWithPayload: { _, _ in
        }, beginMediaRecording: { _ in
        }, finishMediaRecording: { _ in
        }, stopMediaRecording: {
        }, lockMediaRecording: {
        }, deleteRecordedMedia: {
        }, sendRecordedMedia: { _ in
        }, displayRestrictedInfo: { _, _ in
        }, displayVideoUnmuteTip: { _ in
        }, switchMediaRecordingMode: {
        }, setupMessageAutoremoveTimeout: {
        }, sendSticker: { _, _, _, _ in
            return false
        }, unblockPeer: {
        }, pinMessage: { _, _ in
        }, unpinMessage: { _, _, _ in
        }, unpinAllMessages: {
        }, openPinnedList: { _ in
        }, shareAccountContact: {
        }, reportPeer: {
        }, presentPeerContact: {
        }, dismissReportPeer: {
        }, deleteChat: {
        }, beginCall: { _ in
        }, toggleMessageStickerStarred: { _ in
        }, presentController: { _, _ in
        }, getNavigationController: {
            return nil
        }, presentGlobalOverlayController: { _, _ in
        }, navigateFeed: {
        }, openGrouping: {
        }, toggleSilentPost: {
        }, requestUnvoteInMessage: { _ in
        }, requestStopPollInMessage: { _ in
        }, updateInputLanguage: { _ in
        }, unarchiveChat: {
        }, openLinkEditing: {
        }, reportPeerIrrelevantGeoLocation: {
        }, displaySlowmodeTooltip: { _, _ in
        }, displaySendMessageOptions: { [weak self] node, gesture in
            guard let strongSelf = self, let textInputPanelNode = strongSelf.textInputPanelNode else {
                return
            }
            textInputPanelNode.loadTextInputNodeIfNeeded()
            guard let textInputNode = textInputPanelNode.textInputNode else {
                return
            }
//            let previousSupportedOrientations = strongSelf.supportedOrientations
//            if layout.size.width > layout.size.height {
//                strongSelf.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .landscape)
//            } else {
//                strongSelf.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
//            }
            
            let controller = ChatSendMessageActionSheetController(context: strongSelf.context, interfaceState: strongSelf.presentationInterfaceState, gesture: gesture, sourceSendButton: node, textInputNode: textInputNode, completion: { [weak self] in
                if let strongSelf = self {
//                    strongSelf.supportedOrientations = previousSupportedOrientations
                }
            }, sendMessage: { [weak textInputPanelNode] silently in
                textInputPanelNode?.sendMessage(silently ? .silent : .generic)
            }, schedule: { [weak textInputPanelNode] in
                textInputPanelNode?.sendMessage(.schedule)
            })
//            strongSelf.sendMessageActionsController = controller
            strongSelf.presentInGlobalOverlay(controller, nil)
        }, openScheduledMessages: {
        }, openPeersNearby: {
        }, displaySearchResultsTooltip: { _, _ in
        }, unarchivePeer: {
        }, scrollToTop: {
        }, viewReplies: { _, _ in
        }, activatePinnedListPreview: { _, _ in
        }, joinGroupCall: { _ in
        }, presentInviteMembers: {
        }, presentGigagroupHelp: {
        }, editMessageMedia: { _, _ in
        }, updateShowCommands: { _ in }, statuses: nil)
        
        self.readyValue.set(self.chatListNode.ready)
    }
    
    deinit {
        self.presentationDataDisposable?.dispose()
    }
    
    private func updateChatPresentationInterfaceState(animated: Bool = true, _ f: (ChatPresentationInterfaceState) -> ChatPresentationInterfaceState, completion: @escaping (ContainedViewLayoutTransition) -> Void = { _ in }) {
        self.updateChatPresentationInterfaceState(transition: animated ? .animated(duration: 0.4, curve: .spring) : .immediate, f, completion: completion)
    }
    
    private func updateChatPresentationInterfaceState(transition: ContainedViewLayoutTransition, _ f: (ChatPresentationInterfaceState) -> ChatPresentationInterfaceState, completion externalCompletion: @escaping (ContainedViewLayoutTransition) -> Void = { _ in }) {
        let presentationInterfaceState = f(self.presentationInterfaceState)
        let updateInputTextState = self.presentationInterfaceState.interfaceState.effectiveInputState != presentationInterfaceState.interfaceState.effectiveInputState
        
        self.presentationInterfaceState = presentationInterfaceState
        
        if let textInputPanelNode = self.textInputPanelNode, updateInputTextState {
            textInputPanelNode.updateInputTextState(presentationInterfaceState.interfaceState.effectiveInputState, animated: transition.isAnimated)
        }
        
        if let (layout, navigationBarHeight, actualNavigationBarHeight) = self.containerLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, actualNavigationBarHeight: actualNavigationBarHeight, transition: transition)
        }
    }
    
    func beginSelection() {
        if let _ = self.textInputPanelNode {
        } else {
            let textInputPanelNode = PeerSelectionTextInputPanelNode(presentationInterfaceState: self.presentationInterfaceState, presentController: { [weak self] c in self?.present(c, nil) })
            textInputPanelNode.interfaceInteraction = self.interfaceInteraction
            textInputPanelNode.sendMessage = { [weak self] mode in
                guard let strongSelf = self else {
                    return
                }
                
                if strongSelf.contactListActive {
                    strongSelf.contactListNode?.multipleSelection = true
                    let selectedContactPeers = strongSelf.contactListNode?.selectedPeers ?? []
                    let effectiveInputText = strongSelf.presentationInterfaceState.interfaceState.composeInputState.inputText
                    var selectedPeers: [Peer] = []
                    var selectedPeerMap: [PeerId: Peer] = [:]
                    for contactPeer in selectedContactPeers {
                        if case let .peer(peer, _, _) = contactPeer {
                            selectedPeers.append(peer)
                            selectedPeerMap[peer.id] = peer
                        }
                    }
                    if !selectedPeers.isEmpty {
                        strongSelf.requestSend?(selectedPeers, selectedPeerMap, effectiveInputText, mode)
                    }
                } else {
                    var selectedPeerIds: [PeerId] = []
                    var selectedPeerMap: [PeerId: Peer] = [:]
                    strongSelf.chatListNode.updateState { state in
                        selectedPeerIds = Array(state.selectedPeerIds)
                        selectedPeerMap = state.selectedPeerMap
                        return state
                    }
                    if !selectedPeerIds.isEmpty {
                        let effectiveInputText = strongSelf.presentationInterfaceState.interfaceState.composeInputState.inputText
                        var selectedPeers: [Peer] = []
                        for peerId in selectedPeerIds {
                            if let peer = selectedPeerMap[peerId] {
                                selectedPeers.append(peer)
                            }
                        }
                        strongSelf.requestSend?(selectedPeers, selectedPeerMap, effectiveInputText, mode)
                    }
                }
            }
            self.addSubnode(textInputPanelNode)
            self.textInputPanelNode = textInputPanelNode
            
            if let (layout, navigationBarHeight, actualNavigationBarHeight) = self.containerLayout {
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, actualNavigationBarHeight: actualNavigationBarHeight, transition: .animated(duration: 0.3, curve: .spring))
            }
        }
        
        if self.contactListActive {
            self.contactListNode?.updateSelectionState({ _ in
                return ContactListNodeGroupSelectionState()
            })
        } else {
            self.chatListNode.updateState { state in
                var state = state
                state.editing = true
                return state
            }
        }
    }
    
    private func updateThemeAndStrings() {
        self.backgroundColor = self.presentationData.theme.chatList.backgroundColor
        self.searchDisplayController?.updatePresentationData(self.presentationData)
        self.chatListNode.updateThemeAndStrings(theme: self.presentationData.theme, fontSize: self.presentationData.listsFontSize, strings: self.presentationData.strings, dateTimeFormat: self.presentationData.dateTimeFormat, nameSortOrder: self.presentationData.nameSortOrder, nameDisplayOrder: self.presentationData.nameDisplayOrder, disableAnimations: true)
        
        self.toolbarBackgroundNode?.updateColor(color: self.presentationData.theme.rootController.navigationBar.blurredBackgroundColor, transition: .immediate)
        self.toolbarSeparatorNode?.backgroundColor = self.presentationData.theme.rootController.navigationBar.separatorColor
        self.segmentedControlNode?.updateTheme(SegmentedControlTheme(theme: self.presentationData.theme))
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, actualNavigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.containerLayout = (layout, navigationBarHeight, actualNavigationBarHeight)
        
        let cleanInsets = layout.insets(options: [])
        var insets = layout.insets(options: [.input])
        
        var toolbarHeight: CGFloat = cleanInsets.bottom
        var textPanelHeight: CGFloat?
        
        if let textInputPanelNode = self.textInputPanelNode {
            var panelTransition = transition
            if textInputPanelNode.frame.width.isZero {
                panelTransition = .immediate
            }
            var panelHeight = textInputPanelNode.updateLayout(width: layout.size.width, leftInset: layout.safeInsets.left, rightInset: layout.safeInsets.right, additionalSideInsets: UIEdgeInsets(), maxHeight: layout.size.height / 2.0, isSecondary: false, transition: panelTransition, interfaceState: self.presentationInterfaceState, metrics: layout.metrics)
            if self.searchDisplayController == nil {
                panelHeight += insets.bottom
            } else {
                panelHeight += cleanInsets.bottom
            }
            textPanelHeight = panelHeight
            
            let panelFrame = CGRect(x: 0.0, y: layout.size.height - panelHeight, width: layout.size.width, height: panelHeight)
            if textInputPanelNode.frame.width.isZero {
                var initialPanelFrame = panelFrame
                initialPanelFrame.origin.y = layout.size.height
                textInputPanelNode.frame = initialPanelFrame
            }
            transition.updateFrame(node: textInputPanelNode, frame: panelFrame)
        }
        
        if let segmentedControlNode = self.segmentedControlNode, let toolbarBackgroundNode = self.toolbarBackgroundNode, let toolbarSeparatorNode = self.toolbarSeparatorNode {
            if let textPanelHeight = textPanelHeight {
                toolbarHeight = textPanelHeight
            } else {
                toolbarHeight += 44.0
            }
            transition.updateFrame(node: toolbarBackgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: layout.size.height - toolbarHeight), size: CGSize(width: layout.size.width, height: toolbarHeight)))
            toolbarBackgroundNode.update(size: toolbarBackgroundNode.bounds.size, transition: transition)
            transition.updateFrame(node: toolbarSeparatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: layout.size.height - toolbarHeight), size: CGSize(width: layout.size.width, height: UIScreenPixel)))
            
            let controlSize = segmentedControlNode.updateLayout(.sizeToFit(maximumWidth: layout.size.width, minimumWidth: 200.0, height: 32.0), transition: transition)
            let controlOrigin = layout.size.height - (textPanelHeight == nil ? toolbarHeight : 0.0) + floor((44.0 - controlSize.height) / 2.0)
            transition.updateFrame(node: segmentedControlNode, frame: CGRect(origin: CGPoint(x: floor((layout.size.width - controlSize.width) / 2.0), y: controlOrigin), size: controlSize))
        }
                
        insets.top += navigationBarHeight
        insets.bottom = max(insets.bottom, cleanInsets.bottom + 44.0)
        insets.left += layout.safeInsets.left
        insets.right += layout.safeInsets.right
        
        var headerInsets = layout.insets(options: [.input])
        headerInsets.top += actualNavigationBarHeight
        headerInsets.bottom = max(headerInsets.bottom, cleanInsets.bottom)
        headerInsets.left += layout.safeInsets.left
        headerInsets.right += layout.safeInsets.right
        
        self.chatListNode.bounds = CGRect(x: 0.0, y: 0.0, width: layout.size.width, height: layout.size.height)
        self.chatListNode.position = CGPoint(x: layout.size.width / 2.0, y: layout.size.height / 2.0)
        
        let (duration, curve) = listViewAnimationDurationAndCurve(transition: transition)
        let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: layout.size, insets: insets, headerInsets: headerInsets, duration: duration, curve: curve)
        
        self.chatListNode.updateLayout(transition: transition, updateSizeAndInsets: updateSizeAndInsets)
        
        if let contactListNode = self.contactListNode {
            contactListNode.bounds = CGRect(x: 0.0, y: 0.0, width: layout.size.width, height: layout.size.height)
            contactListNode.position = CGPoint(x: layout.size.width / 2.0, y: layout.size.height / 2.0)
            
            let contactsInsets = insets
            
            contactListNode.containerLayoutUpdated(ContainerViewLayout(size: layout.size, metrics: layout.metrics, deviceMetrics: layout.deviceMetrics, intrinsicInsets: contactsInsets, safeInsets: layout.safeInsets, additionalInsets: layout.additionalInsets, statusBarHeight: layout.statusBarHeight, inputHeight: layout.inputHeight, inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging, inVoiceOver: layout.inVoiceOver), headerInsets: headerInsets, transition: transition)
        }
        
        if let searchDisplayController = self.searchDisplayController {
            searchDisplayController.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: transition)
        }
    }
    
    func activateSearch(placeholderNode: SearchBarPlaceholderNode) {
        guard let (containerLayout, navigationBarHeight, _) = self.containerLayout, let navigationBar = self.navigationBar else {
            return
        }
        
        if self.chatListNode.supernode != nil {
            self.searchDisplayController = SearchDisplayController(presentationData: self.presentationData, contentNode: ChatListSearchContainerNode(context: self.context, filter: self.filter, groupId: .root, displaySearchFilters: false, openPeer: { [weak self] peer, chatPeer, _ in
                guard let strongSelf = self else {
                    return
                }
                var updated = false
                var count = 0
                strongSelf.chatListNode.updateState { state in
                    if state.editing {
                        updated = true
                        var state = state
                        var foundPeers = state.foundPeers
                        var selectedPeerMap = state.selectedPeerMap
                        selectedPeerMap[peer.id] = peer
                        if peer is TelegramSecretChat, let chatPeer = chatPeer {
                            selectedPeerMap[chatPeer.id] = chatPeer
                        }
                        var exists = false
                        for foundPeer in foundPeers {
                            if peer.id == foundPeer.0.id {
                                exists = true
                                break
                            }
                        }
                        if !exists {
                            foundPeers.insert((peer, chatPeer), at: 0)
                        }
                        if state.selectedPeerIds.contains(peer.id) {
                            state.selectedPeerIds.remove(peer.id)
                        } else {
                            state.selectedPeerIds.insert(peer.id)
                        }
                        state.foundPeers = foundPeers
                        state.selectedPeerMap = selectedPeerMap
                        count = state.selectedPeerIds.count
                        return state
                    } else {
                        return state
                    }
                }
                if updated {
                    strongSelf.textInputPanelNode?.updateSendButtonEnabled(count > 0, animated: true)
                    strongSelf.requestDeactivateSearch?()
                } else if let requestOpenPeerFromSearch = strongSelf.requestOpenPeerFromSearch {
                    requestOpenPeerFromSearch(peer)
                }
            }, openDisabledPeer: { [weak self] peer in
                self?.requestOpenDisabledPeer?(peer)
            }, openRecentPeerOptions: { _ in
            }, openMessage: { [weak self] peer, messageId, _ in
                if let requestOpenMessageFromSearch = self?.requestOpenMessageFromSearch {
                    requestOpenMessageFromSearch(peer, messageId)
                }
            }, addContact: nil, peerContextAction: nil, present: { [weak self] c, a in
                self?.present(c, a)
            }, presentInGlobalOverlay: { _, _ in
            }, navigationController: nil), cancel: { [weak self] in
                if let requestDeactivateSearch = self?.requestDeactivateSearch {
                    requestDeactivateSearch()
                }
            })
            
            self.searchDisplayController?.containerLayoutUpdated(containerLayout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            self.searchDisplayController?.activate(insertSubnode: { [weak self, weak placeholderNode] subnode, isSearchBar in
                if let strongSelf = self, let strongPlaceholderNode = placeholderNode {
                    if isSearchBar {
                        strongPlaceholderNode.supernode?.insertSubnode(subnode, aboveSubnode: strongPlaceholderNode)
                    } else {
                        strongSelf.insertSubnode(subnode, belowSubnode: navigationBar)
                    }
                }
            }, placeholder: placeholderNode)
            
        } else if let contactListNode = self.contactListNode, contactListNode.supernode != nil {
            var categories: ContactsSearchCategories = [.cloudContacts]
            if self.hasGlobalSearch {
                categories.insert(.global)
            }
            self.searchDisplayController = SearchDisplayController(presentationData: self.presentationData, contentNode: ContactsSearchContainerNode(context: self.context, onlyWriteable: true, categories: categories, addContact: nil, openPeer: { [weak self] peer in
                if let strongSelf = self {
                    var updated = false
                    var count = 0
                    strongSelf.contactListNode?.updateSelectionState { state -> ContactListNodeGroupSelectionState? in
                        if let state = state {
                            updated = true
                            var foundPeers = state.foundPeers
                            var selectedPeerMap = state.selectedPeerMap
                            selectedPeerMap[peer.id] = peer
                            var exists = false
                            for foundPeer in foundPeers {
                                if peer.id == foundPeer.id {
                                    exists = true
                                    break
                                }
                            }
                            if !exists {
                                foundPeers.insert(peer, at: 0)
                            }
                            let updatedState = state.withToggledPeerId(peer.id).withFoundPeers(foundPeers).withSelectedPeerMap(selectedPeerMap)
                            count = updatedState.selectedPeerIndices.count
                            return updatedState
                        } else {
                            return nil
                        }
                    }
                    
                    if updated {
                        strongSelf.textInputPanelNode?.updateSendButtonEnabled(count > 0, animated: true)
                        strongSelf.requestDeactivateSearch?()
                    } else {
                        switch peer {
                            case let .peer(peer, _, _):
                                let _ = (strongSelf.context.account.postbox.transaction { transaction -> Peer? in
                                    return transaction.getPeer(peer.id)
                                } |> deliverOnMainQueue).start(next: { peer in
                                    if let strongSelf = self, let peer = peer {
                                        strongSelf.requestOpenPeerFromSearch?(peer)
                                    }
                                })
                            case .deviceContact:
                                break
                        }
                    }
                }
            }, contextAction: nil), cancel: { [weak self] in
                if let requestDeactivateSearch = self?.requestDeactivateSearch {
                    requestDeactivateSearch()
                }
            })
            
            self.searchDisplayController?.containerLayoutUpdated(containerLayout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            self.searchDisplayController?.activate(insertSubnode: { [weak self, weak placeholderNode] subnode, isSearchBar in
                if let strongSelf = self, let strongPlaceholderNode = placeholderNode {
                    if isSearchBar {
                        strongPlaceholderNode.supernode?.insertSubnode(subnode, aboveSubnode: strongPlaceholderNode)
                    } else {
                        strongSelf.insertSubnode(subnode, belowSubnode: navigationBar)
                    }
                }
            }, placeholder: placeholderNode)
        }
    }
    
    func deactivateSearch(placeholderNode: SearchBarPlaceholderNode) {
        if let searchDisplayController = self.searchDisplayController {
            if self.chatListNode.supernode != nil {
                searchDisplayController.deactivate(placeholder: placeholderNode)
                self.searchDisplayController = nil
            } else if let contactListNode = self.contactListNode, contactListNode.supernode != nil {
                searchDisplayController.deactivate(placeholder: placeholderNode)
                self.searchDisplayController = nil
            }
        }
    }
    
    func scrollToTop() {
        if self.chatListNode.supernode != nil {
            self.chatListNode.scrollToPosition(.top)
        } else if let contactListNode = self.contactListNode, contactListNode.supernode != nil {
            //contactListNode.scrollToTop()
        }
    }
    
    private func indexChanged(_ index: Int) {
        let contactListActive = index == 1
        if contactListActive != self.contactListActive {
            self.contactListActive = contactListActive
            if contactListActive {
                if let contactListNode = self.contactListNode {
                    self.insertSubnode(contactListNode, aboveSubnode: self.chatListNode)
                    self.chatListNode.removeFromSupernode()
                    self.recursivelyEnsureDisplaySynchronously(true)
                    contactListNode.enableUpdates = true
                } else {
                    let contactListNode = ContactListNode(context: context, presentation: .single(.natural(options: [], includeChatList: false)))
                    self.contactListNode = contactListNode
                    contactListNode.enableUpdates = true
                    contactListNode.selectionStateUpdated = { [weak self] selectionState in
                        if let strongSelf = self {
                            strongSelf.textInputPanelNode?.updateSendButtonEnabled((selectionState?.selectedPeerIndices.count ?? 0) > 0, animated: true)
                        }
                    }
                    contactListNode.activateSearch = { [weak self] in
                        self?.requestActivateSearch?()
                    }
                    contactListNode.openPeer = { [weak self] peer, _ in
                        if case let .peer(peer, _, _) = peer {
                            self?.contactListNode?.listNode.clearHighlightAnimated(true)
                            self?.requestOpenPeer?(peer)
                        }
                    }
                    contactListNode.suppressPermissionWarning = { [weak self] in
                        if let strongSelf = self {
                            strongSelf.context.sharedContext.presentContactsWarningSuppression(context: strongSelf.context, present: { c, a in
                                strongSelf.present(c, a)
                            })
                        }
                    }
                    contactListNode.contentOffsetChanged = { [weak self] offset in
                        guard let strongSelf = self else {
                            return
                        }
                        if strongSelf.contactListNode?.supernode != nil {
                            strongSelf.contentOffsetChanged?(offset)
                        }
                    }
                    
                    contactListNode.contentScrollingEnded = { [weak self] listView in
                        return self?.contentScrollingEnded?(listView) ?? false
                    }
                    
                    if let (layout, navigationHeight, actualNavigationHeight) = self.containerLayout {
                        self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, actualNavigationBarHeight: actualNavigationHeight, transition: .immediate)
                        
                        let _ = (contactListNode.ready |> deliverOnMainQueue).start(next: { [weak self] _ in
                            if let strongSelf = self {
                                if let contactListNode = strongSelf.contactListNode {
                                    strongSelf.insertSubnode(contactListNode, aboveSubnode: strongSelf.chatListNode)
                                }
                                strongSelf.chatListNode.removeFromSupernode()
                                strongSelf.recursivelyEnsureDisplaySynchronously(true)
                            }
                        })
                    } else {
                        if let contactListNode = self.contactListNode {
                            self.insertSubnode(contactListNode, aboveSubnode: self.chatListNode)
                        }
                        self.chatListNode.removeFromSupernode()
                        self.recursivelyEnsureDisplaySynchronously(true)
                    }
                }
            } else if let contactListNode = self.contactListNode {
                contactListNode.enableUpdates = false
                
                self.insertSubnode(self.chatListNode, aboveSubnode: contactListNode)
                contactListNode.removeFromSupernode()
            }
        }
    }
}
