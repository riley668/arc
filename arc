#!/usr/bin/env bash
# arc — one CLI for the Workspace tooling that used to be scattered scripts.
#
# Subcommands:
#   arc img compress <path> [target_kb] [formats...]
#   arc img strip    <path> [outdir]
#   arc vid compress <path> [crf]
#   arc seal dir     <folder> [--keep]
#   arc seal files   <path> [--keep]
#   arc unseal       [folder] [--key <file>] [--to <dir>]
#   arc keys         [list|rm <file>]
#
# Every subcommand supports --help.

set -uo pipefail

ARC_SELF="${BASH_SOURCE[0]}"
# Resolve symlinks so `arc` installed into ~/.local/bin still finds
# its arc-lib/ next to the real script in the repo.
ARC_REAL="$(readlink -f "$ARC_SELF" 2>/dev/null || printf '%s' "$ARC_SELF")"
ARC_LIB_DIR="$(cd "$(dirname "$ARC_REAL")" && pwd)/arc-lib"

# Workspace roots used by the original scripts. Kept for familiarity.
WS="${ARC_WORKSPACE:-$HOME/Workspace}"
WS_KEYS="$WS/keys"
WS_ENCRYPTED="$WS/encrypted"
WS_ARCHIVES="$WS/archives"
WS_DECRYPTED="$WS/decrypted"
WS_CLEANED="$WS/cleaned"

die()  { printf 'arc: %s\n' "$*" >&2; exit 1; }
warn() { printf 'arc: warning: %s\n' "$*" >&2; }
say()  { printf '%s\n' "$*"; }

need() {
    command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

# human-readable byte size
human() {
    local bytes="${1:-0}"
    awk -v b="$bytes" 'BEGIN{
        split("B KB MB GB TB", u, " ");
        i=1;
        while (b >= 1024 && i < 5) { b/=1024; i++ }
        printf (i==1 ? "%d%s" : "%.1f%s"), b, u[i]
    }'
}

usage() {
    cat <<'EOF'
arc — Workspace toolbox

Usage: arc <group> <command> [args...]

Image
  arc img compress <path> [target_kb] [formats...]   shrink images to a size
  arc img strip    <path> [outdir]                   strip metadata

Video
  arc vid compress <path> [crf]                      re-encode smaller

Sealing (symmetric encryption, gpg AES256 + random key)
  arc seal dir   <folder> [--keep]    zip + encrypt a folder
  arc seal files <path>   [--keep]    encrypt files in place
  arc unseal     [folder] [--key <file>] [--to <dir>]
  arc keys       [list | rm <file>]

Notes
  Sealed artefacts land in $WS/archives (dirs) or $WS/encrypted (files).
  Keys land in $WS/keys/. Files are only removed after a successful seal
  unless --keep is given.

Run 'arc <group> <command> --help' for details on any command.

Guided mode
  arc                 open the interactive menu
  arc menu            same thing explicitly
  arc doctor          check that required external tools are installed
EOF
}

# Report which external tools arc shells out to, and how to install them.
doctor() {
    local -a req=(magick ffmpeg ffprobe gpg zip unzip)
    local -a opt=(pngquant exiftool)
    local missing=() t
    say "arc doctor — external tools"
    for t in "${req[@]}"; do
        if command -v "$t" >/dev/null 2>&1; then
            printf '  ok       %-10s %s\n' "$t" "$(command -v "$t")"
        else
            printf '  MISSING  %-10s\n' "$t"
            missing+=("$t")
        fi
    done
    for t in "${opt[@]}"; do
        if command -v "$t" >/dev/null 2>&1; then
            printf '  ok       %-10s (optional) %s\n' "$t" "$(command -v "$t")"
        else
            printf '  absent   %-10s (optional)\n' "$t"
        fi
    done
    if (( ${#missing[@]} )); then
        # ffprobe ships with ffmpeg; magick is the ImageMagick package.
        local -a pkgs=()
        for t in "${missing[@]}"; do
            case "$t" in
                magick) pkgs+=(ImageMagick) ;;
                ffprobe) ;;  # covered by ffmpeg
                *) pkgs+=("$t") ;;
            esac
        done
        say ""
        say "Install the missing tools:"
        say "  Fedora:  sudo dnf install ${pkgs[*]}"
        say "  Debian:  sudo apt install ${pkgs[*]}"
        return 1
    fi
    say ""
    say "all required tools present"
    return 0
}

# ---- dispatch ---------------------------------------------------------
main() {
    local group="${1:-}" cmd="${2:-}"

    # Bare `arc` opens the guided menu (needs a terminal).
    if [[ -z "$group" ]]; then
        if [[ -t 0 && -t 1 ]]; then
            . "$ARC_LIB_DIR/menu.sh"
            menu_main
            return 0
        fi
        usage
        exit 0
    fi

    case "$group" in
        -h|--help|help) usage; exit 0 ;;
        menu) . "$ARC_LIB_DIR/menu.sh"; menu_main; return 0 ;;
    esac

    shift || true
    case "$group" in
        img)
            cmd="${1:-}"; shift || true
            case "$cmd" in
                compress) . "$ARC_LIB_DIR/img.sh"; img_compress "$@" ;;
                strip)    . "$ARC_LIB_DIR/strip.sh"; img_strip "$@" ;;
                -h|--help|"") . "$ARC_LIB_DIR/img.sh"; img_usage; exit 0 ;;
                *) die "unknown img command: $cmd (try: arc img --help)" ;;
            esac
            ;;
        vid|video)
            cmd="${1:-}"; shift || true
            case "$cmd" in
                compress) . "$ARC_LIB_DIR/vid.sh"; vid_compress "$@" ;;
                -h|--help|"") . "$ARC_LIB_DIR/vid.sh"; vid_usage; exit 0 ;;
                *) die "unknown vid command: $cmd" ;;
            esac
            ;;
        seal)
            cmd="${1:-}"; shift || true
            . "$ARC_LIB_DIR/seal.sh"
            case "$cmd" in
                dir)   seal_dir "$@" ;;
                files) seal_files "$@" ;;
                -h|--help|"") seal_usage; exit 0 ;;
                *) die "unknown seal command: $cmd (try: seal dir | seal files)" ;;
            esac
            ;;
        unseal)
            . "$ARC_LIB_DIR/seal.sh"
            # 'unseal --help' reaches here with $1 == --help
            unseal "$@" ;;
        keys)
            . "$ARC_LIB_DIR/seal.sh"
            keys "$@" ;;
        doctor)
            doctor ;;
        *)
            die "unknown group: $group (try: arc --help)"
            ;;
    esac
}

main "$@"
