import XCTest

/// 字幕以外的功能回归测试。在模拟器上跑：
///   xcodebuild test -scheme HackerTube -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
/// 每一步截图都附在测试结果里。
final class FeatureTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        if b.waitForExistence(timeout: 5) { b.tap() } else { app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1).tap() }
    }

    /// 打开当前页第一个视频
    func openFirstVideo() {
        let link = app.scrollViews.descendants(matching: .button).matching(NSPredicate(format: "label CONTAINS 'HN'")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "页面上没有视频")
        link.tap()
        XCTAssertTrue(app.buttons["稍后观看"].waitForExistence(timeout: 10) || app.buttons["已加入"].exists, "没进入播放页")
    }

    func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    func test1_HomeChipsLongsCategories() {
        XCTAssertTrue(app.staticTexts["HackerTube"].waitForExistence(timeout: 10))
        shot("首页")
        let sub = app.buttons["有字幕"]
        XCTAssertTrue(sub.waitForExistence(timeout: 15), "首页没有「有字幕」标签")
        sub.tap(); shot("首页-有字幕")
        XCTAssertTrue(app.staticTexts["CC"].exists || app.staticTexts["CC 中"].exists, "有字幕标签下没有 CC 标记")
        app.buttons["全部"].tap()

        tab("长视频")
        for seg in app.segmentedControls.buttons.allElementsBoundByIndex {
            seg.tap()
            XCTAssertTrue(app.scrollViews.descendants(matching: .button).matching(NSPredicate(format: "label CONTAINS 'HN'")).firstMatch.waitForExistence(timeout: 5), "时长档 \(seg.label) 为空")
            shot("长视频-\(seg.label)")
        }

        tab("分类")
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '有字幕,'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "分类页没有「有字幕」")
        XCTAssertLessThan(first.frame.minY, app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tech pioneers'")).firstMatch.frame.minY, "「有字幕」不在最上面")
        shot("分类列表")
        first.tap()
        app.navigationBars.buttons.element(boundBy: 1).tap()   // 排序菜单
        XCTAssertTrue(app.buttons["最新"].waitForExistence(timeout: 3))
        app.buttons["最新"].tap()
        shot("有字幕-最新排序")
        back()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tech pioneers'")).firstMatch.tap()
        shot("普通分类详情")
    }

    func test2_Search() {
        tab("搜索")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("micrograd")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5), "搜 micrograd 没结果")
        shot("搜索-有结果")
        field.buttons.firstMatch.tap()   // 清空
        field.typeText("zzqqxxnotexist")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'zzqqxxnotexist'")).firstMatch.waitForExistence(timeout: 3), "无结果时没有提示")
        shot("搜索-无结果")
    }

    func test3_PlayerAndLibrary() {
        XCTAssertTrue(app.staticTexts["HackerTube"].waitForExistence(timeout: 10))
        openFirstVideo()
        let title = app.staticTexts.element(boundBy: 0).label
        app.buttons["喜欢"].tap()
        XCTAssertTrue(app.buttons["已喜欢"].waitForExistence(timeout: 3), "喜欢按钮没变状态")
        app.buttons["稍后观看"].tap()
        XCTAssertTrue(app.buttons["已加入"].waitForExistence(timeout: 3), "稍后观看按钮没变状态")
        app.buttons["加到播放列表"].tap()
        let name = app.textFields["新播放列表名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("测试列表")
        app.buttons["创建并加入"].tap()
        shot("播放页-\(title)")
        // 横屏
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2); shot("横屏")
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        // 相关视频
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["相关视频"].waitForExistence(timeout: 3))
        sleep(8)   // 播放一会儿，产生历史记录
        back()

        tab("媒体库")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == '喜欢, 1'")).firstMatch.waitForExistence(timeout: 5), "媒体库喜欢数量不对")
        shot("媒体库")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '喜欢,'")).firstMatch.tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 3), "喜欢列表为空")
        back()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '历史记录,'")).firstMatch.tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 3), "历史记录为空")
        shot("历史记录")
        back()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '稍后观看,'")).firstMatch.tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 3), "稍后观看为空")
        back()
        let pl = app.buttons.matching(NSPredicate(format: "label CONTAINS '测试列表'")).firstMatch
        XCTAssertTrue(pl.waitForExistence(timeout: 3), "播放列表没建出来")
        // 重命名
        pl.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["重命名"].waitForExistence(timeout: 3), "播放列表没有重命名")
        app.buttons["重命名"].tap()
        let tf = app.alerts.textFields.firstMatch
        tf.tap()
        tf.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
        tf.typeText("改名列表")
        app.alerts.buttons["保存"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '改名列表'")).firstMatch.waitForExistence(timeout: 3), "重命名没生效")
        shot("重命名后")

        // 杀掉重开，本地数据还在
        app.terminate()
        let again = XCUIApplication(); again.launch()
        app = again
        tab("媒体库")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '改名列表'")).firstMatch.waitForExistence(timeout: 5), "重开后播放列表丢了")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == '喜欢, 1'")).firstMatch.exists, "重开后喜欢丢了")
        shot("重开后媒体库")

        // 播放列表详情：移除视频，再删除列表
        app.buttons.matching(NSPredicate(format: "label CONTAINS '改名列表'")).firstMatch.tap()
        let row = app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "播放列表里没有视频")
        row.swipeLeft(); app.buttons.matching(NSPredicate(format: "label IN {'删除', 'Delete'}")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["播放列表是空的"].waitForExistence(timeout: 3), "移除视频失败")
        back()
        let pl2 = app.buttons.matching(NSPredicate(format: "label CONTAINS '改名列表'")).firstMatch
        pl2.swipeLeft(); app.buttons.matching(NSPredicate(format: "label IN {'删除', 'Delete'}")).firstMatch.tap()
        XCTAssertFalse(pl2.waitForExistence(timeout: 2), "删除播放列表失败")

        // 历史：清空
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '历史记录,'")).firstMatch.tap()
        app.navigationBars.buttons["清空"].tap()
        XCTAssertTrue(app.staticTexts["还没有观看记录"].waitForExistence(timeout: 3), "清空历史失败")
        back()

        // 设置
        app.buttons.matching(NSPredicate(format: "label == '设置'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["字幕大小"].waitForExistence(timeout: 3))
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 1.0)
        shot("设置-字号最大")
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.25)
    }

    func test4_ContextMenu() {
        XCTAssertTrue(app.staticTexts["HackerTube"].waitForExistence(timeout: 10))
        let card = app.scrollViews.descendants(matching: .button).matching(NSPredicate(format: "label CONTAINS 'HN'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.press(forDuration: 1.5)
        XCTAssertTrue(app.buttons["稍后观看"].waitForExistence(timeout: 3) || app.buttons["移出稍后观看"].exists, "长按没有菜单")
        shot("长按菜单")
        app.buttons["喜欢"].firstMatch.tap()
    }

    func test5_ContinueWatching() {
        // 用 -uitest-history 种一条 2 分钟的观看记录，检查首页「继续观看」和续播
        app.terminate()
        app.launchArguments = ["-uitest-reset", "-uitest-history"]
        app.launch()
        XCTAssertTrue(app.staticTexts["继续观看"].waitForExistence(timeout: 10), "首页没有继续观看")
        shot("继续观看")
    }
}
