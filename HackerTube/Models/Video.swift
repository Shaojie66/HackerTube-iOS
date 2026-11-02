import Foundation

/// 一个被 Hacker News 推荐过的 YouTube 视频。
struct Video: Identifiable, Codable, Hashable {
    /// YouTube 视频 ID
    let id: String
    let title: String
    let channel: String
    /// 时长（秒）
    let duration: Int?
    /// 发布日期，ISO 8601（yyyy-MM-dd）
    let published: String?
    /// 所属分类（网站上约 150 个主题）
    let categories: [String]
    /// 在 HN 上被推荐的评论数
    let mentions: Int?
    /// 一条代表性的 HN 评论链接
    let hnURL: String?

    /// 用视频中间位置的帧当缩略图（YouTube 的 hq2.jpg 大约在 50% 处），和原站一致。
    var thumbnailURL: URL? {
        URL(string: "https://i.ytimg.com/vi/\(id)/hq2.jpg")
    }

    var youtubeURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    var durationText: String {
        guard let d = duration, d > 0 else { return "" }
        let h = d / 3600, m = (d % 3600) / 60, s = d % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var year: String? { published.map { String($0.prefix(4)) } }

    /// 时长分档，对应网站 browse?dur= 参数
    var durationBucket: DurationBucket {
        DurationBucket.bucket(for: duration ?? 0)
    }
}

enum DurationBucket: String, CaseIterable, Identifiable {
    case short, medium, long, xlong
    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: "< 10 分钟"
        case .medium: "10–30 分钟"
        case .long: "30–60 分钟"
        case .xlong: "> 1 小时"
        }
    }

    static func bucket(for seconds: Int) -> DurationBucket {
        switch seconds {
        case ..<600: .short
        case ..<1800: .medium
        case ..<3600: .long
        default: .xlong
        }
    }
}

struct Catalog: Codable {
    var version: Int
    var videos: [Video]
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var videoIDs: [String]
    var created = Date()
}

struct HistoryEntry: Codable, Hashable {
    let videoID: String
    var watchedAt: Date
    /// 上次看到的位置（秒）
    var position: Double
}
