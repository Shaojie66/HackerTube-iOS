#!/usr/bin/env python3
"""
批量下载英文字幕，生成 App 用的 subtitles/<videoID>.en.json。

在 Mac 上运行：
    pip install yt-dlp            # 必需
    pip install mlx-whisper       # 可选，给没有字幕的视频做语音转写（Apple 芯片）
    python3 tools/fetch_subtitles.py data/catalog.json --out subtitles [--whisper] [--limit 100]

优先用人工上传的英文字幕，其次 YouTube 自动字幕，都没有时（加 --whisper）才转写。
已存在的文件会跳过，可以随时中断再续跑。
"""
import argparse, json, os, re, subprocess, sys, tempfile, time
from pathlib import Path


def merge_json3(events):
    """自动字幕是逐词出现的，合并成完整句子。"""
    raw = []
    for e in events:
        if "segs" not in e or "tStartMs" not in e:
            continue
        text = "".join(s.get("utf8", "") for s in e["segs"]).replace("\n", " ").strip()
        if not text:
            continue
        start = e["tStartMs"] / 1000
        raw.append((start, start + e.get("dDurationMs", 2000) / 1000, text))

    cues, buf, bs, be = [], "", 0.0, 0.0
    def flush():
        nonlocal buf
        t = re.sub(r"\s+", " ", buf).strip()
        if t:
            cues.append({"s": round(bs, 2), "e": round(be, 2), "t": t})
        buf = ""
    for s, e, t in raw:
        if not buf:
            bs = s
        buf += (" " if buf else "") + t
        be = e
        if t.endswith((".", "?", "!")) or len(buf) > 90 or be - bs > 6:
            flush()
    flush()
    for a, b in zip(cues, cues[1:]):
        if a["e"] > b["s"]:
            a["e"] = b["s"]
    return cues


def ytdlp_subs(vid, tmp, duration=None):
    """返回 json3 events；先人工字幕再自动字幕。

    只要原生英文轨（en / en-US / en-GB / en-orig）。不能写 en.*：它会匹配几十条
    "English from X" 机器翻译轨，每条都要单独请求，很快触发 429。
    人工字幕如果只覆盖不到一半时长（有的上传者只传了开头），继续试自动字幕。
    """
    url = f"https://www.youtube.com/watch?v={vid}"
    best = None
    for flag in ("--write-subs", "--write-auto-subs"):
        cmd = ["yt-dlp", "--no-update", "--skip-download", flag, "--sub-langs", "en,en-US,en-GB,en-orig",
               "--sub-format", "json3", "-o", f"{tmp}/%(id)s.%(ext)s", url]
        subprocess.run(cmd, capture_output=True, text=True)
        files = sorted(Path(tmp).glob(f"{vid}*.json3"))
        if not files:
            continue
        # 优先 en，其次 en-orig 等
        files.sort(key=lambda p: (".en." not in p.name, len(p.name)))
        events = json.loads(files[0].read_text()).get("events", [])
        for f in files:
            f.unlink()
        if not events:
            continue
        end = max((e.get("tStartMs", 0) + e.get("dDurationMs", 0)) / 1000 for e in events)
        if not duration or end >= duration * 0.5:
            return events
        if best is None or end > best[0]:
            best = (end, events)
    return best[1] if best else None


def whisper_subs(vid, tmp):
    import mlx_whisper  # noqa
    audio = f"{tmp}/{vid}.m4a"
    subprocess.run(["yt-dlp", "-f", "bestaudio[ext=m4a]/bestaudio", "-o", audio,
                    f"https://www.youtube.com/watch?v={vid}"], capture_output=True)
    if not os.path.exists(audio):
        return None
    r = mlx_whisper.transcribe(audio, path_or_hf_repo="mlx-community/whisper-large-v3-turbo", language="en")
    os.remove(audio)
    return [{"s": round(s["start"], 2), "e": round(s["end"], 2), "t": s["text"].strip()}
            for s in r["segments"] if s["text"].strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("catalog")
    ap.add_argument("--out", default="subtitles")
    ap.add_argument("--whisper", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--sleep", type=float, default=1.0, help="每个视频之间的间隔，避免被限流")
    args = ap.parse_args()

    videos = json.load(open(args.catalog))["videos"]
    videos.sort(key=lambda v: -(v.get("mentions") or 0))  # 热门视频优先
    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    missing = []
    done = 0
    with tempfile.TemporaryDirectory() as tmp:
        for i, v in enumerate(videos):
            if args.limit and done >= args.limit:
                break
            vid = v["id"]
            dst = out / f"{vid}.en.json"
            if dst.exists():
                continue
            events = ytdlp_subs(vid, tmp, v.get("duration"))
            cues = merge_json3(events) if events else None
            if not cues and args.whisper:
                cues = whisper_subs(vid, tmp)
            if cues:
                dst.write_text(json.dumps({"videoID": vid, "lang": "en", "cues": cues},
                                          ensure_ascii=False, separators=(",", ":")))
                print(f"[{i+1}/{len(videos)}] ✓ {vid} {len(cues)} 句")
            else:
                missing.append(vid)
                print(f"[{i+1}/{len(videos)}] ✗ {vid} 没有字幕")
            done += 1
            time.sleep(args.sleep)
    if missing:
        Path(out / "_missing.txt").write_text("\n".join(missing))
        print(f"{len(missing)} 个视频没有字幕，列表见 {out}/_missing.txt")


if __name__ == "__main__":
    main()
