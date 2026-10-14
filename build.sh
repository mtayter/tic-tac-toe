#!/bin/bash
# Manual Wear OS APK build for Tic-Tac-Toe (Pixel Watch 3):
# aapt2 + javac + d8 + zipalign + apksigner, no Gradle.
set -e
set -o pipefail

PROJ="$HOME/workspace/tictactoe"
# Local config (written by ./install.sh) may override tool paths and the
# debug keystore location. Falls back to the defaults below when absent.
# Env vars win over the config file: snapshot them before sourcing,
# because sourcing assigns TICTACTOE_* and would clobber env values.
ENV_SDK_DIR="${TICTACTOE_SDK_DIR:-}"
ENV_DEBUG_KEYSTORE="${TICTACTOE_DEBUG_KEYSTORE:-}"
TICTACTOE_CONFIG="${TICTACTOE_CONFIG_FILE:-$HOME/.config/tictactoe/config.env}"
[ -f "$TICTACTOE_CONFIG" ] && . "$TICTACTOE_CONFIG"
SDK="${ENV_SDK_DIR:-${TICTACTOE_SDK_DIR:-$HOME/workspace/tooling/android-sdk}}"
BT="$SDK/build-tools/34.0.0"
PLATFORM="$SDK/platforms/android-34/android.jar"
OUT="$PROJ/out"
APK="$PROJ/TicTacToe.apk"
# Signing key lives OUTSIDE out/: the build wipes $OUT every run, and a
# keystore inside it would be regenerated each time, breaking updates.
KEYSTORE="${ENV_DEBUG_KEYSTORE:-${TICTACTOE_DEBUG_KEYSTORE:-$PROJ/debug.keystore}}"

export JAVA_HOME="$(ls -d "$HOME"/workspace/tooling/jdk/jdk-* 2>/dev/null | head -1)"
if [ -z "$JAVA_HOME" ] || [ ! -x "$JAVA_HOME/bin/javac" ]; then
  JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
fi
JAVAC="$JAVA_HOME/bin/javac"
KEYTOOL="$JAVA_HOME/bin/keytool"
export PATH="$JAVA_HOME/bin:$PATH"

rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

if [ ! -f "$KEYSTORE" ]; then
  "$KEYTOOL" -genkeypair -keystore "$KEYSTORE" -alias androiddebugkey \
    -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10950 \
    -dname "CN=Android Debug,O=Android,C=US" 2>/dev/null
fi

echo "== aapt2 compile =="
"$BT/aapt2" compile --dir "$PROJ/res" -o "$OUT/compiled_res.zip"

echo "== aapt2 link =="
"$BT/aapt2" link -o "$OUT/app.unsigned.apk" -I "$PLATFORM" \
  --manifest "$PROJ/AndroidManifest.xml" \
  --min-sdk-version 30 --target-sdk-version 34 \
  --java "$OUT/gen" "$OUT/compiled_res.zip"

echo "== javac =="
find "$PROJ/java" "$OUT/gen" -name "*.java" > "$OUT/sources.txt"
"$JAVAC" -encoding UTF-8 --release 17 -cp "$PLATFORM" -d "$OUT/classes" @"$OUT/sources.txt"

echo "== d8 =="
"$BT/d8" --lib "$PLATFORM" --min-api 30 --output "$OUT/dex" \
  $(find "$OUT/classes" -name "*.class")

echo "== package dex =="
python3 - "$OUT/app.unsigned.apk" "$OUT/dex/classes.dex" "$OUT/app.withdex.apk" <<'EOF'
import sys, zipfile
src, dexf, dst = sys.argv[1], sys.argv[2], sys.argv[3]
with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        zout.writestr(item, zin.read(item.filename))
    zout.write(dexf, 'classes.dex')
EOF

echo "== zipalign + sign =="
"$BT/zipalign" -f 4 "$OUT/app.withdex.apk" "$OUT/app.aligned.apk"
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android \
  --out "$APK" "$OUT/app.aligned.apk"
"$BT/apksigner" verify --print-certs "$APK" | head -4
ls -la "$APK"
echo "TICTACTOE_BUILD_DONE"
