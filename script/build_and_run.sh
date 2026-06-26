#!/usr/bin/env bash
set -euo pipefail

PRODUCT_NAME="Catch"
APP_NAME="Catch"
BUNDLE_ID="xyz.block.catch"
MIN_SYSTEM_VERSION="26.0"
MODE="run"
TEST_INSTANCE_ID_RAW="${CATCH_TEST_INSTANCE_ID:-}"
TEST_INSTANCE_ID_ARG_PROVIDED=0
PRINT_CONFIG="${CATCH_BUILD_AND_RUN_DRY_RUN:-0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$HOME/Applications"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
LSUIELEMENT_PLIST='
  <key>LSUIElement</key>
  <true/>'
TEST_ENV_PLIST=""
TEST_INSTANCE_ID=""
APP_ARGS=()

usage() {
  cat >&2 <<'USAGE'
usage: build_and_run.sh [run|--test|--test-manual|--embedded|--debug|--logs|--telemetry|--verify] [--test-instance-id <id>]

Environment:
  CATCH_TEST_INSTANCE_ID   Isolates test builds as CatchTest-<id>.
  CATCH_TEST_BUILD_LABEL   Sets the orange test-build banner label.
  CATCH_GLOBAL_HOTKEY      Required for --test-manual, forwarded as --global-hotkey.
  CATCH_START_HIDDEN=1     Starts embedded launches hidden.
USAGE
}

is_test_mode() {
  case "$MODE" in
    --test|test|--test-manual|test-manual)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_manual_test_mode() {
  case "$MODE" in
    --test-manual|test-manual)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_embedded_mode() {
  case "$MODE" in
    --embedded|embedded)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

sanitize_test_instance_id() {
  local raw="$1"
  local sanitized
  sanitized="$(printf '%s' "$raw" | LC_ALL=C tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$sanitized" ]]; then
    echo "error: CATCH_TEST_INSTANCE_ID must contain at least one ASCII letter or number after sanitization" >&2
    exit 2
  fi
  printf '%s' "$sanitized"
}

set_app_paths() {
  APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
  APP_CONTENTS="$APP_BUNDLE/Contents"
  APP_MACOS="$APP_CONTENTS/MacOS"
  APP_BINARY="$APP_MACOS/$APP_NAME"
  INFO_PLIST="$APP_CONTENTS/Info.plist"
}

