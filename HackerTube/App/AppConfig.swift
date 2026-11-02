import Foundation

enum AppConfig {
    /// 仓库名，字幕和视频目录都从这个仓库通过 jsDelivr CDN 下载。
    static let repo = "Shaojie66/HackerTube-iOS"
    static let branch = "main"

    static var cdnBase: URL {
        URL(string: "https://cdn.jsdelivr.net/gh/\(repo)@\(branch)/")!
    }

    /// 远程视频目录（可选，有就覆盖 App 内置的那份）
    static var remoteCatalogURL: URL { cdnBase.appending(path: "data/catalog.json") }

    /// 预生成的字幕：en 是英文；zh 是视频作者上传的人工中文字幕（不是每个视频都有）
    static func subtitleURL(for videoID: String, lang: String = "en") -> URL {
        cdnBase.appending(path: "subtitles/\(videoID).\(lang).json")
    }

    /// YouTube 内嵌播放器需要一个合法的来源页，否则部分视频会报“播放器配置错误”。
    static let embedOrigin = "https://hackertube.org"
}
