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
}
