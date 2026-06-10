import Foundation
import Network

/// A minimal loopback HTTP server that serves the YouTube player page from a
/// real `http://localhost` origin (Spec §14.1).
///
/// Why this exists: YouTube refuses to play an embedded video when the host page
/// has no valid web origin — which is exactly the case for
/// `WKWebView.loadHTMLString` on **every** Apple platform (it loads with a null
/// origin, so the embed fails with "video unavailable" / error 152). Serving the
/// identical page over `http://localhost` (a real origin YouTube accepts for
/// embedding) makes it play. Verified on the iOS simulator.
///
/// Shipping note (decision: macOS → **Mac App Store**, so App Sandbox is on):
/// the sandboxed macOS build grants `com.apple.security.network.server` (this
/// loopback listener) + `network.client` (the embed's outbound traffic) in
/// `KidsSRS-macOS.entitlements`. **Verify on a real sandboxed Mac build that the
/// player still loads** (loopback under sandbox). If App Review rejects an
/// in-app local server, the fallback is to serve the player page from a hosted
/// URL — `sync(_:)` only needs the page's origin to change.
final class LocalPlayerServer {
    static let shared = LocalPlayerServer()

    /// Fixed loopback port the player page is served on.
    let port: UInt16 = 24817

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "LocalPlayerServer")

    private init() {}

    /// Start serving (idempotent). Safe to call at app launch.
    func startIfNeeded() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            // Bind to loopback only — never expose the port on the network.
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                         port: NWEndpoint.Port(rawValue: port)!)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            assertionFailure("LocalPlayerServer failed to start: \(error)")
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Read and ignore the request line/headers, then always return the page.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
            let body = Data(Self.playerHTML.utf8)
            var head = "HTTP/1.1 200 OK\r\n"
            head += "Content-Type: text/html; charset=utf-8\r\n"
            head += "Content-Length: \(body.count)\r\n"
            head += "Cache-Control: no-store\r\n"
            head += "Connection: close\r\n\r\n"
            var response = Data(head.utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    /// The player page (Spec §14.3): reads `?v=<id>`, drives the IFrame API, and
    /// bridges `ENDED` / error events to native via `songEvent`. Because it is
    /// served from a real origin, the embed plays and `enablejsapi` events work.
    static let playerHTML = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
    <style>
      html, body { margin: 0; padding: 0; background: #000; height: 100%; overflow: hidden; }
      #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
    </style>
    </head>
    <body>
      <div id="player"></div>
      <script>
        function param(name) {
          var m = new RegExp('[?&]' + name + '=([^&]*)').exec(location.search);
          return m ? decodeURIComponent(m[1]) : '';
        }
        function bridge(msg) {
          try { window.webkit.messageHandlers.songEvent.postMessage(msg); } catch (e) {}
        }
        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        document.head.appendChild(tag);
        var player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            width: '100%', height: '100%',
            videoId: param('v'),
            playerVars: { autoplay: 1, playsinline: 1, rel: 0, modestbranding: 1 },
            events: {
              'onStateChange': function(e) { if (e.data === 0) bridge('ended'); },
              'onError': function(e) { bridge('error:' + e.data); }
            }
          });
        }
        function loadVideo(id) {
          if (player && player.loadVideoById) { player.loadVideoById(id); }
        }
      </script>
    </body>
    </html>
    """
}
