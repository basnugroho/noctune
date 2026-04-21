#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
ELECTRON_PACKAGE_JSON="$PROJECT_ROOT/electron/package.json"

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

: "${REMOTE_PC_ADDR:?REMOTE_PC_ADDR is required}"
: "${REMOTE_PC_USERNAME:?REMOTE_PC_USERNAME is required}"
: "${PASSWORD_REMOTE_PC:?PASSWORD_REMOTE_PC is required}"

REMOTE_BASE_DIR="${REMOTE_PC_BASE_DIR:-C:\Users\Administrator\projects\noctune}"
MAX_RETRIES="${UPLOAD_MAX_RETRIES:-3}"
SSH_COMMON_OPTS=(
    -q
    -o LogLevel=ERROR
    -o PreferredAuthentications=password
    -o PubkeyAuthentication=no
    -o ConnectTimeout=10
    -o ServerAliveInterval=5
    -o ServerAliveCountMax=2
)
ELECTRON_VERSION="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$ELECTRON_PACKAGE_JSON" | head -n 1)"

usage() {
    cat <<'EOF'
Usage: tools/upload_remote_artifacts.sh [platform...]

Platforms:
  mac        Upload macOS DMG artifacts
  windows    Upload Windows installer artifacts
  linux      Upload Linux artifacts
  android    Upload Android APK/AAB artifacts
  all        Upload every available artifact (default)

Examples:
  tools/upload_remote_artifacts.sh mac
  tools/upload_remote_artifacts.sh mac windows linux android
EOF
}

log() {
    printf '%s\n' "$*"
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

trim_quotes() {
    local value="$1"
    value="${value#\"}"
    value="${value%\"}"
    printf '%s' "$value"
}

REMOTE_PC_USERNAME="$(trim_quotes "$REMOTE_PC_USERNAME")"
PASSWORD_REMOTE_PC="$(trim_quotes "$PASSWORD_REMOTE_PC")"

run_expect_command() {
    local mode="$1"
    shift

    EXPECT_PASSWORD="$PASSWORD_REMOTE_PC" expect -f - "$mode" "$@" <<'EOF'
log_user 0
set timeout 900
set mode [lindex $argv 0]
set cmd [lrange $argv 1 end]
set password $env(EXPECT_PASSWORD)
set prompt_re {(?i)(password|passphrase).*: *$}

if {$mode eq "ssh"} {
    eval spawn ssh $cmd
} elseif {$mode eq "scp"} {
    eval spawn scp $cmd
} else {
    puts stderr "unsupported mode: $mode"
    exit 2
}

expect {
    -re $prompt_re {
        send -- "$password\r"
        exp_continue
    }
    eof
}

catch wait result
set exit_status [lindex $result 3]
if {$exit_status eq ""} {
    set exit_status 1
}
exit $exit_status
EOF
}

retry_command() {
    local description="$1"
    shift
    local attempt=1

    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        log "[$attempt/$MAX_RETRIES] $description"
        if "$@"; then
            return 0
        fi
        attempt=$((attempt + 1))
    done

    return 1
}

ssh_remote() {
    run_expect_command ssh \
        "${SSH_COMMON_OPTS[@]}" \
        "$REMOTE_PC_USERNAME@$REMOTE_PC_ADDR" \
        "$@"
}

scp_remote() {
    local local_file="$1"
    local remote_dir="$2"

    run_expect_command scp \
        "${SSH_COMMON_OPTS[@]}" \
        "$local_file" \
        "$REMOTE_PC_USERNAME@$REMOTE_PC_ADDR:$remote_dir/"
}

ensure_remote_dir() {
    local remote_dir="$1"

    retry_command "create remote directory $remote_dir" \
        ssh_remote \
        "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '$remote_dir' | Out-Null\""
}

upload_file() {
    local local_file="$1"
    local remote_dir="$2"

    retry_command "upload $(basename "$local_file")" scp_remote "$local_file" "$remote_dir"
}

artifact_is_valid() {
    local file_path="$1"

    [ -f "$file_path" ] || return 1

    local size
    size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || printf '0')

    case "$file_path" in
        *.deb)
            [ "$size" -gt 10240 ] || return 1
            ;;
        *.blockmap)
            return 1
            ;;
        *)
            [ "$size" -gt 1024 ] || return 1
            ;;
    esac

    return 0
}

append_if_valid() {
    local array_name="$1"
    local candidate="$2"

    if artifact_is_valid "$candidate" && artifact_matches_current_release "$candidate"; then
        eval "$array_name+=(\"$candidate\")"
    fi
}

