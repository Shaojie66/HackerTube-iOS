#!/usr/bin/env python3
"""
把 HackerTube 导出的数据转换成 App 用的 data/catalog.json。

    python3 tools/build_catalog.py <导出文件或解压后的目录> --out data/catalog.json

导出包的具体格式拿到后再对齐；这里先按常见字段名做了兼容（JSON / JSONL / CSV）。
"""
import argparse, csv, json, re, sys
from pathlib import Path

ALIASES = {
    "id": ["id", "video_id", "videoId", "youtube_id", "yt_id"],
    "title": ["title", "video_title", "name"],
    "channel": ["channel", "channel_title", "channelTitle", "author", "uploader"],
    "duration": ["duration", "duration_s", "duration_sec", "seconds", "length"],
    "published": ["published", "published_at", "publishedAt", "upload_date", "date"],
    "categories": ["categories", "category", "topics", "topic", "tags"],
    "mentions": ["mentions", "num_comments", "comment_count", "hn_mentions", "score", "count"],
    "hnURL": ["hn_url", "hnURL", "hn_link", "comment_url"],
}


def pick(row, key):
    for k in ALIASES[key]:
        if k in row and row[k] not in (None, ""):
            return row[k]
    return None


def iso_duration(v):
    if isinstance(v, (int, float)):
        return int(v)
    if isinstance(v, str):
        if v.isdigit():
            return int(v)
        m = re.fullmatch(r"P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", v)
        if m:
            d, h, mi, s = (int(x or 0) for x in m.groups())
            return d * 86400 + h * 3600 + mi * 60 + s
        parts = v.split(":")
        if all(p.isdigit() for p in parts):
            t = 0
            for p in parts:
                t = t * 60 + int(p)
            return t
    return None


def load_rows(path):
    files = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.suffix in (".json", ".jsonl", ".csv"))
    for f in files:
        if f.suffix == ".csv":
            yield from csv.DictReader(open(f, encoding="utf-8"))
        elif f.suffix == ".jsonl":
            for line in open(f, encoding="utf-8"):
                if line.strip():
                    yield json.loads(line)
        else:
            data = json.load(open(f, encoding="utf-8"))
            if isinstance(data, dict):
                data = next((v for v in data.values() if isinstance(v, list)), [data])
            yield from (r for r in data if isinstance(r, dict))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--out", default="data/catalog.json")
    a = ap.parse_args()

    videos = {}
    for r in load_rows(Path(a.src)):
        vid = pick(r, "id")
        if not vid or not re.fullmatch(r"[\w-]{11}", str(vid)):
            continue
        cats = pick(r, "categories") or []
        if isinstance(cats, str):
            cats = [c.strip() for c in re.split(r"[;,|]", cats) if c.strip()]
        pub = pick(r, "published")
        if pub and re.fullmatch(r"\d{8}", str(pub)):
            pub = f"{pub[:4]}-{pub[4:6]}-{pub[6:]}"
        m = pick(r, "mentions")
        v = videos.setdefault(vid, {"id": vid, "categories": []})
        v.update({
            "title": pick(r, "title") or v.get("title") or vid,
            "channel": pick(r, "channel") or v.get("channel") or "",
            "duration": iso_duration(pick(r, "duration")) or v.get("duration"),
            "published": (str(pub)[:10] if pub else v.get("published")),
            "mentions": int(m) if m is not None and str(m).isdigit() else v.get("mentions"),
            "hnURL": pick(r, "hnURL") or v.get("hnURL"),
        })
        v["categories"] = sorted(set(v["categories"]) | set(cats))

    out = Path(a.out); out.parent.mkdir(parents=True, exist_ok=True)
    json.dump({"version": 1, "videos": list(videos.values())}, open(out, "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"写入 {len(videos)} 个视频 → {out}")


if __name__ == "__main__":
    main()
