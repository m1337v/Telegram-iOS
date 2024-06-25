import Foundation
import UIKit
import Display
import AppBundle
import HierarchyTrackingLayer
import ComponentFlow
import TextLoadingEffect

final class ItemLoadingComponent: Component {
    private let color: UIColor
    
    public init(color: UIColor) {
        self.color = color
    }

    public static func ==(lhs: ItemLoadingComponent, rhs: ItemLoadingComponent) -> Bool {
        if !lhs.color.isEqual(rhs.color) {
            return false
        }
        return true
    }
    
    public final class View: UIView {
        private let loadingView = TextLoadingEffectView()
        private let borderView = UIImageView()
        
        private let borderMaskView = UIView()
        private let borderMaskGradientView = UIImageView()
        private let borderMaskFillView = UIImageView()
        
        private var component: ItemLoadingComponent?
        
        override public init(frame: CGRect) {
            super.init(frame: frame)
            
            self.addSubview(self.loadingView)
            self.addSubview(self.borderView)
            
            self.borderView.image = generateFilledRoundedRectImage(size: CGSize(width: 24.0, height: 24.0), cornerRadius: 10.0, color: nil, strokeColor: .white, strokeWidth: 1.0 + UIScreenPixel, backgroundColor: nil)?.stretchableImage(withLeftCapWidth: 10, topCapHeight: 10).withRenderingMode(.alwaysTemplate)
            
            self.borderMaskView.backgroundColor = .clear
            self.borderMaskFillView.backgroundColor = .white
            
            self.borderMaskView.addSubview(self.borderMaskFillView)
            self.borderMaskFillView.addSubview(self.borderMaskGradientView)
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func playAppearanceAnimation() {
            self.borderView.mask = self.borderMaskView
            
            let gradientWidth = self.borderView.bounds.width * 0.4
            self.borderMaskGradientView.image = generateGradientImage(size: CGSize(width: gradientWidth, height: 24.0), colors: [UIColor.white, UIColor.white.withAlphaComponent(0.0)], locations: [0.0, 1.0], direction: .horizontal)
            
            self.borderMaskGradientView.frame = CGRect(origin: CGPoint(x: self.borderView.bounds.width, y: 0.0), size: CGSize(width: gradientWidth, height: self.borderView.bounds.height))
            self.borderMaskFillView.frame = CGRect(origin: .zero, size: self.borderView.bounds.size)
            
            self.borderMaskFillView.layer.animatePosition(from: CGPoint(x: -self.borderView.bounds.width, y: 0.0), to: .zero, duration: 1.0, removeOnCompletion: false, additive: true, completion: { _ in
                self.borderView.mask = nil
            })
        }
        
        func update(component: ItemLoadingComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: Transition) -> CGSize {
            let isFirstTime = self.component == nil
            
            self.component = component
            
            self.borderView.tintColor = component.color
            
            self.loadingView.update(color: component.color, rect: CGRect(origin: .zero, size: availableSize))
            transition.setFrame(view: self.borderView, frame: CGRect(origin: .zero, size: availableSize))
            self.borderMaskView.frame = self.borderView.bounds
            
            if isFirstTime {
                self.playAppearanceAnimation()
            }
            
            return availableSize
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
