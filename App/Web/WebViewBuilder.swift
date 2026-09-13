import KioskCore
import WebKit

/// Turns a resolved configuration into a `WKWebView`.
///
/// Kept separate from the controller so that "what the configuration asks for"
/// and "what happens while the page runs" do not share one 400-line class.
@MainActor
enum WebViewBuilder {
    static func make(configuration kiosk: KioskConfiguration) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        configuration.websiteDataStore =
            switch kiosk.sessionPersistence {
            case .persistent: WKWebsiteDataStore.default()
            case .ephemeral: WKWebsiteDataStore.nonPersistent()
            }

        // Popups never open a window of their own. Either the navigation is
        // allowed, in which case it happens in this view, or it is refused.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = kiosk.allowPopups

        let controller = configuration.userContentController
        for sheet in kiosk.injectedStyleSheets {
            controller.addUserScript(styleScript(for: sheet))
        }
        for script in kiosk.injectedUserScripts {
            controller.addUserScript(
                WKUserScript(
                    source: script.source,
                    injectionTime: script.injectionTime == .documentStart
                        ? .atDocumentStart : .atDocumentEnd,
                    forMainFrameOnly: script.mainFrameOnly
                )
            )
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = kiosk.userAgent
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    /// A stylesheet is injected as the script that installs it. WebKit has no
    /// user-stylesheet API on this platform, and a `<style>` element added at
    /// document start applies before the first paint, which is what avoids the
    /// flash of the page's own layout.
    private static func styleScript(for css: String) -> WKUserScript {
        let encoded = css.data(using: .utf8)?.base64EncodedString() ?? ""
        let source = """
            (function () {
              const style = document.createElement('style');
              style.textContent = atob('\(encoded)');
              (document.head || document.documentElement).appendChild(style);
            })();
            """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }
}
