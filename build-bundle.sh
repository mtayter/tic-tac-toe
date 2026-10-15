#!/bin/bash
# AAB packaging for Google Play: aapt2 (proto format) + bundletool + jarsigner.
# Target API 36 (Wear OS new-app requirement: 35+). minSdk 30 (Wear OS 3+).
# Output: <repo>/TicTacToe.aab (signed with the project's
# upload key — Play App Signing re-signs on upload).
set -e
set -o pipefail
# Repo root: this script lives at the repo root, so all repo paths derive
# from it instead of a hardcoded checkout location.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$ROOT"
# Local config (written by ./install.sh) provides tool paths, keystore,
# alias, and release password. Falls back to the defaults / legacy
# .ks-pass file below when no config exists.
# Env vars win over the config file: snapshot them before sourcing,
# because sourcing assigns TICTACTOE_* and would clobber env values.
ENV_SDK_DIR="${TICTACTOE_SDK_DIR:-}"
ENV_RELEASE_KEYSTORE="${TICTACTOE_RELEASE_KEYSTORE:-}"
ENV_RELEASE_KEY_ALIAS="${TICTACTOE_RELEASE_KEY_ALIAS:-}"
ENV_RELEASE_KEYSTORE_PASS="${TICTACTOE_RELEASE_KEYSTORE_PASS:-}"
ENV_BUNDLETOOL_JAR="${TICTACTOE_BUNDLETOOL_JAR:-}"
TICTACTOE_CONFIG="${TICTACTOE_CONFIG_FILE:-$HOME/.config/tictactoe/config.env}"
[ -f "$TICTACTOE_CONFIG" ] && . "$TICTACTOE_CONFIG"
SDK="${ENV_SDK_DIR:-${TICTACTOE_SDK_DIR:-$HOME/workspace/tooling/android-sdk}}"
BT="$SDK/build-tools/36.1.0"
PLATFORM="$SDK/platforms/android-36/android.jar"
OUT="$PROJ/out-bundle"
# Signing: release (upload) key for Google Play. Play App Signing re-signs on
# upload; this key becomes the permanent upload key — back it up.
KEYSTORE="${ENV_RELEASE_KEYSTORE:-${TICTACTOE_RELEASE_KEYSTORE:-$PROJ/release.keystore}}"
KS_ALIAS="${ENV_RELEASE_KEY_ALIAS:-${TICTACTOE_RELEASE_KEY_ALIAS:-tictactoe}}"
KS_PASS="${ENV_RELEASE_KEYSTORE_PASS:-${TICTACTOE_RELEASE_KEYSTORE_PASS:-}}"
if [ -z "$KS_PASS" ] && [ -f "$PROJ/.ks-pass" ]; then
  KS_PASS="$(cat "$PROJ/.ks-pass")"  # legacy location; run ./install.sh to migrate
fi
[ -n "$KS_PASS" ] || { echo "no release keystore password: run ./install.sh first" >&2; exit 1; }
BUNDLETOOL="${ENV_BUNDLETOOL_JAR:-${TICTACTOE_BUNDLETOOL_JAR:-$HOME/workspace/tooling/bundletool.jar}}"
AAB="$PROJ/TicTacToe.aab"

JAVA_HOME="$(ls -d "$HOME"/workspace/tooling/jdk/jdk-* 2>/dev/null | head -1)"
if [ -z "$JAVA_HOME" ] || [ ! -x "$JAVA_HOME/bin/javac" ]; then
  JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
fi
JAVAC="$JAVA_HOME/bin/javac"
export PATH="$JAVA_HOME/bin:$PATH"

[ -f "$KEYSTORE" ] || { echo "keystore missing: $KEYSTORE" >&2; exit 1; }
[ -f "$BUNDLETOOL" ] || { echo "bundletool.jar missing" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex" "$OUT/base/manifest" "$OUT/base/dex"

echo "== aapt2 compile =="
"$BT/aapt2" compile --dir "$PROJ/res" -o "$OUT/compiled_res.zip"

echo "== aapt2 link (proto, target 36) =="
"$BT/aapt2" link --proto-format -o "$OUT/proto.apk" -I "$PLATFORM" \
  --manifest "$PROJ/AndroidManifest.xml" \
  --min-sdk-version 30 --target-sdk-version 36 \
  --java "$OUT/gen" "$OUT/compiled_res.zip"

echo "== javac =="
find "$PROJ/java" "$OUT/gen" -name "*.java" > "$OUT/sources.txt"
"$JAVAC" -encoding UTF-8 --release 17 -cp "$PLATFORM" -d "$OUT/classes" @"$OUT/sources.txt"

echo "== d8 =="
"$BT/d8" --lib "$PLATFORM" --min-api 30 --output "$OUT/dex" \
  $(find "$OUT/classes" -name "*.class")

echo "== assemble base module =="
cd "$OUT"
unzip -q -o proto.apk -d protox
cp protox/AndroidManifest.xml base/manifest/
cp -r protox/res base/
cp protox/resources.pb base/
cp "$OUT/dex/classes.dex" base/dex/
cd base && zip -q -r ../base.zip manifest dex res resources.pb && cd ..

echo "== bundletool build-bundle =="
java -jar "$BUNDLETOOL" build-bundle --modules="$OUT/base.zip" \
  --output="$OUT/app.aab" --overwrite

echo "== jarsigner (v1, upload key) =="
cp "$OUT/app.aab" "$AAB"
jarsigner -keystore "$KEYSTORE" -storepass "$KS_PASS" -keypass "$KS_PASS" \
  "$AAB" "$KS_ALIAS" 2>/dev/null

echo "== validate =="
java -jar "$BUNDLETOOL" validate --bundle="$AAB" > /dev/null
jarsigner -verify "$AAB" | tail -1
java -jar "$BUNDLETOOL" dump manifest --bundle="$AAB" --xpath=/manifest/@versionCode 2>/dev/null
ls -la "$AAB"
echo "TICTACTOE_BUNDLE_DONE"
