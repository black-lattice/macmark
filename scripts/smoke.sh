#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
dist/MacMark.app/Contents/MacOS/MacMark -didShowWelcome YES > .build/smoke.log 2>&1 &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true' EXIT
sleep 3
kill -0 "$APP_PID"
{
  echo "Runner architecture: $(uname -m)"
  echo "Idle menu-bar process samples: CPU percent, RSS KiB"
  echo "短时间 CI 样本，仅供参考，不代表其他机器或长期能耗。"
  for SAMPLE in 1 2 3 4 5; do
    ps -p "$APP_PID" -o %cpu=,rss=
    sleep 1
  done
} > dist/idle-sample.txt
cat dist/idle-sample.txt
