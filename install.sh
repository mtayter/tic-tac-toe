#!/bin/bash
# Tic-Tac-Toe (Wear OS) — local installer / first-time setup.
#
# What this does:
#   * Writes local configuration to ~/.config/tictactoe/config.env (mode 0600).
#     That file is gitignored and NEVER committed: it holds the release
#     keystore password.
#   * Generates the release (upload) keystore if it is missing, with a random
#     strong password stored only in that config file. If the keystore
#     already exists it is NEVER regenerated or overwritten.
#   * Generates the debug keystore if it is missing (standard Android debug
#     credentials, documented in README.md).
#   * Verifies the existing release keystore opens with the configured
#     password, so a typo is caught here instead of at bundle time.
#
# Usage:
#   ./install.sh                    # interactive prompts
#   ./install.sh --non-interactive  # read everything from environment
#   ./install.sh --config PATH     # use a different config file
#   ./install.sh --help
#
# Non-interactive environment variables (see README.md for the full table):
#   TICTACTOE_RELEASE_KEYSTORE        path to release.keystore
#   TICTACTOE_RELEASE_KEYSTORE_PASS   release keystore + key password
#   TICTACTOE_RELEASE_KEY_ALIAS       key alias (default: tictactoe)
#   TICTACTOE_KEY_DNAME               distinguished name for a NEW key
#   TICTACTOE_DEBUG_KEYSTORE          path to debug.keystore
#   TICTACTOE_SDK_DIR                 Android SDK directory
#   TICTACTOE_BUNDLETOOL_JAR          path to bundletool.jar
#   TICTACTOE_CONFIG_FILE             config file location (overrides default)
#
# Idempotent: safe to re-run. Existing config values become the defaults,
# existing keystores are verified, never regenerated.
#
# Security: this script never prints a password and never enables shell
# tracing (no `set -x`). Passwords are passed to keytool as arguments,
# exactly as the build scripts already do.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NON_INTERACTIVE=0
CONFIG_FILE="${TICTACTOE_CONFIG_FILE:-$HOME/.config/tictactoe/config.env}"

