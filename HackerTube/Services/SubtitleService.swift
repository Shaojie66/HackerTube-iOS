import Foundation

/// 负责拿到英文字幕，并缓存翻译好的中文。
/// 英文来源顺序：本地缓存 → 仓库里预生成的字幕（CDN）→ YouTube 自带字幕接口（不保证可用）。
actor SubtitleService {
    static let shared = SubtitleService()

    enum SubtitleError: Error { case notFound }

    private let dir: URL = {
        let d = URL.cachesDirectory.appending(path: "subtitles", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func cacheURL(_ id: String) -> URL { dir.appending(path: "\(id).json") }

    /// 读取字幕（含已缓存的中文翻译）
    func cues(for videoID: String) async throws -> [SubtitleCue] {
        if let data = try? Data(contentsOf: cacheURL(videoID)),
           let cached = try? JSONDecoder().decode([SubtitleCue].self, from: data), !cached.isEmpty {
            return cached
        }
        var cues = try await fetchFromCDN(videoID)
        if cues.isEmpty { cues = try await fetchFromYouTube(videoID) }
        guard !cues.isEmpty else { throw SubtitleError.notFound }
        save(cues, for: videoID)
        return cues
    }

    /// 翻译完后保存，下次打开同一个视频不用再翻
    func save(_ cues: [SubtitleCue], for videoID: String) {
        if let data = try? JSONEncoder().encode(cues) {
            try? data.write(to: cacheURL(videoID), options: .atomic)
        }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - 来源 1：仓库预生成的字幕

    private func fetchFromCDN(_ id: String) async throws -> [SubtitleCue] {
        let (data, resp) = try await URLSession.shared.data(from: AppConfig.subtitleURL(for: id))
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let file = try? JSONDecoder().decode(SubtitleFile.self, from: data) else { return [] }
        return file.cues.enumerated().map { i, c in
            SubtitleCue(id: i, start: c.s, end: c.e, en: c.t)
        }
    }

    // MARK: - 来源 2：YouTube timedtext（非公开接口，可能随时失效，只作兜底）

    private struct JSON3: Decodable {
        struct Event: Decodable {
            let tStartMs: Double?
            let dDurationMs: Double?
            let segs: [Seg]?
        }
        struct Seg: Decodable { let utf8: String? }
        let events: [Event]?
    }

    private func fetchFromYouTube(_ id: String) async throws -> [SubtitleCue] {
        for kind in ["", "&kind=asr"] {
            guard let url = URL(string: "https://www.youtube.com/api/timedtext?v=\(id)&lang=en&fmt=json3\(kind)") else { continue }
            guard let result = try? await URLSession.shared.data(from: url) else { continue }
            let data = result.0
            guard !data.isEmpty, let json = try? JSONDecoder().decode(JSON3.self, from: data) else { continue }
            let cues = Self.merge(json.events ?? [])
            if !cues.isEmpty { return cues }
        }
        return []
    }

    /// 自动字幕是一个词一个词蹦出来的，这里合并成完整的句子，方便翻译和阅读。
    private static func merge(_ events: [JSON3.Event]) -> [SubtitleCue] {
        var raw: [(Double, Double, String)] = []
        for e in events {
            guard let start = e.tStartMs, let segs = e.segs else { continue }
            let text = segs.compactMap(\.utf8).joined()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            raw.append((start / 1000, (start + (e.dDurationMs ?? 2000)) / 1000, text))
        }
        var out: [SubtitleCue] = []
        var buf = "", bufStart = 0.0, bufEnd = 0.0
        func flush() {
            let t = buf.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(SubtitleCue(id: out.count, start: bufStart, end: bufEnd, en: t)) }
            buf = ""
        }
        for (s, e, t) in raw {
            if buf.isEmpty { bufStart = s }
            buf += (buf.isEmpty ? "" : " ") + t
            bufEnd = e
            let endsSentence = t.hasSuffix(".") || t.hasSuffix("?") || t.hasSuffix("!")
            if endsSentence || buf.count > 90 || bufEnd - bufStart > 6 { flush() }
        }
        flush()
        // 避免上下两句时间重叠
        for i in out.indices.dropLast() where out[i].end > out[i + 1].start {
            out[i] = SubtitleCue(id: out[i].id, start: out[i].start, end: out[i + 1].start, en: out[i].en, zh: out[i].zh)
        }
        return out
    }
}
