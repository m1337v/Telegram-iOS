import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import Markdown

public final class AdInfoScreen: ViewController {
    private final class Node: ViewControllerTracingNode {
        private weak var controller: AdInfoScreen?
        private let context: AccountContext
        private var presentationData: PresentationData

        private let titleNode: ImmediateTextNode

        private final class LinkNode: HighlightableButtonNode {
            private let backgroundNode: ASImageNode
            private let textNode: ImmediateTextNode

            private let action: () -> Void

            init(text: String, color: UIColor, action: @escaping () -> Void) {
                self.action = action

                self.backgroundNode = ASImageNode()
                self.backgroundNode.image = generateStretchableFilledCircleImage(diameter: 10.0, color: nil, strokeColor: color, strokeWidth: 1.0, backgroundColor: nil)

                self.textNode = ImmediateTextNode()
                self.textNode.maximumNumberOfLines = 1
                self.textNode.attributedText = NSAttributedString(string: text, font: Font.regular(16.0), textColor: color)

                super.init()

                self.addSubnode(self.backgroundNode)
                self.addSubnode(self.textNode)

                self.addTarget(self, action:#selector(self.pressed), forControlEvents: .touchUpInside)
            }

            @objc private func pressed() {
                self.action()
            }

            func update(width: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
                let size = CGSize(width: width, height: 44.0)

                transition.updateFrame(node: self.backgroundNode, frame: CGRect(origin: CGPoint(), size: size))

                let textSize = self.textNode.updateLayout(CGSize(width: width - 8.0 * 2.0, height: 44.0))
                transition.updateFrameAdditiveToCenter(node: self.textNode, frame: CGRect(origin: CGPoint(x: floor((size.width - textSize.width) / 2.0), y: floor((size.height - textSize.height) / 2.0)), size: textSize))

                return size.height
            }
        }

        private enum Item {
            case text(ImmediateTextNode)
            case link(LinkNode)
        }
        private let items: [Item]

        private let scrollNode: ASScrollNode

        init(controller: AdInfoScreen, context: AccountContext) {
            self.controller = controller
            self.context = context

            self.presentationData = controller.presentationData

            self.titleNode = ImmediateTextNode()
            self.titleNode.maximumNumberOfLines = 1
            self.titleNode.attributedText = NSAttributedString(string: self.presentationData.strings.SponsoredMessageInfoScreen_Title, font: NavigationBar.titleFont, textColor: self.presentationData.theme.rootController.navigationBar.primaryTextColor)

            self.scrollNode = ASScrollNode()
            self.scrollNode.view.showsVerticalScrollIndicator = true
            self.scrollNode.view.showsHorizontalScrollIndicator = false
            self.scrollNode.view.scrollsToTop = true
            self.scrollNode.view.delaysContentTouches = false
            self.scrollNode.view.canCancelContentTouches = true
            if #available(iOS 11.0, *) {
                self.scrollNode.view.contentInsetAdjustmentBehavior = .never
            }

            var openUrl: ((String) -> Void)?

            #if DEBUG && false
            let rawText = "First Line\n**Bold Text** [Description](http://google.com) text\n[url]\nabcdee"
            #else
            let rawText = self.presentationData.strings.SponsoredMessageInfoScreen_MarkdownText
            #endif
            
            let defaultUrl = self.presentationData.strings.SponsoredMessageInfo_Url
            
            var items: [Item] = []
            var didAddUrl = false
            for component in rawText.components(separatedBy: "[url]") {
                var itemText = component
                if itemText.hasPrefix("\n") {
                    itemText = String(itemText[itemText.index(itemText.startIndex, offsetBy: 1)...])
                }
                if itemText.hasSuffix("\n") {
                    itemText = String(itemText[..<itemText.index(itemText.endIndex, offsetBy: -1)])
                }

                let textNode = ImmediateTextNode()
                textNode.maximumNumberOfLines = 0
                textNode.attributedText = parseMarkdownIntoAttributedString(itemText, attributes: MarkdownAttributes(
                    body: MarkdownAttributeSet(font: Font.regular(16.0), textColor: self.presentationData.theme.list.itemPrimaryTextColor),
                    bold: MarkdownAttributeSet(font: Font.semibold(16.0), textColor: self.presentationData.theme.list.itemPrimaryTextColor),
                    link: MarkdownAttributeSet(font: Font.regular(16.0), textColor: self.presentationData.theme.list.itemAccentColor),
                    linkAttribute: { url in
                        return ("URL", url)
                    }
                ))
                items.append(.text(textNode))
                textNode.highlightAttributeAction = { attributes in
                    if let _ = attributes[NSAttributedString.Key(rawValue: "URL")] {
                        return NSAttributedString.Key(rawValue: "URL")
                    } else {
                        return nil
                    }
                }
                textNode.tapAttributeAction = { attributes, _ in
                    if let value = attributes[NSAttributedString.Key(rawValue: "URL")] as? String {
                        openUrl?(value)
                    }
                }
                textNode.linkHighlightColor = self.presentationData.theme.list.itemAccentColor.withAlphaComponent(0.2)

                if !didAddUrl {
                    didAddUrl = true
                    items.append(.link(LinkNode(text: self.presentationData.strings.SponsoredMessageInfo_Url, color: self.presentationData.theme.list.itemAccentColor, action: {
                        openUrl?(defaultUrl)
                    })))
                }
            }
            if !didAddUrl {
                didAddUrl = true
                items.append(.link(LinkNode(text: self.presentationData.strings.SponsoredMessageInfo_Url, color: self.presentationData.theme.list.itemAccentColor, action: {
                    openUrl?(defaultUrl)
                })))
            }
            self.items = items

