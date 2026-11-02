import Foundation
import Observation
import Translation

enum SubtitleMode: String, CaseIterable, Identifiable {
    case bilingual, chinese, english, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bilingual: "中英双语"
        case .chinese: "仅中文"
        case .english: "仅英文"
        case .off: "关闭"
        }
    }
}

/// 一个视频的字幕状态：加载英文 → 用苹果 Translation 框架在本机逐批翻成中文。
@Observable
@MainActor
final class SubtitleModel {
    enum Status: Equatable {
        case idle, loading, ready, unavailable
        case translating(done: Int, total: Int)
        case translationFailed(String)
    }

    let videoID: String
    private(set) var cues: [SubtitleCue] = []
    private(set) var status: Status = .idle
    /// 设置后会触发 SwiftUI 的 .translationTask
    var translationConfig: TranslationSession.Configuration?

    init(videoID: String) { self.videoID = videoID }

    func load() async {
        guard status == .idle else { return }
        status = .loading
        do {
            cues = try await SubtitleService.shared.cues(for: videoID)
            status = .ready
            if cues.contains(where: { $0.zh == nil }) {
                translationConfig = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "zh-Hans"))
            }
        } catch {
            status = .unavailable
        }
    }

    /// 在 .translationTask 闭包里调用。从当前播放位置开始先翻，再回头翻前面的，用户马上就能看到中文。
    func translate(using session: TranslationSession, from time: Double) async {
        let pending = cues.indices.filter { cues[$0].zh == nil }
        guard !pending.isEmpty else { return }
        let pivot = pending.firstIndex { cues[$0].end >= time } ?? 0
        let ordered = Array(pending[pivot...] + pending[..<pivot])

        var done = cues.count - pending.count
        status = .translating(done: done, total: cues.count)
        do {
            try await session.prepareTranslation()
            for chunk in ordered.chunked(into: 40) {
                let requests = chunk.map {
                    TranslationSession.Request(sourceText: cues[$0].en, clientIdentifier: String($0))
                }
                let responses = try await session.translations(from: requests)
                for r in responses {
                    if let id = r.clientIdentifier, let i = Int(id), cues.indices.contains(i) {
                        cues[i].zh = r.targetText
                    }
                }
                done += chunk.count
                status = .translating(done: done, total: cues.count)
                if Task.isCancelled { break }
            }
            await SubtitleService.shared.save(cues, for: videoID)
            status = .ready
        } catch {
            await SubtitleService.shared.save(cues, for: videoID)
            status = .translationFailed(error.localizedDescription)
        }
    }

    func cue(at time: Double) -> SubtitleCue? { cues.cue(at: time) }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
