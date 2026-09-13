import AppKit
import KioskCore
import WebKit

/// One screen's worth of kiosk: the web view, the optional navigation bar and
/// the notice overlay, plus the policy that decides what the page may do.
@MainActor
final class KioskViewController: NSViewController {
    private let kiosk: KioskConfiguration
    private let policy: URLPolicy
    private let homeURL: URL?

    private let webView: WKWebView
    private let notice = NoticeView()
    private var navigationBar: NavigationBar?

    private var retryDelay: TimeInterval = 1
    private var retryTimer: Timer?
    private var reloadTimer: Timer?

    init(configuration: KioskConfiguration, url: URL?) {
        self.kiosk = configuration
        self.policy = configuration.urlPolicy
        self.homeURL = url
        self.webView = WebViewBuilder.make(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Kioskalator builds its views in code")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        view.wantsLayer = true

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        notice.translatesAutoresizingMaskIntoConstraints = false
        notice.isHidden = true
        view.addSubview(notice)

        var top = view.topAnchor
        if kiosk.showNavigationBar {
            let bar = NavigationBar(buttons: kiosk.navigationBarButtons, delegate: self)
            bar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.topAnchor.constraint(equalTo: view.topAnchor),
                bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                bar.heightAnchor.constraint(equalToConstant: NavigationBar.height),
            ])
            top = bar.bottomAnchor
            navigationBar = bar
        }

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: top),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            notice.topAnchor.constraint(equalTo: top),
            notice.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            notice.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            notice.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        loadHome()
        startScheduledReload()
    }

    // MARK: Navigation the application performs itself

    func loadHome() {
        guard let homeURL else {
            notice.show(
                title: "Kioskalator is not configured",
                detail: "No home URL was found in any configuration layer.",
                hint: "/Library/Application Support/Kioskalator/configuration.json"
                    + "\n\(ConfigurationSources.preferenceDomain)"
            )
            return
        }
        notice.isHidden = true
        webView.load(URLRequest(url: homeURL))
    }

    func returnToHomeAfterIdle() {
        if kiosk.idleAction == .returnHomeAndClearData {
            clearWebsiteData { [weak self] in self?.loadHome() }
        } else {
            loadHome()
        }
    }

    private func clearWebsiteData(completion: @escaping () -> Void) {
        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: .distantPast) {
            MainActor.assumeIsolated(completion)
        }
    }

    private func startScheduledReload() {
        guard let interval = kiosk.scheduledReloadInterval else { return }
        reloadTimer?.invalidate()
        reloadTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.loadHome() }
        }
    }

    /// Retries the home URL with a growing delay.
    ///
    /// A kiosk usually starts before the network is up, so the first load
    /// failing is the normal case rather than an error worth showing forever.
    private func scheduleRetry() {
        guard kiosk.startupRetryEnabled else { return }
        retryTimer?.invalidate()
        let delay = min(retryDelay, kiosk.startupRetryMaximumDelay)
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.loadHome() }
        }
        retryDelay = min(retryDelay * 2, kiosk.startupRetryMaximumDelay)
    }

    private func show(refusal url: URL) {
        Log.navigation.notice("refused navigation to \(url.absoluteString, privacy: .public)")
        notice.show(
            title: "This page is not available here",
            detail: "The address is outside what this kiosk is allowed to show.",
            hint: url.absoluteString
        )
    }

    isolated deinit {
        retryTimer?.invalidate()
        reloadTimer?.invalidate()
    }
}

// MARK: - Navigation policy

extension KioskViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // Only main-frame navigations are policed. A target frame of nil is a
        // new window, which is a main-frame navigation by any other name and is
        // handled here rather than slipping through as a subresource.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        guard isMainFrame, let url = navigationAction.request.url else { return .allow }

        switch policy.decision(for: url, externalScheme: kiosk.externalSchemePolicy) {
        case .allow:
            notice.isHidden = true
            return .allow
        case .blockNotAllowed:
            show(refusal: url)
            return .cancel
        case .blockExternalScheme:
            Log.navigation.notice("refused external scheme \(url.scheme ?? "?", privacy: .public)")
            return .cancel
        case .openExternally:
            NSWorkspace.shared.open(url)
            return .cancel
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        // A response that cannot be displayed becomes a download unless it is
        // refused here. A download on a kiosk is a file on a machine nobody
        // administers.
        if !navigationResponse.canShowMIMEType && !kiosk.allowDownloads {
            Log.navigation.notice("refused a download")
            return .cancel
        }
        return .allow
    }

    // swiftlint:disable:next implicitly_unwrapped_optional - the SDK declares it
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        retryDelay = 1
        retryTimer?.invalidate()
        navigationBar?.update(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
    }

    func webView(
        _ webView: WKWebView,
        // swiftlint:disable:next implicitly_unwrapped_optional - the SDK declares it
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        handle(error)
    }

    func webView(
        _ webView: WKWebView,
        // swiftlint:disable:next implicitly_unwrapped_optional - the SDK declares it
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        handle(error)
    }

    private func handle(_ error: any Error) {
        // A cancelled navigation is what the policy above does on every refusal.
        // Reporting it as a failure would overwrite the refusal notice with a
        // network error and send the operator looking in the wrong place.
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else {
            return
        }
        Log.navigation.error("navigation failed: \(nsError.localizedDescription, privacy: .public)")
        notice.show(
            title: "The page could not be loaded",
            detail: nsError.localizedDescription,
            hint: homeURL?.absoluteString ?? ""
        )
        scheduleRetry()
    }

    /// The content process dying is otherwise a silent blank page that looks
    /// exactly like a dead machine.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.kiosk.error("the web content process terminated")
        guard kiosk.reloadsOnContentProcessTermination else {
            notice.show(
                title: "The page stopped running",
                detail: "Automatic reloading is switched off in the configuration.",
                hint: ""
            )
            return
        }
        loadHome()
    }
}

// MARK: - Page-initiated behaviour

extension KioskViewController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Never a second window. Either the target is allowed, in which case it
        // is loaded here, or it is refused. Returning a new web view would put a
        // window on the kiosk that has no chrome and cannot be closed.
        guard let url = navigationAction.request.url else { return nil }
        switch policy.decision(for: url, externalScheme: kiosk.externalSchemePolicy) {
        case .allow where kiosk.allowPopups:
            webView.load(URLRequest(url: url))
        case .openExternally:
            NSWorkspace.shared.open(url)
        case .allow, .blockNotAllowed, .blockExternalScheme:
            show(refusal: url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo
    ) async -> [URL]? {
        // An open panel is a file browser, and a file browser on a kiosk is an
        // escape route. It opens only when uploads are switched on.
        guard kiosk.allowFileUploads else {
            Log.navigation.notice("refused a file upload panel")
            return nil
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return await panel.begin() == .OK ? panel.urls : nil
    }
}

// MARK: - Navigation bar actions

extension KioskViewController: NavigationBarDelegate {
    func navigationBarDidTap(_ button: NavigationBarButton) {
        switch button {
        case .back: webView.goBack()
        case .forward: webView.goForward()
        case .reload: webView.reload()
        case .home: loadHome()
        }
    }
}
