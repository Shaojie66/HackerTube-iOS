import SwiftUI

@main
struct HackerTubeApp: App {
    @State private var catalog = CatalogStore()
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(catalog)
                .environment(library)
                .task { await catalog.load() }
                .tint(.orange)   // HN 橙
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("首页", systemImage: "house") { NavStack { HomeView() } }
            Tab("长视频", systemImage: "film.stack") { NavStack { LongsView() } }
            Tab("分类", systemImage: "square.grid.2x2") { NavStack { CategoriesView() } }
            Tab("媒体库", systemImage: "books.vertical") { NavStack { LibraryView() } }
            // 搜索标签的输入框长在标签栏里，在这里隐藏标签栏会让推进来的页面变成空白
            Tab(role: .search) { NavStack { SearchView() }.environment(\.hidesTabBarOnPlayer, false) }
        }
    }
}

/// 每个标签页共用的导航栈，点视频统一进入播放页。
struct NavStack<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: Video.self) { PlayerScreen(video: $0) }
                .navigationDestination(for: CategoryRoute.self) { CategoryDetailView(name: $0.name) }
                .navigationDestination(for: Playlist.ID.self) { PlaylistDetailView(playlistID: $0) }
        }
    }
}

struct CategoryRoute: Hashable { let name: String }

extension EnvironmentValues {
    /// 播放页是否隐藏底部标签栏（搜索标签里不能隐藏）
    @Entry var hidesTabBarOnPlayer = true
}
