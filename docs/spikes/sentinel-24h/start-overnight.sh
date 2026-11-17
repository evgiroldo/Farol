#!/bin/sh
# Starts the overnight sentinel measurement (run 6). Throwaway spike tooling, not Farol.
# Archives the previous run's files, starts FarolSpike.app, and keeps the Mac awake
# (the screen may still turn off) until FarolSpike quits. Stop in the morning with:
#   pkill -x FarolSpike
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
data="$HOME/Library/Application Support/FarolSpike"
run="${1:-run6}"

if pgrep -x FarolSpike >/dev/null; then
    echo "FarolSpike is already running. Stop it first: pkill -x FarolSpike"
    exit 1
fi

archive="$data/previous-before-$run"
mkdir -p "$archive"
for f in measure.csv breakdown.csv history.sqlite history.sqlite-shm history.sqlite-wal; do
    if [ -e "$data/$f" ]; then mv "$data/$f" "$archive/$f"; fi
done

open "$here/FarolSpike.app"
sleep 3
pid="$(pgrep -x FarolSpike || true)"
if [ -z "$pid" ]; then
    echo "FarolSpike did not start."
    exit 1
fi
nohup caffeinate -i -w "$pid" >/dev/null 2>&1 &

echo "Measurement $run started at $(date '+%H:%M'). Leave the Mac on the charger and do not use it."
echo "You can close this window. In the morning: pkill -x FarolSpike"
