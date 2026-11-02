import Foundation
import Observation

/// 用户在本机的所有状态：喜欢、历史、稍后观看、播放列表。和原站一样不需要登录。
@Observable
@MainActor
final class LibraryStore {
    private(set) var likedIDs: [String] = []
    private(set) var history: [HistoryEntry] = []
    private(set) var watchLaterIDs: [String] = []
    private(set) var playlists: [Playlist] = []

    private struct Snapshot: Codable {
        var liked: [String]
        var history: [HistoryEntry]
        var later: [String]
        var playlists: [Playlist]
    }

    private let fileURL = URL.documentsDirectory.appending(path: "library.json")

    init() { load() }

    // MARK: 喜欢
    func isLiked(_ id: String) -> Bool { likedIDs.contains(id) }
    func toggleLike(_ id: String) {
        if let i = likedIDs.firstIndex(of: id) { likedIDs.remove(at: i) } else { likedIDs.insert(id, at: 0) }
        save()
    }

    // MARK: 稍后观看
    func isInWatchLater(_ id: String) -> Bool { watchLaterIDs.contains(id) }
    func toggleWatchLater(_ id: String) {
        if let i = watchLaterIDs.firstIndex(of: id) { watchLaterIDs.remove(at: i) } else { watchLaterIDs.insert(id, at: 0) }
        save()
    }

    // MARK: 历史
    func recordWatch(_ id: String, position: Double) {
        history.removeAll { $0.videoID == id }
        history.insert(HistoryEntry(videoID: id, watchedAt: .now, position: position), at: 0)
        if history.count > 1000 { history.removeLast(history.count - 1000) }
        save()
    }
    func lastPosition(_ id: String) -> Double { history.first { $0.videoID == id }?.position ?? 0 }
    func removeFromHistory(_ id: String) { history.removeAll { $0.videoID == id }; save() }
    func clearHistory() { history.removeAll(); save() }

    // MARK: 播放列表
    func createPlaylist(_ name: String) -> Playlist {
        let p = Playlist(name: name, videoIDs: [])
        playlists.insert(p, at: 0)
        save()
        return p
    }
    func add(_ videoID: String, to playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[i].videoIDs.contains(videoID) else { return }
        playlists[i].videoIDs.append(videoID)
        save()
    }
    func remove(_ videoID: String, from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].videoIDs.removeAll { $0 == videoID }
        save()
    }
    func deletePlaylist(_ id: UUID) { playlists.removeAll { $0.id == id }; save() }
    func renamePlaylist(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = name
        save()
    }

    // MARK: 持久化
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        likedIDs = s.liked; history = s.history; watchLaterIDs = s.later; playlists = s.playlists
    }

    private func save() {
        let s = Snapshot(liked: likedIDs, history: history, later: watchLaterIDs, playlists: playlists)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: fileURL, options: .atomic) }
    }
}
