import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import PresentationDataUtils
import AccountContext
import ComponentFlow
import ViewControllerComponent
import MultilineTextComponent
import BalancedTextComponent
import ListSectionComponent
import ListActionItemComponent
import BundleIconComponent
import LottieComponent
import Markdown
import LocationUI
import TelegramStringFormatting
import TimezoneSelectionScreen

final class BusinessHoursSetupScreenComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment
    
    let context: AccountContext
    let initialValue: TelegramBusinessHours?
    let completion: (TelegramBusinessHours?) -> Void

    init(
        context: AccountContext,
        initialValue: TelegramBusinessHours?,
        completion: @escaping (TelegramBusinessHours?) -> Void
    ) {
        self.context = context
        self.initialValue = initialValue
        self.completion = completion
    }

    static func ==(lhs: BusinessHoursSetupScreenComponent, rhs: BusinessHoursSetupScreenComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.initialValue != rhs.initialValue {
            return false
        }

        return true
    }
    
    private final class ScrollView: UIScrollView {
        override func touchesShouldCancel(in view: UIView) -> Bool {
            return true
        }
    }
    
    struct WorkingHourRange: Equatable {
        var id: Int
        var startMinute: Int
        var endMinute: Int
        
        init(id: Int, startMinute: Int, endMinute: Int) {
            self.id = id
            self.startMinute = startMinute
            self.endMinute = endMinute
        }
    }
    
    struct Day: Equatable {
        var ranges: [WorkingHourRange]?
        
        init(ranges: [WorkingHourRange]?) {
            self.ranges = ranges
        }
    }
    
    struct DaysState: Equatable {
        enum ValidationError: Error {
            case intersectingRanges
        }
        
        var timezoneId: String
        var days: [Day]
        
        init(timezoneId: String, days: [Day]) {
            self.timezoneId = timezoneId
            self.days = days
        }
        
        init(businessHours: TelegramBusinessHours) {
            self.timezoneId = businessHours.timezoneId
            
            self.days = businessHours.splitIntoWeekDays().map { day in
                switch day {
                case .closed:
                    return Day(ranges: nil)
                case .open:
                    return Day(ranges: [])
                case let .intervals(intervals):
                    var nextIntervalId = 0
                    return Day(ranges: intervals.map { interval in
                        let intervalId = nextIntervalId
                        nextIntervalId += 1
                        return WorkingHourRange(id: intervalId, startMinute: interval.startMinute, endMinute: interval.endMinute)
                    })
                }
            }
        }
        
        func asBusinessHours() throws -> TelegramBusinessHours {
            var mappedIntervals: [TelegramBusinessHours.WorkingTimeInterval] = []
            
            var filledMinutes = IndexSet()
            for i in 0 ..< self.days.count {
                let dayStartMinute = i * 24 * 60
                guard var effectiveRanges = self.days[i].ranges else {
                    continue
                }
                if effectiveRanges.isEmpty {
                    effectiveRanges = [WorkingHourRange(id: 0, startMinute: 0, endMinute: 24 * 60)]
                }
                for range in effectiveRanges {
                    let minuteRange: Range<Int> = (dayStartMinute + range.startMinute) ..< (dayStartMinute + range.endMinute)
                    
                    var wrappedMinutes = IndexSet()
                    if minuteRange.upperBound > 7 * 24 * 60 {
                        wrappedMinutes.insert(integersIn: minuteRange.lowerBound ..< 7 * 24 * 60)
                        wrappedMinutes.insert(integersIn: 0 ..< (7 * 24 * 60 - minuteRange.upperBound))
                    } else {
                        wrappedMinutes.insert(integersIn: minuteRange)
                    }
                    
                    if !filledMinutes.intersection(wrappedMinutes).isEmpty {
                        throw ValidationError.intersectingRanges
                    }
                    filledMinutes.formUnion(wrappedMinutes)
                    mappedIntervals.append(TelegramBusinessHours.WorkingTimeInterval(startMinute: minuteRange.lowerBound, endMinute: minuteRange.upperBound))
                }
            }
            
            return TelegramBusinessHours(timezoneId: self.timezoneId, weeklyTimeIntervals: mappedIntervals)
        }
    }
    
    final class View: UIView, UIScrollViewDelegate {
        private let topOverscrollLayer = SimpleLayer()
        private let scrollView: ScrollView
        
        private let navigationTitle = ComponentView<Empty>()
        private let icon = ComponentView<Empty>()
        private let subtitle = ComponentView<Empty>()
        private let generalSection = ComponentView<Empty>()
        private let daysSection = ComponentView<Empty>()
        private let timezoneSection = ComponentView<Empty>()
        
        private var ignoreScrolling: Bool = false
        private var isUpdating: Bool = false
        
        private var component: BusinessHoursSetupScreenComponent?
        private(set) weak var state: EmptyComponentState?
        private var environment: EnvironmentType?
        
        private var showHours: Bool = false
        private var daysState = DaysState(timezoneId: "", days: [])
        
        override init(frame: CGRect) {
            self.scrollView = ScrollView()
            self.scrollView.showsVerticalScrollIndicator = true
            self.scrollView.showsHorizontalScrollIndicator = false
            self.scrollView.scrollsToTop = false
            self.scrollView.delaysContentTouches = false
            self.scrollView.canCancelContentTouches = true
            self.scrollView.contentInsetAdjustmentBehavior = .never
            if #available(iOS 13.0, *) {
                self.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
            }
            self.scrollView.alwaysBounceVertical = true
            
            super.init(frame: frame)
            
            self.scrollView.delegate = self
            self.addSubview(self.scrollView)
            
            self.scrollView.layer.addSublayer(self.topOverscrollLayer)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        deinit {
        }

        func scrollToTop() {
            self.scrollView.setContentOffset(CGPoint(), animated: true)
        }
        
        func attemptNavigation(complete: @escaping () -> Void) -> Bool {
            guard let component = self.component else {
                return true
            }
            
            if self.showHours {
                do {
                    let businessHours = try self.daysState.asBusinessHours()
                    let _ = component.context.engine.accountData.updateAccountBusinessHours(businessHours: businessHours).startStandalone()
                    return true
                } catch let error {
                    let _ = error
                    //TODO:localize
                    return false
                }
            } else {
                if component.initialValue != nil {
                    let _ = component.context.engine.accountData.updateAccountBusinessHours(businessHours: nil).startStandalone()
                    return true
                } else {
                    return true
                }
            }
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if !self.ignoreScrolling {
                self.updateScrolling(transition: .immediate)
            }
        }
        
        var scrolledUp = true
        private func updateScrolling(transition: Transition) {
            let navigationRevealOffsetY: CGFloat = 0.0
            
            let navigationAlphaDistance: CGFloat = 16.0
            let navigationAlpha: CGFloat = max(0.0, min(1.0, (self.scrollView.contentOffset.y - navigationRevealOffsetY) / navigationAlphaDistance))
            if let controller = self.environment?.controller(), let navigationBar = controller.navigationBar {
                transition.setAlpha(layer: navigationBar.backgroundNode.layer, alpha: navigationAlpha)
                transition.setAlpha(layer: navigationBar.stripeNode.layer, alpha: navigationAlpha)
            }
            
            var scrolledUp = false
            if navigationAlpha < 0.5 {
                scrolledUp = true
            } else if navigationAlpha > 0.5 {
                scrolledUp = false
            }
            
            if self.scrolledUp != scrolledUp {
                self.scrolledUp = scrolledUp
                if !self.isUpdating {
                    self.state?.updated()
                }
            }
            
            if let navigationTitleView = self.navigationTitle.view {
                transition.setAlpha(view: navigationTitleView, alpha: 1.0)
            }
        }
        
        func update(component: BusinessHoursSetupScreenComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: Transition) -> CGSize {
            self.isUpdating = true
            defer {
                self.isUpdating = false
            }
            
            if self.component == nil {
                if let initialValue = component.initialValue {
                    self.showHours = true
                    self.daysState = DaysState(businessHours: initialValue)
                } else {
                    self.showHours = false
                    self.daysState.timezoneId = TimeZone.current.identifier
                    self.daysState.days = (0 ..< 7).map { _ in
                        return Day(ranges: [])
                    }
                }
            }
            
            let environment = environment[EnvironmentType.self].value
            let themeUpdated = self.environment?.theme !== environment.theme
            self.environment = environment
            
            self.component = component
            self.state = state
            
            if themeUpdated {
                self.backgroundColor = environment.theme.list.blocksBackgroundColor
            }
            
            let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
            
            //TODO:localize
            let navigationTitleSize = self.navigationTitle.update(
                transition: transition,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: "Business Hours", font: Font.semibold(17.0), textColor: environment.theme.rootController.navigationBar.primaryTextColor)),
                    horizontalAlignment: .center
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: 100.0)
            )
            let navigationTitleFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - navigationTitleSize.width) / 2.0), y: environment.statusBarHeight + floor((environment.navigationHeight - environment.statusBarHeight - navigationTitleSize.height) / 2.0)), size: navigationTitleSize)
            if let navigationTitleView = self.navigationTitle.view {
                if navigationTitleView.superview == nil {
                    if let controller = self.environment?.controller(), let navigationBar = controller.navigationBar {
                        navigationBar.view.addSubview(navigationTitleView)
                    }
                }
                transition.setFrame(view: navigationTitleView, frame: navigationTitleFrame)
            }
            
            let bottomContentInset: CGFloat = 24.0
            let sideInset: CGFloat = 16.0 + environment.safeInsets.left
            let sectionSpacing: CGFloat = 32.0
            
            let _ = bottomContentInset
            let _ = sectionSpacing
            
            var contentHeight: CGFloat = 0.0
            
            contentHeight += environment.navigationHeight
            
            let iconSize = self.icon.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: "⏰", font: Font.semibold(90.0), textColor: environment.theme.rootController.navigationBar.primaryTextColor)),
                    horizontalAlignment: .center
                )),
                environment: {},
                containerSize: CGSize(width: 100.0, height: 100.0)
            )
            let iconFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - iconSize.width) * 0.5), y: contentHeight + 2.0), size: iconSize)
            if let iconView = self.icon.view {
                if iconView.superview == nil {
                    self.scrollView.addSubview(iconView)
                }
                transition.setPosition(view: iconView, position: iconFrame.center)
                iconView.bounds = CGRect(origin: CGPoint(), size: iconFrame.size)
            }
            
            contentHeight += 129.0
            
            //TODO:localize
            let subtitleString = NSMutableAttributedString(attributedString: parseMarkdownIntoAttributedString("Turn this on to show your opening hours schedule to your customers.", attributes: MarkdownAttributes(
                body: MarkdownAttributeSet(font: Font.regular(15.0), textColor: environment.theme.list.freeTextColor),
                bold: MarkdownAttributeSet(font: Font.semibold(15.0), textColor: environment.theme.list.freeTextColor),
                link: MarkdownAttributeSet(font: Font.regular(15.0), textColor: environment.theme.list.itemAccentColor),
                linkAttribute: { attributes in
                    return ("URL", "")
                }), textAlignment: .center
            ))
            
            //TODO:localize
            let subtitleSize = self.subtitle.update(
                transition: .immediate,
                component: AnyComponent(BalancedTextComponent(
                    text: .plain(subtitleString),
                    horizontalAlignment: .center,
                    maximumNumberOfLines: 0,
                    lineSpacing: 0.25,
                    highlightColor: environment.theme.list.itemAccentColor.withMultipliedAlpha(0.1),
                    highlightAction: { attributes in
                        if let _ = attributes[NSAttributedString.Key(rawValue: "URL")] {
                            return NSAttributedString.Key(rawValue: "URL")
                        } else {
                            return nil
                        }
                    },
                    tapAction: { [weak self] _, _ in
                        guard let self, let component = self.component else {
                            return
                        }
                        let _ = component
                    }
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 1000.0)
            )
            let subtitleFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - subtitleSize.width) * 0.5), y: contentHeight), size: subtitleSize)
            if let subtitleView = self.subtitle.view {
                if subtitleView.superview == nil {
                    self.scrollView.addSubview(subtitleView)
                }
                transition.setPosition(view: subtitleView, position: subtitleFrame.center)
                subtitleView.bounds = CGRect(origin: CGPoint(), size: subtitleFrame.size)
            }
            contentHeight += subtitleSize.height
            contentHeight += 27.0
            
            //TODO:localize
            let generalSectionSize = self.generalSection.update(
                transition: transition,
                component: AnyComponent(ListSectionComponent(
                    theme: environment.theme,
                    header: nil,
                    footer: nil,
                    items: [
                        AnyComponentWithIdentity(id: 0, component: AnyComponent(ListActionItemComponent(
                            theme: environment.theme,
                            title: AnyComponent(VStack([
                                AnyComponentWithIdentity(id: AnyHashable(0), component: AnyComponent(MultilineTextComponent(
                                    text: .plain(NSAttributedString(
                                        string: "Show Business Hours",
                                        font: Font.regular(presentationData.listsFontSize.baseDisplaySize),
                                        textColor: environment.theme.list.itemPrimaryTextColor
                                    )),
                                    maximumNumberOfLines: 1
                                ))),
                            ], alignment: .left, spacing: 2.0)),
                            accessory: .toggle(ListActionItemComponent.Toggle(style: .regular, isOn: self.showHours, action: { [weak self] _ in
                                guard let self else {
                                    return
                                }
                                self.showHours = !self.showHours
                                self.state?.updated(transition: .spring(duration: 0.4))
                            })),
                            action: nil
                        )))
                    ]
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 10000.0)
            )
            let generalSectionFrame = CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: generalSectionSize)
            if let generalSectionView = self.generalSection.view {
                if generalSectionView.superview == nil {
                    self.scrollView.addSubview(generalSectionView)
                }
                transition.setFrame(view: generalSectionView, frame: generalSectionFrame)
            }
            contentHeight += generalSectionSize.height
            contentHeight += sectionSpacing
            
            var daysContentHeight: CGFloat = 0.0
            
            var daysSectionItems: [AnyComponentWithIdentity<Empty>] = []
            for day in self.daysState.days {
                let dayIndex = daysSectionItems.count
                
                let title: String
                //TODO:localize
                switch dayIndex {
                case 0:
                    title = "Monday"
                case 1:
                    title = "Tuesday"
                case 2:
                    title = "Wednesday"
                case 3:
                    title = "Thursday"
                case 4:
                    title = "Friday"
                case 5:
                    title = "Saturday"
                case 6:
                    title = "Sunday"
                default:
                    title = " "
                }
                
                let subtitle: String
                if let ranges = self.daysState.days[dayIndex].ranges {
                    if ranges.isEmpty {
                        subtitle = "Open 24 Hours"
                    } else {
                        var resultText: String = ""
                        for range in ranges {
                            if !resultText.isEmpty {
                                resultText.append(", ")
                            }
                            let startHours = clipMinutes(range.startMinute) / 60
                            let startMinutes = clipMinutes(range.startMinute) % 60
                            let startText = stringForShortTimestamp(hours: Int32(startHours), minutes: Int32(startMinutes), dateTimeFormat: PresentationDateTimeFormat())
                            let endHours = clipMinutes(range.endMinute) / 60
                            let endMinutes = clipMinutes(range.endMinute) % 60
                            let endText = stringForShortTimestamp(hours: Int32(endHours), minutes: Int32(endMinutes), dateTimeFormat: PresentationDateTimeFormat())
                            resultText.append("\(startText)\u{00a0}- \(endText)")
                        }
                        subtitle = resultText
                    }
                } else {
                    subtitle = "Closed"
                }
                
                daysSectionItems.append(AnyComponentWithIdentity(id: dayIndex, component: AnyComponent(ListActionItemComponent(
                    theme: environment.theme,
                    title: AnyComponent(VStack([
                        AnyComponentWithIdentity(id: AnyHashable(0), component: AnyComponent(MultilineTextComponent(
                            text: .plain(NSAttributedString(
                                string: title,
                                font: Font.regular(presentationData.listsFontSize.baseDisplaySize),
                                textColor: environment.theme.list.itemPrimaryTextColor
                            )),
                            maximumNumberOfLines: 1
                        ))),
                        AnyComponentWithIdentity(id: AnyHashable(1), component: AnyComponent(MultilineTextComponent(
                            text: .plain(NSAttributedString(
                                string: subtitle,
                                font: Font.regular(floor(presentationData.listsFontSize.baseDisplaySize * 15.0 / 17.0)),
                                textColor: environment.theme.list.itemAccentColor
                            )),
                            maximumNumberOfLines: 5
                        )))
                    ], alignment: .left, spacing: 2.0)),
                    accessory: .toggle(ListActionItemComponent.Toggle(style: .regular, isOn: day.ranges != nil, action: { [weak self] _ in
                        guard let self else {
                            return
                        }
                        if dayIndex < self.daysState.days.count {
                            if self.daysState.days[dayIndex].ranges == nil {
                                self.daysState.days[dayIndex].ranges = []
                            } else {
                                self.daysState.days[dayIndex].ranges = nil
                            }
                        }
                        self.state?.updated(transition: .immediate)
                    })),
                    action: { [weak self] _ in
                        guard let self, let component = self.component else {
                            return
                        }
                        self.environment?.controller()?.push(BusinessDaySetupScreen(
                            context: component.context,
                            dayIndex: dayIndex,
                            day: self.daysState.days[dayIndex],
                            updateDay: { [weak self] day in
                                guard let self else {
                                    return
                                }
                                if self.daysState.days[dayIndex] != day {
                                    self.daysState.days[dayIndex] = day
                                    self.state?.updated(transition: .immediate)
                                }
                            }
                        ))
                    }
                ))))
            }
            let daysSectionSize = self.daysSection.update(
                transition: transition,
                component: AnyComponent(ListSectionComponent(
                    theme: environment.theme,
                    header: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(
                            string: "BUSINESS HOURS",
                            font: Font.regular(presentationData.listsFontSize.itemListBaseHeaderFontSize),
                            textColor: environment.theme.list.freeTextColor
                        )),
                        maximumNumberOfLines: 0
                    )),
                    footer: nil,
                    items: daysSectionItems
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 10000.0)
            )
            let daysSectionFrame = CGRect(origin: CGPoint(x: sideInset, y: contentHeight + daysContentHeight), size: daysSectionSize)
            if let daysSectionView = self.daysSection.view {
                if daysSectionView.superview == nil {
                    daysSectionView.layer.allowsGroupOpacity = true
                    self.scrollView.addSubview(daysSectionView)
                }
                transition.setFrame(view: daysSectionView, frame: daysSectionFrame)
                
                let alphaTransition = transition.animation.isImmediate ? transition : .easeInOut(duration: 0.25)
                alphaTransition.setAlpha(view: daysSectionView, alpha: self.showHours ? 1.0 : 0.0)
            }
            daysContentHeight += daysSectionSize.height
            daysContentHeight += sectionSpacing
            
            let timezoneSectionSize = self.timezoneSection.update(
                transition: transition,
                component: AnyComponent(ListSectionComponent(
                    theme: environment.theme,
                    header: nil,
                    footer: nil,
                    items: [
                        AnyComponentWithIdentity(id: 0, component: AnyComponent(ListActionItemComponent(
                            theme: environment.theme,
                            title: AnyComponent(MultilineTextComponent(
                                text: .plain(NSAttributedString(
                                    string: "Time Zone", //TODO:localize
                                    font: Font.regular(presentationData.listsFontSize.baseDisplaySize),
                                    textColor: environment.theme.list.itemPrimaryTextColor
                                )),
                                maximumNumberOfLines: 1
                            )),
                            icon: ListActionItemComponent.Icon(component: AnyComponentWithIdentity(id: 0, component: AnyComponent(MultilineTextComponent(
                                text: .plain(NSAttributedString(
                                    string: TimeZone(identifier: self.daysState.timezoneId)?.localizedName(for: .shortStandard, locale: Locale.current) ?? self.daysState.timezoneId,
                                    font: Font.regular(presentationData.listsFontSize.baseDisplaySize),
                                    textColor: environment.theme.list.itemSecondaryTextColor
                                )),
                                maximumNumberOfLines: 1
                            )))),
                            accessory: .arrow,
                            action: { [weak self] _ in
                                guard let self, let component = self.component else {
                                    return
                                }
                                var completed: ((String) -> Void)?
                                let controller = TimezoneSelectionScreen(context: component.context, completed: { timezoneId in
                                    completed?(timezoneId)
                                })
                                controller.navigationPresentation = .modal
                                self.environment?.controller()?.push(controller)
                                completed = { [weak self, weak controller] timezoneId in
                                    guard let self else {
                                        controller?.dismiss()
                                        return
                                    }
                                    self.daysState.timezoneId = timezoneId
                                    self.state?.updated(transition: .immediate)
                                    controller?.dismiss()
                                }
                            }
                        )))
                    ]
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 10000.0)
            )
            let timezoneSectionFrame = CGRect(origin: CGPoint(x: sideInset, y: contentHeight + daysContentHeight), size: timezoneSectionSize)
            if let timezoneSectionView = self.timezoneSection.view {
                if timezoneSectionView.superview == nil {
                    self.scrollView.addSubview(timezoneSectionView)
                }
                transition.setFrame(view: timezoneSectionView, frame: timezoneSectionFrame)
                let alphaTransition = transition.animation.isImmediate ? transition : .easeInOut(duration: 0.25)
                alphaTransition.setAlpha(view: timezoneSectionView, alpha: self.showHours ? 1.0 : 0.0)
            }
            daysContentHeight += timezoneSectionSize.height
            
            if self.showHours {
                contentHeight += daysContentHeight
            }
            
            contentHeight += bottomContentInset
            contentHeight += environment.safeInsets.bottom
            
            self.ignoreScrolling = true
            let previousBounds = self.scrollView.bounds
            
            let contentSize = CGSize(width: availableSize.width, height: contentHeight)
            if self.scrollView.frame != CGRect(origin: CGPoint(), size: availableSize) {
                self.scrollView.frame = CGRect(origin: CGPoint(), size: availableSize)
            }
            if self.scrollView.contentSize != contentSize {
                self.scrollView.contentSize = contentSize
            }
            let scrollInsets = UIEdgeInsets(top: environment.navigationHeight, left: 0.0, bottom: 0.0, right: 0.0)
            if self.scrollView.scrollIndicatorInsets != scrollInsets {
                self.scrollView.scrollIndicatorInsets = scrollInsets
            }
            self.ignoreScrolling = false
                        
            if !previousBounds.isEmpty, !transition.animation.isImmediate {
                let bounds = self.scrollView.bounds
                if bounds.maxY != previousBounds.maxY {
                    let offsetY = previousBounds.maxY - bounds.maxY
                    transition.animateBoundsOrigin(view: self.scrollView, from: CGPoint(x: 0.0, y: offsetY), to: CGPoint(), additive: true)
                }
            }
            
            self.topOverscrollLayer.frame = CGRect(origin: CGPoint(x: 0.0, y: -3000.0), size: CGSize(width: availableSize.width, height: 3000.0))
            
            self.updateScrolling(transition: transition)
            
            return availableSize
        }
    }
    
    func makeView() -> View {
        return View()
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

public final class BusinessHoursSetupScreen: ViewControllerComponentContainer {
    private let context: AccountContext
    
    public init(context: AccountContext, initialValue: TelegramBusinessHours?, completion: @escaping (TelegramBusinessHours?) -> Void) {
        self.context = context
        
        super.init(context: context, component: BusinessHoursSetupScreenComponent(
            context: context,
            initialValue: initialValue,
            completion: completion
        ), navigationBarAppearance: .default, theme: .default, updatedPresentationData: nil)
        
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.title = ""
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        
        self.scrollToTop = { [weak self] in
            guard let self, let componentView = self.node.hostView.componentView as? BusinessHoursSetupScreenComponent.View else {
                return
            }
            componentView.scrollToTop()
        }
        
        self.attemptNavigation = { [weak self] complete in
            guard let self, let componentView = self.node.hostView.componentView as? BusinessHoursSetupScreenComponent.View else {
                return true
            }
            
            return componentView.attemptNavigation(complete: complete)
        }
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
    }
    
    @objc private func cancelPressed() {
        self.dismiss()
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
    }
}
