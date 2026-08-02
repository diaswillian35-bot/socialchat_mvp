#!/usr/bin/env bash
# Parte 8 — smoke Android share-in (debug install + intents).
# Uso: ./scripts/part8_android_share_smoke.sh
set -euo pipefail
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
SERIAL="${ANDROID_SERIAL:-R38M30CCS1T}"
PKG=com.remdy.app
ACTIVITY=com.example.socialchat_mvp.MainActivity

if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
  echo "DEVICE_OFFLINE serial=$SERIAL"
  "$ADB" devices -l
  exit 2
fi

echo "== query SEND text/plain =="
"$ADB" -s "$SERIAL" shell cmd package query-activities --brief \
  -a android.intent.action.SEND -t text/plain 2>/dev/null | tee /tmp/part8_share_targets.txt
if ! rg -q "$PKG|$ACTIVITY|remdy" /tmp/part8_share_targets.txt; then
  echo "FAIL: Remdy not in share targets yet (install debug build first)"
fi

echo "== share text =="
"$ADB" -s "$SERIAL" shell am start -a android.intent.action.SEND -t text/plain \
  --es android.intent.extra.TEXT "Parte8 smoke https://example.com/item" \
  -n "$PKG/$ACTIVITY"

sleep 2
echo "== share https only =="
"$ADB" -s "$SERIAL" shell am start -a android.intent.action.SEND -t text/plain \
  --es android.intent.extra.TEXT "https://www.amazon.com/dp/B0TEST" \
  -n "$PKG/$ACTIVITY"

echo "DONE — validate ShareIn UI on device manually"
