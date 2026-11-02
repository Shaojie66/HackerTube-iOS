#!/bin/bash
# 后台跑全量字幕：每 300 个提交并推送一次 subtitles/ 到 main。
#   cd ~/code/HackerTube-subs && caffeinate -i nohup tools/run_subtitles.sh >> ~/code/hackertube-subs.log 2>&1 &
# 中断后重新执行即可续跑（已下载的、确认没字幕的都会跳过）。
cd "$(dirname "$0")/.." || exit 1
BATCH=${BATCH:-300}
while true; do
  echo "=== $(date '+%F %T') 开始新一批（$BATCH 个）"
  python3 -I tools/fetch_subtitles.py data/catalog.json --out subtitles --sleep 3 --limit "$BATCH"
  rc=$?
  n=$(ls subtitles/*.en.json 2>/dev/null | wc -l | tr -d ' ')
  m=$(wc -l < subtitles/_missing.txt 2>/dev/null | tr -d ' ')
  git add subtitles/
  if ! git diff --cached --quiet; then
    git commit -q -m "字幕进度：${n}/6454 已完成，${m:-0} 个无字幕" \
      && for i in 1 2 3 4; do git pull -q --rebase --autostash origin main && git push -q origin main && break; sleep $((2**i)); done \
      && echo "=== 已推送：${n} 个字幕"
  fi
  [ $rc -eq 3 ] && { echo "=== $(date '+%F %T') 全部完成"; break; }
  [ $rc -ne 0 ] && { echo "=== 脚本异常退出（$rc），5 分钟后重试"; sleep 300; }
done