artifact_matches_current_release() {
    local file_path="$1"

    case "$file_path" in
        "$PROJECT_ROOT/electron/dist"/*)
            [ -n "$ELECTRON_VERSION" ] || return 0
            [[ "$(basename "$file_path")" == *"$ELECTRON_VERSION"* ]]
            ;;
        *)
            return 0
            ;;
    esac
}

collect_mac_artifacts() {
    local -a files=()

    local candidate
    while IFS= read -r -d '' candidate; do
        append_if_valid files "$candidate"
    done < <(find "$PROJECT_ROOT/electron/dist" -maxdepth 1 -type f -name 'NOC-Tune-*-mac-*.dmg' -print0 2>/dev/null)

    printf '%s\n' "${files[@]}" | sort
}

collect_windows_artifacts() {
    local -a files=()

    local candidate
    while IFS= read -r -d '' candidate; do
        append_if_valid files "$candidate"
    done < <(find "$PROJECT_ROOT/electron/dist" -maxdepth 1 -type f \( -name '*.exe' -o -name '*.msi' -o -name '*.zip' \) -print0 2>/dev/null)

    printf '%s\n' "${files[@]}" | sort
}

collect_linux_artifacts() {
    local -a files=()

    local candidate
    while IFS= read -r -d '' candidate; do
        append_if_valid files "$candidate"
    done < <(find "$PROJECT_ROOT/electron/dist" -maxdepth 1 -type f \( -name '*.AppImage' -o -name '*.deb' -o -name '*.rpm' -o -name '*.tar.gz' \) -print0 2>/dev/null)

    printf '%s\n' "${files[@]}" | sort
}

collect_android_artifacts() {
    local -a files=()

    append_if_valid files "$PROJECT_ROOT/noc_tune.apk"

    local candidate
    while IFS= read -r -d '' candidate; do
        append_if_valid files "$candidate"
    done < <(find "$PROJECT_ROOT/mobile/build" -type f \( -name '*.apk' -o -name '*.aab' \) -print0 2>/dev/null)

    printf '%s\n' "${files[@]}" | sort
}

collect_artifacts() {
    local platform="$1"

    case "$platform" in
        mac)
            collect_mac_artifacts
            ;;
        windows)
            collect_windows_artifacts
            ;;
        linux)
            collect_linux_artifacts
            ;;
        android)
            collect_android_artifacts
            ;;
        *)
            fail "Unknown platform collector: $platform"
            ;;
    esac
}

read_artifact_list() {
    local platform="$1"

    mapfile_output=()
    while IFS= read -r line; do
        [ -n "$line" ] && mapfile_output+=("$line")
    done < <(collect_artifacts "$platform")
}

upload_platform_group() {
    local label="$1"
    local remote_dir="$2"
    shift 2
    local files=("$@")

    if [ "${#files[@]}" -eq 0 ]; then
        log "No valid $label artifacts found."
        return 0
    fi

    ensure_remote_dir "$remote_dir"

    local file_path
    for file_path in "${files[@]}"; do
        upload_file "$file_path" "$remote_dir"
    done
}

requested_platforms=("$@")
if [ "${#requested_platforms[@]}" -eq 0 ]; then
    requested_platforms=(all)
fi

for platform in "${requested_platforms[@]}"; do
    case "$platform" in
        all|mac|windows|linux|android)
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown platform: $platform"
            ;;
    esac
done

declare_all=false
for platform in "${requested_platforms[@]}"; do
    if [ "$platform" = "all" ]; then
        declare_all=true
        break
    fi
done

should_upload() {
    local name="$1"
    if [ "$declare_all" = true ]; then
        return 0
    fi

    local platform
    for platform in "${requested_platforms[@]}"; do
        if [ "$platform" = "$name" ]; then
            return 0
        fi
    done

    return 1
}

if should_upload mac; then
    read_artifact_list mac mapfile_output
    upload_platform_group "macOS" "$REMOTE_BASE_DIR\\electron\\dist" "${mapfile_output[@]}"
fi

if should_upload windows; then
    read_artifact_list windows mapfile_output
    upload_platform_group "Windows" "$REMOTE_BASE_DIR\\electron\\dist" "${mapfile_output[@]}"
fi

if should_upload linux; then
    read_artifact_list linux mapfile_output
    upload_platform_group "Linux" "$REMOTE_BASE_DIR\\electron\\dist" "${mapfile_output[@]}"
fi

if should_upload android; then
    read_artifact_list android mapfile_output
    upload_platform_group "Android" "$REMOTE_BASE_DIR\\mobile\\build\\android" "${mapfile_output[@]}"
fi

log "Upload routine finished."