import AccountContext
import Display
import Foundation
import NGCore

class UrlOpenerImpl {
    
    //  MARK: - Dependencies
    
    private let accountContext: AccountContext
    
    //  MARK: - Lifecycle
    
    init(accountContext: AccountContext) {
        self.accountContext = accountContext
    }
}

extension UrlOpenerImpl: UrlOpener {
    func open(_ url: URL) {
        let sharedContext = accountContext.sharedContext
        let navigationController = sharedContext.mainWindow?.viewController as? NavigationController
        let presentationData = sharedContext.currentPresentationData.with { $0 }
        
        let telegramHosts = ["t.me", "telegram.me"]
        let isTelegramHost = telegramHosts.contains(url._wrapperHost() ?? "")
        
        let forceExternal = !isTelegramHost
        
        sharedContext.openExternalUrl(
            context: accountContext,
            urlContext: .generic,
            url: url.absoluteString,
            forceExternal: forceExternal,
            presentationData: presentationData,
            navigationController: navigationController,
            dismissInput: {}
        )
    }
}
