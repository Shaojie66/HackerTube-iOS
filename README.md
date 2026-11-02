# HackerTube iOS

[HackerTube](https://hackertube.org/) 的 iOS 客户端：收录 Hacker News 二十年来被反复推荐的 YouTube 技术/教育视频，并给每个视频配上**中英双语字幕**。

## 功能

- 首页（按本地喜好推荐，不需要账号）、长视频、分类、搜索
- 媒体库：喜欢、历史记录（含续播位置）、稍后观看、播放列表，全部存在手机本地
- 播放器：YouTube 官方内嵌播放器 + 自绘双语字幕层，支持横屏；字幕可切换 中英双语 / 仅中文 / 仅英文 / 关闭，可调字号
- 缩略图用视频中间帧（`hq2.jpg`），和原站一致

## 字幕怎么来的

1. **英文**：`tools/fetch_subtitles.py` 用 yt-dlp 批量下载 YouTube 字幕（人工字幕优先，其次自动字幕，可选 Whisper 转写），合并成整句，存为 `subtitles/<videoID>.en.json`，App 通过 jsDelivr CDN 按需下载。仓库里没有的视频，App 会尝试直接读取 YouTube 字幕作为兜底。
2. **中文**：App 用 iOS 18 自带的 [Translation 框架](https://developer.apple.com/documentation/translation) 在本机翻译，免费、离线、无需 API key。从当前播放位置开始翻，翻好后缓存，下次秒开。

## 运行

需要 macOS + Xcode 16 以上，iOS 18 以上设备或模拟器。

```bash
brew install xcodegen
xcodegen            # 生成 HackerTube.xcodeproj
open HackerTube.xcodeproj
```

> 系统翻译在模拟器上可能不可用，建议用真机测试中文字幕。

## 数据

```bash
# 1. 把 HackerTube 网站导出的数据转换成视频目录
python3 tools/build_catalog.py <导出文件或目录> --out data/catalog.json
cp data/catalog.json HackerTube/Resources/catalog.json   # 内置一份，离线可用

# 2. 批量下载英文字幕（可中断续跑）
pip install yt-dlp
python3 tools/fetch_subtitles.py data/catalog.json --out subtitles
```

`HackerTube/Resources/catalog.json` 目前只是几个示例视频，等拿到导出数据后替换。

## 目录

```
HackerTube/
  App/          入口、标签页、配置（仓库名 / CDN 地址）
  Models/       Video、字幕数据结构
  Services/     视频目录、本地媒体库、字幕下载与缓存
  Views/        首页、分类、媒体库、播放器（YouTube 内嵌 + 双语字幕 + 本机翻译）
tools/          数据转换、字幕批量下载脚本
data/           视频目录（CDN 读取）
subtitles/      英文字幕（CDN 读取）
```
