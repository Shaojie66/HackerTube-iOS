#!/usr/bin/env python3
"""
从 hackertube.org 的 /api/list 分页拉取全部视频的时长、发布日期等 YouTube 元数据。
官方导出包不含这两项，build_catalog.py --meta 用它补齐。约 65 次请求，每次间隔 0.5 秒。

    python3 tools/fetch_site_meta.py --out /tmp/ht/youtube_meta.json
"""
import argparse, json, time, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--base", default="https://hackertube.org")
a = ap.parse_args()

rows, off = [], 0
while True:
    req = urllib.request.Request(f"{a.base}/api/list?n=100&offset={off}",
                                 headers={"User-Agent": "HackerTube-iOS catalog builder"})
    page = json.load(urllib.request.urlopen(req, timeout=30))
    if not page:
        break
    rows += page
    off += len(page)
    time.sleep(0.5)

json.dump(rows, open(a.out, "w"), ensure_ascii=False)
print(f"拉取 {len(rows)} 条 → {a.out}")
