# Tic-Tac-Toe (Wear OS)

Classic tic-tac-toe for your Wear OS watch. Two players, pass and play:
red **X** moves first, blue **O** second. Tap a square to place your mark;
a win draws a line through it in the winner's color. One-tap **New Game**
button, no menus, no settings.

Works fully offline. No accounts, no ads, no permissions — not even
internet access. Game state lives only in memory while you play; nothing
is saved or transmitted. See `privacy-policy.html` for the full policy.

- Package: `com.tayter.tictactoe`
- `minSdk 30` (Wear OS 3+), `targetSdk 36`
- Two-player local game only; no single-player / AI opponent
- Built manually with `aapt2` + `javac` + `d8` — **no Gradle**

## Repository layout

| Path | What it is |
| --- | --- |
| `AndroidManifest.xml` | App manifest (package, version, watch feature) |
| `java/com/tayter/tictactoe/` | `MainActivity.java`, `BoardView.java` (game + rendering) |
| `res/` | Layout + strings |
| `build.sh` | Builds the debug APK (`TicTacToe.apk`) |
| `build-bundle.sh` | Builds the signed Play AAB (`TicTacToe.aab`) |
| `install.sh` | First-time setup: config + keystores (run this first) |
| `privacy-policy.html` | Privacy policy served with the store listing |
| `app-icon-512.png`, `feature-graphic.png`, `play-*.png` | Store listing graphics / screenshots |

## Prerequisites

- JDK 17 (`javac`, `keytool`, `jarsigner` on `PATH`)
- Android SDK with:
  - `build-tools/34.0.0` + `platforms/android-34` (debug APK build)
  - `build-tools/36.1.0` + `platforms/android-36` (Play AAB build)
- `bundletool.jar` (only for the Play AAB build)
- `adb` (only for installing onto a watch)

The build scripts default to the SDK under `~/workspace/tooling/android-sdk`
and `bundletool.jar` under `~/workspace/tooling/`; `install.sh` lets you
point them elsewhere and saves your choice.

## Install

Run the installer first. It writes local configuration to
`~/.config/tictactoe/config.env` (mode `0600`, gitignored — never
committed) and sets up signing keys. It is idempotent: re-running it
verifies what exists and never regenerates a keystore.

```sh
./install.sh
```

Interactive prompts:

1. **Release keystore path** (default: `release.keystore` in this directory)
2. **Release key alias** (default: `tictactoe`)
3. **Debug keystore path** (default: `debug.keystore` in this directory)
4. **Android SDK directory**
5. **bundletool.jar path**
6. **Release keystore password** (hidden input):
   - If the keystore already exists, enter the password that opens it.
     Pressing Enter keeps the password already in the config file.
   - If the keystore does not exist yet, press Enter for a generated
     random password, or type your own (entered twice to confirm).

If a legacy `.ks-pass` password file exists in the project directory and
no password is configured yet, the installer adopts it (read, never
printed) into the config file and offers to delete the legacy file.

### Non-interactive install

```sh
./install.sh --non-interactive
```

Reads everything from environment variables. Precedence:
environment > existing config file > built-in defaults.

| Variable | Purpose | Default |
| --- | --- | --- |
| `TICTACTOE_RELEASE_KEYSTORE` | Release (upload) keystore path | `<project>/release.keystore` |
| `TICTACTOE_RELEASE_KEYSTORE_PASS` | Release keystore + key password | *(none — generated if the keystore is missing; required if it exists)* |
| `TICTACTOE_RELEASE_KEY_ALIAS` | Key alias | `tictactoe` |
| `TICTACTOE_KEY_DNAME` | Distinguished name for a **new** key | `CN=Tic-Tac-Toe Release, O=Tic-Tac-Toe, C=US` |
| `TICTACTOE_DEBUG_KEYSTORE` | Debug keystore path | `<project>/debug.keystore` |
| `TICTACTOE_SDK_DIR` | Android SDK directory | `~/workspace/tooling/android-sdk` |
| `TICTACTOE_BUNDLETOOL_JAR` | `bundletool.jar` path | `~/workspace/tooling/bundletool.jar` |
| `TICTACTOE_CONFIG_FILE` | Config file location | `~/.config/tictactoe/config.env` |

`./install.sh --config PATH` uses a different config file.
`./install.sh --help` prints usage.

## Build

```sh
./build.sh          # debug APK  -> TicTacToe.apk (debug key)
./build-bundle.sh   # Play AAB  -> TicTacToe.aab (release/upload key)
```

Both scripts read the config file written by `install.sh` (or
`TICTACTOE_CONFIG_FILE` if set) for the SDK, bundletool, keystore, alias,
and release password. If no config file exists, `build-bundle.sh` falls
back to the legacy `.ks-pass` file for the release password; run
`./install.sh` to migrate to the config file.

## Install on a watch

```sh
adb connect <watch-ip>:<port>   # wireless debugging; see your watch settings
adb install -r TicTacToe.apk
```

The sideloaded APK is signed with the debug key. A Play Store build is
re-signed by Play App Signing, so it will **not** update over a sideloaded
copy — uninstall the sideloaded app first.

## Signing — read before you touch this

- The **release keystore** is the permanent **upload key** for Google Play
  App Signing. **Back it up somewhere safe, offline.** If it is lost, you
  cannot publish updates signed with the same upload key.
- The installer **never regenerates an existing keystore**. If the
  configured password does not open the existing keystore, the installer
  stops and changes nothing — fix the password, do not delete the keystore.
- The **debug keystore** uses the standard Android debug credentials
  (well-known public values, alias `androiddebugkey`). It is only for
  local sideloading; it must never be used for a store build.
- Passwords are passed to `keytool` / `jarsigner` as command-line
  arguments, as the build scripts already do. The installer never prints
  a password and never enables shell tracing around secret handling.

## Configuration collected

`install.sh` collects and stores only:

| Value | Stored where | Secret? |
| --- | --- | --- |
| Release keystore path + alias | `~/.config/tictactoe/config.env` | No |
| Release keystore password | Same config file | **Yes** — `0600`, never committed |
| Debug keystore path | Same config file | No (standard debug values) |
| Android SDK directory | Same config file | No |
| bundletool.jar path | Same config file | No |

No hostname, email, username, token, or API key is collected or needed.
The app itself has no server side and no accounts.

## Privacy

Zero permissions, zero data collection. See `privacy-policy.html`.
When publishing the store listing, fill in the contact address in the
privacy policy with the address you want made public.

## Publishing checklist

1. License: MIT — see [LICENSE](LICENSE).
2. Confirm the contact address in `privacy-policy.html` is one you are
   happy to publish.
3. Keep Play Console notes (listing copy, screenshots, release notes)
   out of the repo — they contain account-specific material.
4. Back up `release.keystore` + the config password offline before the
   first Play upload.

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE).
