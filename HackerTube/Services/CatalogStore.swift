import Foundation
import Observation

/// 视频目录：先读 App 内置的 catalog.json，再尝试从 CDN 更新。
@Observable
@MainActor
final class CatalogStore {
    private(set) var videos: [Video] = []
    private(set) var byID: [String: Video] = [:]
    private(set) var categories: [(name: String, count: Int)] = []
    private(set) var isLoading = false

    private var cacheURL: URL {
        URL.cachesDirectory.appending(path: "catalog.json")
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        if let cached = try? Data(contentsOf: cacheURL), let catalog = decode(cached) {
            apply(catalog)
        } else if let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let catalog = decode(data) {
            apply(catalog)
        }

        // 后台尝试拉取最新目录
        // 离线或镜像都连不上时，用本地的就行
        if case .data(let data) = await RepoFetcher.fetch(AppConfig.catalogPath),
           let catalog = decode(data), catalog.videos.count >= videos.count {
            try? data.write(to: cacheURL)
            apply(catalog)
        }
    }

    private func decode(_ data: Data) -> Catalog? {
        try? JSONDecoder().decode(Catalog.self, from: data)
    }

    private func apply(_ catalog: Catalog) {
        videos = catalog.videos
        byID = Dictionary(catalog.videos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var counts: [String: Int] = [:]
        for v in catalog.videos { for c in v.categories { counts[c, default: 0] += 1 } }
        categories = counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    func videos(in category: String) -> [Video] {
        videos.filter { $0.categories.contains(category) }.sorted { ($0.mentions ?? 0) > ($1.mentions ?? 0) }
    }

    /// 指定 ID 的视频，按推荐次数排序（“有字幕”分类用）
    func videos(ids: Set<String>) -> [Video] {
        videos.filter { ids.contains($0.id) }.sorted { ($0.mentions ?? 0) > ($1.mentions ?? 0) }
    }

    func videos(duration: DurationBucket) -> [Video] {
        videos.filter { $0.durationBucket == duration }.sorted { ($0.mentions ?? 0) > ($1.mentions ?? 0) }
    }

    func search(_ query: String) -> [Video] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return videos.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.channel.localizedCaseInsensitiveContains(q)
        }
    }

    /// “为你推荐”：不需要账号，按本地喜欢/观看过的分类和频道加权，再混入一点随机性。
    func recommendations(library: LibraryStore, limit: Int = 60) -> [Video] {
        var catWeight: [String: Double] = [:]
        var chanWeight: [String: Double] = [:]
        func bump(_ id: String, _ w: Double) {
            guard let v = byID[id] else { return }
            v.categories.forEach { catWeight[$0, default: 0] += w }
            chanWeight[v.channel, default: 0] += w
        }
        library.likedIDs.forEach { bump($0, 3) }
        library.history.prefix(50).forEach { bump($0.videoID, 1) }

        let seen = Set(library.history.map(\.videoID))
        var rng = SeededGenerator(seed: UInt64(Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0))
        let scored = videos.filter { !seen.contains($0.id) }.map { v -> (Video, Double) in
            let pop = log(Double((v.mentions ?? 1) + 1))
            let pref = v.categories.reduce(0) { $0 + (catWeight[$1] ?? 0) } + (chanWeight[v.channel] ?? 0) * 0.5
            return (v, pop + pref + Double.random(in: 0..<2, using: &rng))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}

/// 每天固定种子，让首页一天之内保持稳定。
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
