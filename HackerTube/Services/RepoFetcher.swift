import Foundation
import Observation
import os

let netLog = Logger(subsystem: "org.hackertube.ios", category: "net")

/// 从仓库下载文件：依次尝试各个镜像，每个镜像最多等 8 秒。
enum RepoFetcher {
    enum Result { case data(Data), notFound, failed }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 20
        return URLSession(configuration: c)
    }()

    /// 404 说明文件确实不存在，不用再试别的镜像；超时或其他错误才换下一个。
    static func fetch(_ path: String) async -> Result {
        for base in AppConfig.mirrors {
            let url = base.appending(path: path)
            do {
                let (data, resp) = try await session.data(from: url)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200 { return .data(data) }
                netLog.notice("\(url.host ?? "", privacy: .public) \(path, privacy: .public) -> \(code)")
                if code == 404 { return .notFound }
            } catch {
                netLog.error("\(url.host ?? "", privacy: .public) \(path, privacy: .public) 失败：\(error.localizedDescription, privacy: .public)")
            }
        }
        return .failed
    }

    static func get(_ url: URL) async -> Data? {
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else {
            netLog.error("\(url.host ?? "", privacy: .public) 文件清单获取失败")
            return nil
        }
        return data
    }
}

/// 哪些视频已经有字幕。启动时从仓库文件清单里取一次，用于在缩略图上标 CC。
@Observable
@MainActor
final class SubtitleIndex {
    /// 分类页和首页里“有字幕”这一项的名字
    static let categoryName = "有字幕"

    private(set) var withSubtitles: Set<String> = []
    /// 其中有视频作者上传的中文字幕的
    private(set) var withChinese: Set<String> = []

    func has(_ id: String) -> Bool { withSubtitles.contains(id) }
    func hasChinese(_ id: String) -> Bool { withChinese.contains(id) }

    func load() async {
        for url in AppConfig.fileListURLs {
            guard let data = await RepoFetcher.get(url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // jsDelivr: files[].name = "/subtitles/x.en.json"；GitHub: tree[].path = "subtitles/x.en.json"
            let names = ((obj["files"] as? [[String: Any]])?.compactMap { $0["name"] as? String })
                ?? ((obj["tree"] as? [[String: Any]])?.compactMap { $0["path"] as? String }) ?? []
            var all = Set<String>(), zh = Set<String>()
            for raw in names {
                let n = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
                guard n.hasPrefix("subtitles/"), n.hasSuffix(".en.json") || n.hasSuffix(".zh.json") else { continue }
                let id = String(n.dropFirst("subtitles/".count).dropLast(".en.json".count))
                all.insert(id)
                if n.hasSuffix(".zh.json") { zh.insert(id) }
            }
            if !all.isEmpty { withSubtitles = all; withChinese = zh; return }
        }
    }
}
