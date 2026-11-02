import SwiftUI

/// 首页大卡片：缩略图 + 标题 + 频道
struct VideoCard: View {
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumbnail(video: video)
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .videoContextMenu(video)
    }

    private var meta: String {
        [video.channel, video.year, video.mentions.map { "HN \($0) 次推荐" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// 列表行：左边小缩略图
struct VideoRow: View {
    let video: Video
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Thumbnail(video: video).frame(width: 150)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.subheadline.weight(.medium)).lineLimit(3)
                Text(subtitle ?? video.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .videoContextMenu(video)
    }
}

struct Thumbnail: View {
    let video: Video
    var body: some View {
        AsyncImage(url: video.thumbnailURL) { phase in
            if let img = phase.image { img.resizable().scaledToFill() }
            else { Rectangle().fill(.quaternary) }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if !video.durationText.isEmpty {
                Text(video.durationText)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.white)
                    .padding(5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// 长按视频弹出的菜单
private struct VideoContextMenu: ViewModifier {
    let video: Video
    @Environment(LibraryStore.self) private var library

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { library.toggleWatchLater(video.id) } label: {
                Label(library.isInWatchLater(video.id) ? "移出稍后观看" : "稍后观看", systemImage: "clock")
            }
            Button { library.toggleLike(video.id) } label: {
                Label(library.isLiked(video.id) ? "取消喜欢" : "喜欢", systemImage: "hand.thumbsup")
            }
            if !library.playlists.isEmpty {
                Menu("加到播放列表") {
                    ForEach(library.playlists) { p in
                        Button(p.name) { library.add(video.id, to: p.id) }
                    }
                }
            }
            if let url = video.youtubeURL { ShareLink(item: url) }
        }
    }
}

extension View {
    func videoContextMenu(_ video: Video) -> some View { modifier(VideoContextMenu(video: video)) }
}

/// 自适应网格：手机一列、iPad 多列
struct VideoGrid: View {
    let videos: [Video]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 20) {
            ForEach(videos) { v in
                NavigationLink(value: v) { VideoCard(video: v) }.buttonStyle(.plain)
            }
        }
        .padding()
    }
}

struct EmptyHint: View {
    let title: String
    let systemImage: String
    var message: String = ""
    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}
