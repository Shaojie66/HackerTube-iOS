import SwiftUI
import WebKit

/// 控制内嵌 YouTube 播放器，并把播放进度回传给 SwiftUI。
@Observable
@MainActor
final class YouTubePlayerController {
    enum State: Int { case unstarted = -1, ended = 0, playing = 1, paused = 2, buffering = 3, cued = 5 }

    var currentTime: Double = 0
    var duration: Double = 0
    var state: State = .unstarted
    var isReady = false
    var errorCode: Int?

    fileprivate weak var webView: WKWebView?

    func play() { run("player.playVideo()") }
    func pause() { run("player.pauseVideo()") }
    func seek(to t: Double) { run("player.seekTo(\(t), true)") }
    func setRate(_ r: Double) { run("player.setPlaybackRate(\(r))") }

    private func run(_ js: String) {
        webView?.evaluateJavaScript("try{\(js)}catch(e){}")
    }

    fileprivate func handle(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "ready":
            isReady = true
            duration = body["d"] as? Double ?? 0
        case "time":
            currentTime = body["t"] as? Double ?? currentTime
            if let d = body["d"] as? Double, d > 0 { duration = d }
        case "state":
            state = State(rawValue: body["s"] as? Int ?? -1) ?? .unstarted
        case "error":
            errorCode = body["code"] as? Int
        default: break
        }
    }
}

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    var startAt: Double = 0
    let controller: YouTubePlayerController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "yt")

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        controller.webView = web
        web.loadHTMLString(Self.html(videoID: videoID, start: Int(startAt)),
                           baseURL: URL(string: AppConfig.embedOrigin))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "yt")
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let controller: YouTubePlayerController
        init(controller: YouTubePlayerController) { self.controller = controller }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            Task { @MainActor in controller.handle(body) }
        }
    }

    /// fs=0 关掉 YouTube 自己的全屏，这样横屏时我们的双语字幕层还能盖在视频上面。
    static func html(videoID: String, start: Int) -> String {
        """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player, timer;
        function post(m){window.webkit.messageHandlers.yt.postMessage(m)}
        function onYouTubeIframeAPIReady(){
          player = new YT.Player('p',{
            videoId:'\(videoID)',
            playerVars:{playsinline:1,fs:0,rel:0,modestbranding:1,cc_load_policy:0,iv_load_policy:3,start:\(start),autoplay:1,origin:'\(AppConfig.embedOrigin)'},
            events:{
              onReady:function(e){post({type:'ready',d:player.getDuration()});
                timer=setInterval(function(){post({type:'time',t:player.getCurrentTime(),d:player.getDuration()})},200);},
              onStateChange:function(e){post({type:'state',s:e.data})},
              onError:function(e){post({type:'error',code:e.data})}
            }});
        }
        </script></body></html>
        """
    }
}
