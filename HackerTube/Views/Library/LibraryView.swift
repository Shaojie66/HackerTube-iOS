import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var newPlaylistName = ""
    @State private var showNewPlaylist = false

    var body: some View {
        List {
            Section {
                NavigationLink { VideoListView(title: "喜欢", ids: library.likedIDs, kind: .liked) } label: {
                    LabeledContent { Text("\(library.likedIDs.count)") } label: { Label("喜欢", systemImage: "hand.thumbsup") }
                }
                NavigationLink { HistoryView() } label: {
                    LabeledContent { Text("\(library.history.count)") } label: { Label("历史记录", systemImage: "clock.arrow.circlepath") }
                }
                NavigationLink { VideoListView(title: "稍后观看", ids: library.watchLaterIDs, kind: .later) } label: {
                    LabeledContent { Text("\(library.watchLaterIDs.count)") } label: { Label("稍后观看", systemImage: "clock") }
                }
            }
            Section("播放列表") {
                ForEach(library.playlists) { p in
                    NavigationLink(value: p.id) {
                        LabeledContent(p.name, value: "\(p.videoIDs.count)")
                    }
                }
                .onDelete { idx in idx.map { library.playlists[$0].id }.forEach(library.deletePlaylist) }
                Button { showNewPlaylist = true } label: { Label("新建播放列表", systemImage: "plus") }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("设置", systemImage: "gearshape") }
            }
        }
        .navigationTitle("媒体库")
        .alert("新建播放列表", isPresented: $showNewPlaylist) {
            TextField("名称", text: $newPlaylistName)
            Button("创建") {
                let n = newPlaylistName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { _ = library.createPlaylist(n) }
                newPlaylistName = ""
            }
            Button("取消", role: .cancel) { newPlaylistName = "" }
        }
    }
}

struct VideoListView: View {
    enum Kind { case liked, later }
    let title: String
    let ids: [String]
    let kind: Kind
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let videos = ids.compactMap { catalog.byID[$0] }
        List {
            ForEach(videos) { v in
                NavigationLink(value: v) { VideoRow(video: v) }
            }
            .onDelete { idx in
                for i in idx {
                    let id = videos[i].id
                    if kind == .liked { library.toggleLike(id) } else { library.toggleWatchLater(id) }
                }
            }
        }
        .listStyle(.plain)
        .overlay { if videos.isEmpty { EmptyHint(title: "这里还是空的", systemImage: "tray") } }
        .navigationTitle(title)
    }
}

struct HistoryView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library

    var body: some View {
        List {
            ForEach(library.history, id: \.videoID) { h in
                if let v = catalog.byID[h.videoID] {
                    NavigationLink(value: v) {
                        VideoRow(video: v, subtitle: h.watchedAt.formatted(.relative(presentation: .named)))
                    }
                }
            }
            .onDelete { idx in idx.map { library.history[$0].videoID }.forEach(library.removeFromHistory) }
        }
        .listStyle(.plain)
        .overlay { if library.history.isEmpty { EmptyHint(title: "还没有观看记录", systemImage: "clock") } }
        .toolbar {
            if !library.history.isEmpty {
                Button("清空", role: .destructive) { library.clearHistory() }
            }
        }
        .navigationTitle("历史记录")
    }
}

struct PlaylistDetailView: View {
    let playlistID: UUID
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let p = library.playlists.first(where: { $0.id == playlistID }) {
            let videos = p.videoIDs.compactMap { catalog.byID[$0] }
            List {
                ForEach(videos) { v in NavigationLink(value: v) { VideoRow(video: v) } }
                    .onDelete { idx in idx.map { videos[$0].id }.forEach { library.remove($0, from: p.id) } }
            }
            .listStyle(.plain)
            .overlay { if videos.isEmpty { EmptyHint(title: "播放列表是空的", systemImage: "music.note.list", message: "长按任意视频即可加入") } }
            .navigationTitle(p.name)
        } else {
            EmptyHint(title: "播放列表已删除", systemImage: "trash")
        }
    }
}

struct PlaylistPicker: View {
    let videoID: String
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("新播放列表名称", text: $name)
                        Button("创建并加入") {
                            let p = library.createPlaylist(name)
                            library.add(videoID, to: p.id)
                            dismiss()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach(library.playlists) { p in
                        Button {
                            library.add(videoID, to: p.id); dismiss()
                        } label: {
                            HStack {
                                Text(p.name)
                                Spacer()
                                if p.videoIDs.contains(videoID) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("加到播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct SettingsView: View {
    @AppStorage("subtitleMode") private var modeRaw = SubtitleMode.bilingual.rawValue
    @AppStorage("subtitleScale") private var subtitleScale = 1.0
    @State private var cleared = false

    var body: some View {
        Form {
            Section {
                Picker("默认字幕", selection: $modeRaw) {
                    ForEach(SubtitleMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                VStack(alignment: .leading) {
                    Text("字幕大小")
                    Slider(value: $subtitleScale, in: 0.8...1.6, step: 0.1)
                }
                SubtitleOverlay(
                    cue: SubtitleCue(id: 0, start: 0, end: 1,
                                     en: "Let's build the transformer from scratch.",
                                     zh: "让我们从零开始构建 Transformer。"),
                    mode: SubtitleMode(rawValue: modeRaw) ?? .bilingual, scale: subtitleScale)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.gray.opacity(0.4))
            } header: { Text("字幕") } footer: {
                Text("中文字幕由 iOS 自带的翻译功能在本机生成，免费、离线可用。第一次使用时系统会提示下载中英翻译语言包。")
            }
            Section {
                Button(cleared ? "已清除" : "清除字幕缓存") {
                    Task { await SubtitleService.shared.clearCache(); cleared = true }
                }
                .disabled(cleared)
            }
            Section("关于") {
                Link("HackerTube 网站", destination: URL(string: "https://hackertube.org")!)
                Text("视频精选自 Hacker News 二十年来被反复推荐的 YouTube 视频，数据来自 Andrej Karpathy 的 HackerTube。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
    }
}
