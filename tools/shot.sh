#!/bin/sh
# Grow a forest in a window for a while and save a screenshot.
# usage: tools/shot.sh out.png real_seconds [extra game args...]
out="$1"; secs="$2"; shift 2
godot --path "$(dirname "$0")/.." --resolution 1280x720 -- --shot "$out" "$secs" "$@" 2>&1 &
pid=$!
( sleep $((secs + 40)); kill $pid 2>/dev/null ) &
wait $pid 2>/dev/null
