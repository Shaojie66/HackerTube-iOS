import Foundation

enum AppConfig {
    /// 仓库名，字幕和视频目录都从这个仓库下载。
    static let repo = "Shaojie66/HackerTube-iOS"
    static let branch = "main"

    /// 同一份仓库文件的多个下载地址，按顺序尝试。
    /// 大陆网络下 cdn.jsdelivr.net 经常连不上，fastly 节点和 GitHub 原始地址作后备。
    static var mirrors: [URL] {
        [
            URL(string: "https://cdn.jsdelivr.net/gh/\(repo)@\(branch)/")!,
            URL(string: "https://fastly.jsdelivr.net/gh/\(repo)@\(branch)/")!,
            URL(string: "https://raw.githubusercontent.com/\(repo)/\(branch)/")!,
        ]
    }

    /// 远程视频目录（可选，有就覆盖 App 内置的那份）
    static let catalogPath = "data/catalog.json"

    /// 预生成的字幕：en 是英文；zh 是视频作者上传的人工中文字幕（不是每个视频都有）
    static func subtitlePath(for videoID: String, lang: String = "en") -> String {
        "subtitles/\(videoID).\(lang).json"
    }

    /// 仓库文件清单，用来知道哪些视频已经有字幕（给缩略图打 CC 标记）
    static var fileListURLs: [URL] {
        [
            URL(string: "https://data.jsdelivr.com/v1/packages/gh/\(repo)@\(branch)?structure=flat")!,
            URL(string: "https://api.github.com/repos/\(repo)/git/trees/\(branch)?recursive=1")!,
        ]
    }

    /// YouTube 内嵌播放器需要一个合法的来源页，否则部分视频会报“播放器配置错误”。
    static let embedOrigin = "https://hackertube.org"
}