while (($# > 0)); do
  case "$1" in
    run|--test|test|--test-manual|test-manual|--embedded|embedded|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
      MODE="$1"
      shift
      ;;
    --test-instance-id)
      if (($# < 2)); then
        echo "error: --test-instance-id requires a value" >&2
        usage
        exit 2
      fi
      TEST_INSTANCE_ID_RAW="$2"
      TEST_INSTANCE_ID_ARG_PROVIDED=1
      shift 2
      ;;
    --test-instance-id=*)
      TEST_INSTANCE_ID_RAW="${1#*=}"
      TEST_INSTANCE_ID_ARG_PROVIDED=1
      shift
      ;;
    --print-config)
      PRINT_CONFIG=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

if ((TEST_INSTANCE_ID_ARG_PROVIDED)) && ! is_test_mode; then
  echo "error: --test-instance-id is only valid with --test or --test-manual" >&2
  exit 2
fi

if is_test_mode; then
  if [[ -n "$TEST_INSTANCE_ID_RAW" ]]; then
    TEST_INSTANCE_ID="$(sanitize_test_instance_id "$TEST_INSTANCE_ID_RAW")"
    APP_NAME="CatchTest-$TEST_INSTANCE_ID"
    BUNDLE_ID="xyz.block.catch.test.$TEST_INSTANCE_ID"
  else
    APP_NAME="CatchTest"
    BUNDLE_ID="xyz.block.catch.test"
  fi
  set_app_paths

  TEST_ENV_PLIST='
  <key>LSEnvironment</key>
  <dict>
    <key>CATCH_TEST_BUILD</key>
    <string>1</string>'

  if [[ -n "$TEST_INSTANCE_ID" ]]; then
    TEST_ENV_PLIST="$TEST_ENV_PLIST
    <key>CATCH_TEST_INSTANCE_ID</key>
    <string>$TEST_INSTANCE_ID</string>"
    APP_ARGS+=(--test-instance-id "$TEST_INSTANCE_ID")
  fi

  TEST_ENV_PLIST="$TEST_ENV_PLIST
  </dict>"

  if is_manual_test_mode; then
    if [[ -z "${CATCH_GLOBAL_HOTKEY:-}" ]]; then
      echo "error: --test-manual requires CATCH_GLOBAL_HOTKEY with a shortcut unique to this test instance" >&2
      exit 2
    fi
    NORMALIZED_TEST_HOTKEY="$(printf '%s' "$CATCH_GLOBAL_HOTKEY" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    if [[ "$NORMALIZED_TEST_HOTKEY" == "alt+space" ]]; then
      echo "error: --test-manual must not use alt+space; choose a unique Cmd-Ctrl shortcut" >&2
      exit 2
    fi
    APP_ARGS+=(--manual-test-window)
  fi

  if [[ -n "${CATCH_TEST_BUILD_LABEL:-}" ]]; then
    APP_ARGS+=(--test-build-label "$CATCH_TEST_BUILD_LABEL")
  fi

  if is_manual_test_mode; then
    APP_ARGS+=(--global-hotkey "$CATCH_GLOBAL_HOTKEY")
  fi
fi

if is_embedded_mode; then
  APP_ARGS=(--embedded)
  if [[ -n "${CATCH_GLOBAL_HOTKEY:-}" ]]; then
    APP_ARGS+=(--global-hotkey "$CATCH_GLOBAL_HOTKEY")
  fi
  if [[ "${CATCH_START_HIDDEN:-}" == "1" ]]; then
    APP_ARGS+=(--start-hidden)
  fi
fi

print_config() {
  printf 'MODE=%s\n' "$MODE"
  printf 'APP_NAME=%s\n' "$APP_NAME"
  printf 'BUNDLE_ID=%s\n' "$BUNDLE_ID"
  printf 'APP_BUNDLE=%s\n' "$APP_BUNDLE"
  printf 'APP_BINARY=%s\n' "$APP_BINARY"
  printf 'TEST_INSTANCE_ID=%s\n' "$TEST_INSTANCE_ID"
  if ((${#APP_ARGS[@]} > 0)); then
    for arg in "${APP_ARGS[@]}"; do
      printf 'APP_ARG=%s\n' "$arg"
    done
  fi
}

stop_existing_app() {
  local escaped_binary
  local pids

  escaped_binary="$(printf '%s' "$APP_BINARY" | sed 's/[][(){}.^$*+?|\\]/\\&/g')"
  pids="$(/usr/bin/pgrep -f "^${escaped_binary}($|[[:space:]])" || true)"
  if [[ -n "$pids" ]]; then
    /bin/kill $pids >/dev/null 2>&1 || true
    sleep 0.5
    pids="$(/usr/bin/pgrep -f "^${escaped_binary}($|[[:space:]])" || true)"
    if [[ -n "$pids" ]]; then
      /bin/kill -9 $pids >/dev/null 2>&1 || true
    fi
    return
  fi

  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

process_is_running() {
  local escaped_binary
  escaped_binary="$(printf '%s' "$APP_BINARY" | sed 's/[][(){}.^$*+?|\\]/\\&/g')"
  /usr/bin/pgrep -f "^${escaped_binary}($|[[:space:]])" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1
}

if [[ "$PRINT_CONFIG" == "1" ]]; then
  print_config
  exit 0
fi

stop_existing_app

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
$LSUIELEMENT_PLIST
$TEST_ENV_PLIST
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null

open_app() {
  if ((${#APP_ARGS[@]} > 0)); then
    /usr/bin/open -n "$APP_BUNDLE" --args "${APP_ARGS[@]}"
  else
    /usr/bin/open -n "$APP_BUNDLE"
  fi
}

case "$MODE" in
  run|--test|test|--test-manual|test-manual|--embedded|embedded)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    process_is_running
    ;;
  *)
    usage
    exit 2
    ;;
esac
