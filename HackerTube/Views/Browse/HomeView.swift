import SwiftUI

struct HomeView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    @Environment(SubtitleIndex.self) private var subtitleIndex
    @State private var chip: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                chips
                if chip == nil, !continueWatching.isEmpty {
                    Text("继续观看").font(.headline).padding([.horizontal, .top])
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(continueWatching, id: \.0.id) { item in
                                let v = item.0, pos = item.1
                                NavigationLink(value: v) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Thumbnail(video: v)
                                            .overlay(alignment: .bottom) {
                                                ProgressView(value: min(pos / Double(max(v.duration ?? 1, 1)), 1))
                                                    .tint(.red)
                                            }
                                        Text(v.title).font(.caption).lineLimit(2)
                                    }
                                    .frame(width: 200)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                VideoGrid(videos: feed)
            }
        }
        .overlay {
            if catalog.videos.isEmpty && !catalog.isLoading {
                EmptyHint(title: "还没有视频数据", systemImage: "tray", message: "检查网络后下拉刷新")
            }
        }
        .refreshable { await catalog.load() }
        .navigationTitle("HackerTube")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton("全部", selected: chip == nil) { chip = nil }
                if !subtitleIndex.withSubtitles.isEmpty {
                    let name = SubtitleIndex.categoryName
                    chipButton(name, selected: chip == name) { chip = name }
                }
                ForEach(catalog.categories.prefix(20), id: \.name) { c in
                    chipButton(c.name, selected: chip == c.name) { chip = c.name }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chipButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Color.primary : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color(.systemBackground) : .primary)
        }
        .buttonStyle(.plain)
    }

    private var feed: [Video] {
        if chip == SubtitleIndex.categoryName { return catalog.videos(ids: subtitleIndex.withSubtitles) }
        if let chip { return catalog.videos(in: chip) }
        return catalog.recommendations(library: library)
    }

    private var continueWatching: [(Video, Double)] {
        library.history.prefix(10).compactMap { h in
            guard let v = catalog.byID[h.videoID], h.position > 30,
                  Double(v.duration ?? 0) - h.position > 60 else { return nil }
            return (v, h.position)
        }
    }
}

struct LongsView: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var bucket: DurationBucket = .xlong

    var body: some View {
        ScrollView {
            Picker("时长", selection: $bucket) {
                ForEach(DurationBucket.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            VideoGrid(videos: catalog.videos(duration: bucket))
        }
        .navigationTitle("长视频")
    }
}

struct CategoriesView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SubtitleIndex.self) private var subtitleIndex

    var body: some View {
        List {
            if !subtitleIndex.withSubtitles.isEmpty {
                NavigationLink(value: CategoryRoute(name: SubtitleIndex.categoryName)) {
                    LabeledContent {
                        Text("\(catalog.videos(ids: subtitleIndex.withSubtitles).count)")
                    } label: {
                        Label(SubtitleIndex.categoryName, systemImage: "captions.bubble.fill")
                    }
                }
            }
            ForEach(catalog.categories, id: \.name) { c in
                NavigationLink(value: CategoryRoute(name: c.name)) {
                    LabeledContent(c.name, value: "\(c.count)")
                }
            }
        }
        .navigationTitle("分类")
    }
}

struct CategoryDetailView: View {
    let name: String
    @Environment(CatalogStore.self) private var catalog
    @Environment(SubtitleIndex.self) private var subtitleIndex
    @State private var sort: Sort = .popular
    @State private var onlyChinese = false

    private var isSubtitled: Bool { name == SubtitleIndex.categoryName }

    enum Sort: String, CaseIterable { case popular = "最多推荐", newest = "最新", oldest = "最早", longest = "最长" }

    var body: some View {
        ScrollView { VideoGrid(videos: sorted) }
            .navigationTitle(name)
            .toolbar {
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    if isSubtitled {
                        Toggle("只看作者中文字幕", isOn: $onlyChinese)
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
    }

    private var sorted: [Video] {
        let vs = isSubtitled
            ? catalog.videos(ids: onlyChinese ? subtitleIndex.withChinese : subtitleIndex.withSubtitles)
            : catalog.videos(in: name)
        switch sort {
        case .popular: return vs
        case .newest: return vs.sorted { ($0.published ?? "") > ($1.published ?? "") }
        case .oldest: return vs.sorted { ($0.published ?? "9") < ($1.published ?? "9") }
        case .longest: return vs.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        }
    }
}

struct SearchView: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var query = ""

    var body: some View {
        List(catalog.search(query).prefix(200)) { v in
            NavigationLink(value: v) { VideoRow(video: v) }
        }
        .listStyle(.plain)
        .overlay {
            if query.isEmpty { EmptyHint(title: "搜索视频", systemImage: "magnifyingglass", message: "按标题或频道名搜索") }
            else if catalog.search(query).isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, prompt: "标题或频道")
        .navigationTitle("搜索")
    }
}