            super.init()

            self.backgroundColor = self.presentationData.theme.list.plainBackgroundColor

            self.addSubnode(self.scrollNode)

            for item in self.items {
                switch item {
                case let .text(text):
                    self.scrollNode.addSubnode(text)
                case let .link(link):
                    self.scrollNode.addSubnode(link)
                }
            }

            openUrl = { [weak self] url in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.context.sharedContext.applicationBindings.openUrl(url)
            }
        }

        func containerLayoutUpdated(layout: ContainerViewLayout, navigationHeight: CGFloat, transition: ContainedViewLayoutTransition) {
            if self.titleNode.supernode == nil {
                self.addSubnode(self.titleNode)
            }
            let titleSize = self.titleNode.updateLayout(CGSize(width: layout.size.width - layout.safeInsets.left * 2.0 - 80.0 - 16.0 * 2.0, height: 100.0))
            transition.updateFrameAdditive(node: self.titleNode, frame: CGRect(origin: CGPoint(x: layout.safeInsets.left + 16.0, y: floor((navigationHeight - titleSize.height) / 2.0)), size: titleSize))

            transition.updateFrame(node: self.scrollNode, frame: CGRect(origin: CGPoint(), size: layout.size))
            self.scrollNode.view.scrollIndicatorInsets = UIEdgeInsets(top: navigationHeight, left: 0.0, bottom: 0.0, right: 0.0)

            let sideInset: CGFloat = layout.safeInsets.left + 16.0
            let maxWidth: CGFloat = layout.size.width - sideInset * 2.0
            var contentHeight: CGFloat = navigationHeight + 16.0

            for item in self.items {
                switch item {
                case let .text(text):
                    let textSize = text.updateLayout(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
                    transition.updateFrameAdditive(node: text, frame: CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: textSize))
                    contentHeight += textSize.height
                case let .link(link):
                    let linkHeight = link.update(width: maxWidth, transition: transition)
                    let linkSize = CGSize(width: maxWidth, height: linkHeight)
                    contentHeight += 16.0
                    transition.updateFrame(node: link, frame: CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: linkSize))
                    contentHeight += linkSize.height
                    contentHeight += 16.0
                }
            }

            contentHeight += 16.0
            contentHeight += layout.intrinsicInsets.bottom

            self.scrollNode.view.contentSize = CGSize(width: layout.size.width, height: contentHeight)
        }
    }

    private var node: Node {
        return self.displayNode as! Node
    }

    private let context: AccountContext
    fileprivate var presentationData: PresentationData

    public init(context: AccountContext, forceDark: Bool = false) {
        self.context = context
        
        var presentationData = context.sharedContext.currentPresentationData.with { $0 }
        if forceDark {
            presentationData = presentationData.withUpdated(theme: defaultDarkColorPresentationTheme)
        }
        self.presentationData = presentationData

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.navigationPresentation = .modal

        self.navigationItem.setLeftBarButton(UIBarButtonItem(title: "", style: .plain, target: self, action: #selector(self.noAction)), animated: false)
        self.navigationItem.setRightBarButton(UIBarButtonItem(title: self.presentationData.strings.Common_Done, style: .done, target: self, action: #selector(self.donePressed)), animated: false)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func noAction() {
    }

    @objc private func donePressed() {
        self.dismiss()
    }

    override public func loadDisplayNode() {
        self.displayNode = Node(controller: self, context: self.context)

        super.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.node.containerLayoutUpdated(layout: layout, navigationHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
}
