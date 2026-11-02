import SwiftUI
import Translation

struct PlayerScreen: View {
    let video: Video

    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    @AppStorage("subtitleMode") private var modeRaw = SubtitleMode.bilingual.rawValue
    @AppStorage("subtitleScale") private var subtitleScale = 1.0

    @State private var player = YouTubePlayerController()
    @State private var subs: SubtitleModel
    @State private var startAt: Double
    @State private var lastSaved: Double = 0
    @State private var showPlaylistPicker = false
    /// 先确定从哪里开始播放，再创建播放器
    @State private var positionResolved = false

    init(video: Video, startAt: Double = 0) {
        self.video = video
        _subs = State(initialValue: SubtitleModel(videoID: video.id))
        _startAt = State(initialValue: startAt)
    }

    private var mode: SubtitleMode { SubtitleMode(rawValue: modeRaw) ?? .bilingual }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            if landscape {
                playerWithSubtitles
                    .frame(width: geo.size.width, height: geo.size.height)
                    .background(.black)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 0) {
                    playerWithSubtitles
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black)
                    ScrollView { details }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { subtitleMenu }
        .task {
            if startAt == 0 { startAt = library.lastPosition(video.id) }
            positionResolved = true
            await subs.load()
        }
        .translationTask(subs.translationConfig) { session in
            await subs.translate(using: session, from: player.currentTime)
        }
        .onChange(of: player.currentTime) { _, t in
            if abs(t - lastSaved) > 10 { lastSaved = t; library.recordWatch(video.id, position: t) }
        }
        .onDisappear { library.recordWatch(video.id, position: player.currentTime) }
        .sheet(isPresented: $showPlaylistPicker) { PlaylistPicker(videoID: video.id) }
    }

    // MARK: 播放器 + 字幕层

    private var playerWithSubtitles: some View {
        ZStack(alignment: .bottom) {
            if positionResolved {
                YouTubePlayerView(videoID: video.id, startAt: startAt, controller: player)
            } else {
                Color.black
            }
            if mode != .off, let cue = subs.cue(at: player.currentTime) {
                SubtitleOverlay(cue: cue, mode: mode, scale: subtitleScale)
                    .padding(.bottom, 36)
                    .padding(.horizontal, 12)
                    .allowsHitTesting(false)   // 不挡住 YouTube 的播放控制
                    .animation(.none, value: cue.id)
            }
        }
    }

    // MARK: 视频信息

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(video.title).font(.headline)
            HStack(spacing: 6) {
                Text(video.channel)
                if let y = video.year { Text("· \(y)") }
                if let m = video.mentions { Text("· HN 推荐 \(m) 次") }
            }
            .font(.subheadline).foregroundStyle(.secondary)

            subtitleStatus

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    pill(library.isLiked(video.id) ? "已喜欢" : "喜欢",
                         library.isLiked(video.id) ? "hand.thumbsup.fill" : "hand.thumbsup") {
                        library.toggleLike(video.id)
                    }
                    pill(library.isInWatchLater(video.id) ? "已加入" : "稍后观看",
                         library.isInWatchLater(video.id) ? "clock.fill" : "clock") {
                        library.toggleWatchLater(video.id)
                    }
                    pill("加到播放列表", "text.badge.plus") { showPlaylistPicker = true }
                    if let url = video.youtubeURL {
                        ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                    if let hn = video.hnURL.flatMap(URL.init(string:)) {
                        Link(destination: hn) { Label("HN 讨论", systemImage: "bubble.left.and.bubble.right") }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                }
            }

            if !related.isEmpty {
                Text("相关视频").font(.headline).padding(.top, 8)
                ForEach(related) { v in
                    NavigationLink(value: v) { VideoRow(video: v) }.buttonStyle(.plain)
                }
            }
        }
        .padding()
    }

    @ViewBuilder private var subtitleStatus: some View {
        switch subs.status {
        case .loading:
            Label("正在加载字幕…", systemImage: "captions.bubble").font(.caption).foregroundStyle(.secondary)
        case .translating(let done, let total):
            ProgressView(value: Double(done), total: Double(max(total, 1))) {
                Text("正在本机翻译中文字幕 \(done)/\(total)").font(.caption).foregroundStyle(.secondary)
            }
        case .unavailable:
            Label("这个视频暂时没有字幕", systemImage: "captions.bubble").font(.caption).foregroundStyle(.secondary)
        case .translationFailed(let msg):
            Label("中文翻译失败：\(msg)", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private var related: [Video] {
        guard let cat = video.categories.first else { return [] }
        return catalog.videos(in: cat).filter { $0.id != video.id }.prefix(15).map { $0 }
    }

    private var subtitleMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("字幕", selection: $modeRaw) {
                    ForEach(SubtitleMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } label: {
                Image(systemName: mode == .off ? "captions.bubble" : "captions.bubble.fill")
            }
        }
    }

    private func pill(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon) }
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
    }
}

struct SubtitleOverlay: View {
    let cue: SubtitleCue
    let mode: SubtitleMode
    var scale: Double = 1

    var body: some View {
        VStack(spacing: 2) {
            if mode == .bilingual || mode == .chinese, let zh = cue.zh {
                Text(zh).font(.system(size: 17 * scale, weight: .semibold))
            }
            if mode == .bilingual || mode == .english || (mode == .chinese && cue.zh == nil) {
                Text(cue.en).font(.system(size: (mode == .bilingual ? 14 : 16) * scale))
                    .foregroundStyle(.white.opacity(mode == .bilingual ? 0.85 : 1))
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .shadow(color: .black, radius: 2)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
    }
}
