#!/bin/zsh
# Visual check: launch the built app at 1280×800 on a route and save a 2× PNG of the window.
# Usage: tools/snap.sh <route> [--fixtures]   → /tmp/folio-<route>.png
#
# Uses `screencapture -l <windowID>` when Screen Recording is allowed; otherwise the app's
# DEBUG-only -FolioSnapshot, which renders the window itself.
set -e
cd "$(dirname "$0")/.."
route=${1:-today}
app=build/DerivedData/Build/Products/Debug/Folio.app
fixtures=NO; [[ "$2" == "--fixtures" ]] && fixtures=YES
out="/tmp/folio-$route.png"
container_tmp=~/Library/Containers/app.folio.Folio/Data/tmp

pkill -x Folio 2>/dev/null || true
sleep 0.5
# Forget the remembered window frame so it opens at the default 1280×800.
defaults delete app.folio.Folio 2>/dev/null || true
rm -rf ~/Library/Containers/app.folio.Folio/Data/Library/Saved\ Application\ State 2>/dev/null || true

if screencapture -x /tmp/.folio-probe.png 2>/dev/null; then
  rm -f /tmp/.folio-probe.png
  open -n "$app" --args -FolioRoute "$route" -FolioDesignFixtures "$fixtures" -ApplePersistenceIgnoreState YES
  sleep 3
  screencapture -x -o -l "$(swift tools/window-id.swift Folio)" "$out"
else
  rm -f "$container_tmp/folio-$route.png"
  "$app/Contents/MacOS/Folio" -FolioRoute "$route" -FolioDesignFixtures "$fixtures" \
    -ApplePersistenceIgnoreState YES -FolioSnapshot "$route" 2>/dev/null | grep Snapshot || true
  cp "$container_tmp/folio-$route.png" "$out"
fi
sips -g pixelWidth -g pixelHeight "$out" | tail -2 | tr '\n' ' '
echo "\n$out"
