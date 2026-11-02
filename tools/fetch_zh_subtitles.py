#!/usr/bin/env python3
"""
下载视频作者上传的人工中文字幕，生成 subtitles/<videoID>.zh.json（格式同 .en.json）。
有中文轨的视频，App 直接用它，不再做本机翻译。

    python3 tools/fetch_zh_subtitles.py data/catalog.json --out subtitles [--limit 50] [--sleep 5]

只要人工字幕（--write-subs），不要自动字幕和机器翻译轨：翻译轨质量差，而且每条都要单独请求，容易 429。
繁体会用 opencc 转成简体（pip install opencc-python-reimplemented，可选；没装就保留原文）。
不要和英文全量任务同时大规模跑：同一个 IP 更容易被限流。
"""
import argparse, json, subprocess, sys, tempfile, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_subtitles import RateLimited, check_blocked  # noqa: E402

# 简体优先
ZH_LANGS = ["zh-Hans", "zh-CN", "zh-SG", "zh", "zh-Hant", "zh-TW", "zh-HK"]

try:
    import opencc
    _t2s = opencc.OpenCC("t2s")
    to_simplified = _t2s.convert
except Exception:
    to_simplified = None


def zh_subs(vid, tmp, duration=None):
    """返回 (语言码, cues)；没有人工中文字幕返回 None。"""
    cmd = ["yt-dlp", "--no-update", "--skip-download", "--write-subs", "--sub-langs", ",".join(ZH_LANGS),
           "--sub-format", "json3", "-o", f"{tmp}/%(id)s.%(ext)s", f"https://www.youtube.com/watch?v={vid}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    files = {p.name[len(vid) + 1:-len(".json3")]: p for p in Path(tmp).glob(f"{vid}.*.json3")}
    if not files:
        check_blocked(r.stderr)
        return None
    lang = next((l for l in ZH_LANGS if l in files), next(iter(files)))
    events = json.loads(files[lang].read_text()).get("events", [])
    for p in files.values():
        p.unlink()

    # 人工中文字幕本来就是按句切好的，一个事件一句，不像英文自动字幕那样需要合并
    cues = []
    for e in events:
        if "segs" not in e or "tStartMs" not in e:
            continue
        t = "".join(s.get("utf8", "") for s in e["segs"]).replace("\n", " ").strip()
        if not t:
            continue
        s = e["tStartMs"] / 1000
        cues.append({"s": round(s, 2), "e": round(s + e.get("dDurationMs", 2000) / 1000, 2), "t": t})
    for a, b in zip(cues, cues[1:]):
        if a["e"] > b["s"]:
            a["e"] = b["s"]
    if not cues:
        return None
    # 只覆盖开头一小段的（有的作者只传了片头）不算
    if duration and cues[-1]["e"] < duration * 0.5:
        return None
    if lang in ("zh-Hant", "zh-TW", "zh-HK") and to_simplified:
        for c in cues:
            c["t"] = to_simplified(c["t"])
    return lang, cues


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("catalog")
    ap.add_argument("--out", default="subtitles")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--sleep", type=float, default=3.0)
    ap.add_argument("--backoff", type=int, default=600)
    ap.add_argument("--retry-missing", action="store_true")
    args = ap.parse_args()

    videos = json.load(open(args.catalog))["videos"]
    videos.sort(key=lambda v: -(v.get("mentions") or 0))  # 热门视频优先，和英文脚本一致
    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    missing_file = out / "_missing_zh.txt"
    missing = set(missing_file.read_text().split()) if missing_file.exists() else set()
    todo = [v for v in videos if not (out / f"{v['id']}.zh.json").exists()
            and (args.retry_missing or v["id"] not in missing)]
    print(f"待处理 {len(todo)} 个（无中文字幕 {len(missing)}）", flush=True)
    if not todo:
        sys.exit(3)

    done = found = blocked = 0
    with tempfile.TemporaryDirectory() as tmp:
        for v in todo:
            if args.limit and done >= args.limit:
                break
            vid = v["id"]
            try:
                res = zh_subs(vid, tmp, v.get("duration"))
            except RateLimited as e:
                blocked += 1
                wait = args.backoff * min(blocked, 3)
                print(f"⚠ {vid} 被限流（第 {blocked} 次）：{e}；暂停 {wait // 60} 分钟", flush=True)
                time.sleep(wait)
                continue
            blocked = 0
            if res:
                lang, cues = res
                (out / f"{vid}.zh.json").write_text(json.dumps(
                    {"videoID": vid, "lang": lang, "cues": cues}, ensure_ascii=False, separators=(",", ":")))
                found += 1
                print(f"✓ {vid} {lang} {len(cues)} 句", flush=True)
            else:
                missing.add(vid)
                print(f"· {vid} 没有人工中文字幕", flush=True)
            done += 1
            time.sleep(args.sleep)
    if missing:
        missing_file.write_text("\n".join(sorted(missing)) + "\n")
    print(f"本次检查 {done} 个，{found} 个有中文字幕（{found / max(done, 1):.0%}）", flush=True)


if __name__ == "__main__":
    main()
