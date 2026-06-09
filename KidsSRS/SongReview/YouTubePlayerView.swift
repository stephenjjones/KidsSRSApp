import SwiftUI
import WebKit

/// Embeds a YouTube video in a `WKWebView` (Spec §14.1) by loading the player
/// page from the in-app loopback server (`LocalPlayerServer`).
///
/// Why the local server: YouTube refuses to play an embed when the host page has
/// no real web origin, which is the case for `WKWebView.loadHTMLString` on every
/// Apple platform (error 152 / "video unavailable"). Serving the same page over
/// `http://localhost` (a real origin) makes it play — verified on the simulator.
///
/// Auto-advance + error reporting use the IFrame API's `onStateChange` /
/// `onError`, bridged to SwiftUI via a `WKScriptMessageHandler`. Changing
/// `videoID` swaps the song in place via `loadVideoById` (no full reload). The
/// player stays on-screen and visible per YouTube's ToS.
struct YouTubePlayerView {
    let videoID: String
    /// Called on the main thread when the current video reaches its end.
    var onEnded: () -> Void = {}
    /// Called on the main thread with a YouTube error code (2/5/100/101/150).
    var onError: (Int) -> Void = { _ in }

    /// Bridges the page's JS messages to SwiftUI and remembers the loaded id.
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onEnded: () -> Void = {}
        var onError: (Int) -> Void = { _ in }
        var loadedID: String?

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            if body == "ended" {
                onEnded()
            } else if body.hasPrefix("error:"), let code = Int(body.dropFirst("error:".count)) {
                onError(code)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.onEnded = onEnded
        coordinator.onError = onError
        return coordinator
    }

    fileprivate func makeWebView(coordinator: Coordinator) -> WKWebView {
        LocalPlayerServer.shared.startIfNeeded()
        let configuration = WKWebViewConfiguration()
        // Allow programmatic autoplay so the playlist plays through.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        configuration.userContentController.add(coordinator, name: "songEvent")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        #if os(iOS)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        #endif
        return webView
    }

    /// On first load, navigate to the local player page for this song; afterwards
    /// swap the song in place via `loadVideoById` (no reload), which autoplays.
    fileprivate func sync(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.onEnded = onEnded
        coordinator.onError = onError
        guard coordinator.loadedID != videoID else { return }
        let previous = coordinator.loadedID
        coordinator.loadedID = videoID

        // Video ids are [A-Za-z0-9_-] — URL-safe — so interpolation is fine.
        if previous == nil {
            let url = URL(string: "http://localhost:\(LocalPlayerServer.shared.port)/?v=\(videoID)")!
            webView.load(URLRequest(url: url))
        } else {
            let safeID = videoID.replacingOccurrences(of: "'", with: "")
            webView.evaluateJavaScript("loadVideo('\(safeID)')")
        }
    }

    fileprivate static func removeHandler(from webView: WKWebView) {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "songEvent")
    }
}

#if os(iOS)
extension YouTubePlayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateUIView(_ webView: WKWebView, context: Context) {
        sync(webView, coordinator: context.coordinator)
    }
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        removeHandler(from: webView)
    }
}
#elseif os(macOS)
extension YouTubePlayerView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateNSView(_ webView: WKWebView, context: Context) {
        sync(webView, coordinator: context.coordinator)
    }
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        removeHandler(from: webView)
    }
}
#endif