usage() {
    cat <<'EOF'
Usage:
  ./install.sh                    # interactive prompts
  ./install.sh --non-interactive  # read everything from environment
  ./install.sh --config PATH     # use a different config file
  ./install.sh --help

Non-interactive environment variables (see README.md for the full table):
  TICTACTOE_RELEASE_KEYSTORE        path to release.keystore
  TICTACTOE_RELEASE_KEYSTORE_PASS   release keystore + key password
  TICTACTOE_RELEASE_KEY_ALIAS       key alias (default: tictactoe)
  TICTACTOE_KEY_DNAME               distinguished name for a NEW key
  TICTACTOE_DEBUG_KEYSTORE          path to debug.keystore
  TICTACTOE_SDK_DIR                 Android SDK directory
  TICTACTOE_BUNDLETOOL_JAR          path to bundletool.jar
  TICTACTOE_CONFIG_FILE             config file location (overrides default)

Idempotent: safe to re-run. Existing config values become the defaults,
existing keystores are verified, never regenerated.
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --non-interactive) NON_INTERACTIVE=1; shift ;;
        --config)
            [ $# -ge 2 ] || { echo "error: --config needs a path" >&2; exit 2; }
            CONFIG_FILE="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo "error: unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
done

# --- Defaults (built-in; config file and env vars override) ---
RELEASE_KEYSTORE="$PROJECT_DIR/release.keystore"
RELEASE_ALIAS="tictactoe"
KEY_DNAME="CN=Tic-Tac-Toe Release, O=Tic-Tac-Toe, C=US"
DEBUG_KEYSTORE="$PROJECT_DIR/debug.keystore"
SDK_DIR="$HOME/workspace/tooling/android-sdk"
BUNDLETOOL_JAR="$HOME/workspace/tooling/bundletool.jar"
RELEASE_PASS=""

# --- Snapshot environment overrides BEFORE sourcing the config file ---
# Sourcing the config assigns TICTACTOE_* variables, which would clobber
# same-named environment values. Capture env first so the precedence
# stays: environment > config file > built-in defaults.
ENV_RELEASE_KEYSTORE="${TICTACTOE_RELEASE_KEYSTORE:-}"
ENV_RELEASE_KEY_ALIAS="${TICTACTOE_RELEASE_KEY_ALIAS:-}"
ENV_RELEASE_KEYSTORE_PASS="${TICTACTOE_RELEASE_KEYSTORE_PASS:-}"
ENV_KEY_DNAME="${TICTACTOE_KEY_DNAME:-}"
ENV_DEBUG_KEYSTORE="${TICTACTOE_DEBUG_KEYSTORE:-}"
ENV_SDK_DIR="${TICTACTOE_SDK_DIR:-}"
ENV_BUNDLETOOL_JAR="${TICTACTOE_BUNDLETOOL_JAR:-}"

# --- Existing local config (if any) becomes the defaults ---
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
fi

# --- Apply precedence: environment > config file > built-in defaults ---
RELEASE_KEYSTORE="${ENV_RELEASE_KEYSTORE:-${TICTACTOE_RELEASE_KEYSTORE:-$RELEASE_KEYSTORE}}"
RELEASE_ALIAS="${ENV_RELEASE_KEY_ALIAS:-${TICTACTOE_RELEASE_KEY_ALIAS:-$RELEASE_ALIAS}}"
KEY_DNAME="${ENV_KEY_DNAME:-${TICTACTOE_KEY_DNAME:-$KEY_DNAME}}"
DEBUG_KEYSTORE="${ENV_DEBUG_KEYSTORE:-${TICTACTOE_DEBUG_KEYSTORE:-$DEBUG_KEYSTORE}}"
SDK_DIR="${ENV_SDK_DIR:-${TICTACTOE_SDK_DIR:-$SDK_DIR}}"
BUNDLETOOL_JAR="${ENV_BUNDLETOOL_JAR:-${TICTACTOE_BUNDLETOOL_JAR:-$BUNDLETOOL_JAR}}"
RELEASE_PASS="${ENV_RELEASE_KEYSTORE_PASS:-${TICTACTOE_RELEASE_KEYSTORE_PASS:-}}"

# --- Legacy password file migration ---
# Older setups kept the release password in <project>/.ks-pass. If no
# password is configured yet, adopt that value (read, never printed) so
# the existing keystore keeps working. The installer offers to remove the
# legacy file afterwards; .gitignore covers it either way.
LEGACY_PASS_FILE="$PROJECT_DIR/.ks-pass"
MIGRATED_FROM_LEGACY=0
if [ -z "$RELEASE_PASS" ] && [ -f "$LEGACY_PASS_FILE" ]; then
    RELEASE_PASS="$(head -n 1 "$LEGACY_PASS_FILE" | tr -d '\r\n')"
    MIGRATED_FROM_LEGACY=1
    echo "Note: adopted release password from legacy .ks-pass (will be stored in the 0600 config file)."
fi

prompt_default() { # prompt_default "Prompt text" "default" -> prints value
    local prompt="$1" def="$2" answer=""
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        printf '%s' "$def"
        return 0
    fi
    printf '%s [%s]: ' "$prompt" "$def" >&2
    IFS= read -r answer || true
    if [ -z "$answer" ]; then printf '%s' "$def"; else printf '%s' "$answer"; fi
}

prompt_password() { # prompt_password "existing-or-empty" -> prints password
    local existing="$1" first="" second=""
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        printf '%s' "$existing"
        return 0
    fi
    if [ -n "$existing" ]; then
        printf 'Release keystore password [press Enter to keep existing]: ' >&2
        IFS= read -r -s first || true
        echo >&2
        if [ -z "$first" ]; then printf '%s' "$existing"; return 0; fi
        printf 'Repeat new password: ' >&2
        IFS= read -r -s second || true
        echo >&2
        [ "$first" = "$second" ] || { echo "error: passwords do not match" >&2; exit 1; }
        printf '%s' "$first"
        return 0
    fi
    printf 'Release keystore password (hidden, stored in the 0600 config file): ' >&2
    IFS= read -r -s first || true
    echo >&2
    printf 'Repeat password: ' >&2
    IFS= read -r -s second || true
    echo >&2
    [ -n "$first" ] || { echo "error: password must not be empty" >&2; exit 1; }
    [ "$first" = "$second" ] || { echo "error: passwords do not match" >&2; exit 1; }
    printf '%s' "$first"
}

prompt_password_or_generate() { # empty input means "generate a random one"
    local first="" second=""
    printf 'Release keystore password (hidden; Enter = generate a random one): ' >&2
    IFS= read -r -s first || true
    echo >&2
    if [ -z "$first" ]; then printf ''; return 0; fi
    printf 'Repeat password: ' >&2
    IFS= read -r -s second || true
    echo >&2
    [ "$first" = "$second" ] || { echo "error: passwords do not match" >&2; exit 1; }
    printf '%s' "$first"
}

random_password() {
    # Alphanumeric only, so the value is safe to store and source verbatim.
    # stdout carries ONLY the password. Deliberately no `head -c` in the
    # pipeline: an early pipe close SIGPIPEs the producer and, under
    # `pipefail` + `set -e`, would abort the script. Filter everything,
    # then truncate in shell.
    local raw=""
    if command -v openssl >/dev/null 2>&1; then
        raw="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9')"
    else
        raw="$(head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9')"
    fi
    printf '%s' "${raw:0:32}"
}

# --- Interactive prompts for non-secret settings ---
RELEASE_KEYSTORE="$(prompt_default "Release keystore path" "$RELEASE_KEYSTORE")"
RELEASE_ALIAS="$(prompt_default "Release key alias" "$RELEASE_ALIAS")"
DEBUG_KEYSTORE="$(prompt_default "Debug keystore path" "$DEBUG_KEYSTORE")"
SDK_DIR="$(prompt_default "Android SDK directory" "$SDK_DIR")"
BUNDLETOOL_JAR="$(prompt_default "bundletool.jar path" "$BUNDLETOOL_JAR")"
if [ ! -f "$RELEASE_KEYSTORE" ]; then
    KEY_DNAME="$(prompt_default "Distinguished name for the NEW release key" "$KEY_DNAME")"
fi

# --- Release password ---
if [ -f "$RELEASE_KEYSTORE" ]; then
    # Keystore exists: a password is mandatory so we can verify it.
    if [ -z "$RELEASE_PASS" ]; then
        if [ "$NON_INTERACTIVE" -eq 1 ]; then
            echo "error: release keystore exists but no password is configured." >&2
            echo "Set TICTACTOE_RELEASE_KEYSTORE_PASS or run interactively." >&2
            exit 1
        fi
        RELEASE_PASS="$(prompt_password "")"
    fi
else
    # No keystore yet: generate a password unless one was supplied.
    if [ -z "$RELEASE_PASS" ]; then
        if [ "$NON_INTERACTIVE" -eq 1 ]; then
            echo "No release keystore found; generating a random password." >&2
            RELEASE_PASS="$(random_password)"
        else
            echo "No release keystore found. Press Enter for a generated random password, or type one." >&2
            RELEASE_PASS="$(prompt_password_or_generate)"
            if [ -z "$RELEASE_PASS" ]; then
                RELEASE_PASS="$(random_password)"
                echo "Generated a random password (stored in the config file)." >&2
            fi
        fi
    fi
fi

# --- Tool checks (warnings only; the build scripts fail later if missing) ---
KEYTOOL=""
if command -v keytool >/dev/null 2>&1; then
    KEYTOOL="keytool"
else
    for candidate in "$HOME"/workspace/tooling/jdk/jdk-*/bin/keytool /usr/lib/jvm/*/bin/keytool; do
        if [ -x "$candidate" ]; then KEYTOOL="$candidate"; break; fi
    done
fi
[ -n "$KEYTOOL" ] || { echo "error: keytool not found (need a JDK on PATH or under ~/workspace/tooling/jdk/)" >&2; exit 1; }
[ -d "$SDK_DIR" ] || echo "warning: SDK directory not found: $SDK_DIR" >&2
[ -f "$BUNDLETOOL_JAR" ] || echo "warning: bundletool.jar not found: $BUNDLETOOL_JAR (needed only for the Play AAB build)" >&2

# --- Release keystore: verify existing, or generate once ---
if [ -f "$RELEASE_KEYSTORE" ]; then
    if ! "$KEYTOOL" -list -keystore "$RELEASE_KEYSTORE" -storepass "$RELEASE_PASS" >/dev/null 2>&1; then
        echo "error: release keystore exists but the configured password does not open it." >&2
        echo "Fix the password in $CONFIG_FILE (or via TICTACTOE_RELEASE_KEYSTORE_PASS)." >&2
        echo "The keystore was NOT modified." >&2
        exit 1
    fi
    echo "Release keystore exists and opens with the configured password: $RELEASE_KEYSTORE"
else
    echo "Generating release keystore (RSA-2048, 30-year validity): $RELEASE_KEYSTORE"
    "$KEYTOOL" -genkeypair -keystore "$RELEASE_KEYSTORE" -alias "$RELEASE_ALIAS" \
        -storepass "$RELEASE_PASS" -keypass "$RELEASE_PASS" \
        -keyalg RSA -keysize 2048 -validity 10950 -dname "$KEY_DNAME" 2>/dev/null
    echo "Release keystore created. BACK IT UP: it is the permanent upload key for Play App Signing."
fi

# --- Debug keystore: generate once with the standard Android debug values ---
if [ -f "$DEBUG_KEYSTORE" ]; then
    echo "Debug keystore already exists: $DEBUG_KEYSTORE"
else
    echo "Generating debug keystore: $DEBUG_KEYSTORE"
    "$KEYTOOL" -genkeypair -keystore "$DEBUG_KEYSTORE" -alias androiddebugkey \
        -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10950 \
        -dname "CN=Android Debug,O=Android,C=US" 2>/dev/null
fi

# --- Write config (atomic, mode 0600) ---
mkdir -p "$(dirname "$CONFIG_FILE")"
TMP_CONFIG="$CONFIG_FILE.tmp.$$"
umask 077
{
    printf '# Tic-Tac-Toe local config — GENERATED by ./install.sh. DO NOT COMMIT.\n'
    printf '# Permissions must stay 0600. Re-run ./install.sh to change values.\n'
    printf 'TICTACTOE_RELEASE_KEYSTORE=%q\n' "$RELEASE_KEYSTORE"
    printf 'TICTACTOE_RELEASE_KEY_ALIAS=%q\n' "$RELEASE_ALIAS"
    printf 'TICTACTOE_RELEASE_KEYSTORE_PASS=%q\n' "$RELEASE_PASS"
    printf 'TICTACTOE_DEBUG_KEYSTORE=%q\n' "$DEBUG_KEYSTORE"
    printf 'TICTACTOE_SDK_DIR=%q\n' "$SDK_DIR"
    printf 'TICTACTOE_BUNDLETOOL_JAR=%q\n' "$BUNDLETOOL_JAR"
} > "$TMP_CONFIG"
chmod 600 "$TMP_CONFIG"
mv "$TMP_CONFIG" "$CONFIG_FILE"
echo "Config written (0600): $CONFIG_FILE"

# --- Legacy cleanup offer ---
if [ "$MIGRATED_FROM_LEGACY" -eq 1 ] && [ -f "$LEGACY_PASS_FILE" ]; then
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        echo "warning: legacy password file still exists: $LEGACY_PASS_FILE (covered by .gitignore; delete it once you have verified the new config)." >&2
    else
        printf 'Password migrated to the config file. Delete the legacy %s? [y/N]: ' "$LEGACY_PASS_FILE" >&2
        IFS= read -r answer || true
        case "$answer" in
            y|Y|yes|YES) rm -f "$LEGACY_PASS_FILE"; echo "Deleted $LEGACY_PASS_FILE." ;;
            *) echo "Left $LEGACY_PASS_FILE in place (covered by .gitignore)." ;;
        esac
    fi
fi

echo "Install complete. Next: ./build.sh (debug APK) or ./build-bundle.sh (Play AAB)."
