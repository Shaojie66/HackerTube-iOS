import Foundation

/// 一句字幕，带英文原文和（可能已翻译好的）中文。
struct SubtitleCue: Codable, Hashable, Identifiable {
    var id: Int
    let start: Double
    let end: Double
    let en: String
    var zh: String?
}

/// 仓库里预生成的字幕文件格式：subtitles/<videoID>.en.json
struct SubtitleFile: Codable {
    let videoID: String
    let lang: String
    let cues: [Cue]

    struct Cue: Codable {
        let s: Double   // 开始秒
        let e: Double   // 结束秒
        let t: String   // 文本
    }
}

extension Array where Element == SubtitleCue {
    /// 二分查找当前时间对应的字幕
    func cue(at time: Double) -> SubtitleCue? {
        var lo = 0, hi = count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let c = self[mid]
            if time < c.start { hi = mid - 1 }
            else if time >= c.end { lo = mid + 1 }
            else { return c }
        }
        return nil
    }

    /// 和 [start, end) 重叠时间最长的一句；重叠不到 0.2 秒的不算
    func bestOverlap(start: Double, end: Double) -> SubtitleCue? {
        // 先二分找到第一句 end > start 的位置，再往后看到 start >= end 为止
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if self[mid].end <= start { lo = mid + 1 } else { hi = mid }
        }
        var best: SubtitleCue?, bestLen = 0.2
        var i = lo
        while i < count, self[i].start < end {
            let len = Swift.min(end, self[i].end) - Swift.max(start, self[i].start)
            if len > bestLen { best = self[i]; bestLen = len }
            i += 1
        }
        return best
    }
}
