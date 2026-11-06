# arc-lib/menu.sh — interactive, guided menus
# Sourced by `arc` when it is run with no arguments (or an unknown group).
# Style follows ~/.aliases/touch_gpt: colored banner, numbered choices,
# a pause between steps, and a loop back to the menu on bad input.

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
DIM='\033[2m'
NC='\033[0m'

_menu_banner() {
    clear 2>/dev/null || printf '\033[H\033[2J'
    printf '%b\n' "${CYAN}                               ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf '%b\n' "${MAGENTA}                                    ⚡  A R C  ⚡${NC}"
    printf '%b\n' "${CYAN}                               ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    [[ -n "${1:-}" ]] && printf '%b\n' "  ${DIM}$1${NC}"
    printf '\n'
}

_menu_pause() {
    printf '\n'
    read -r -p "Press Enter to continue..." _
}

# Ask for a path with a default. Echoes the answer.
_menu_ask_path() {
    local prompt="$1" default="${2:-}"
    local answer
    if [[ -n "$default" ]]; then
        printf '%b\n' "${YELLOW}${prompt}${NC} ${DIM}[${default}]${NC}" >&2
    else
        printf '%b\n' "${YELLOW}${prompt}${NC}" >&2
    fi
    read -r -p "> " answer
    answer="${answer:-$default}"
    # expand leading ~
    [[ "$answer" == "~" ]] && answer="$HOME"
    [[ "$answer" == "~/"* ]] && answer="$HOME/${answer#~/}"
    printf '%s\n' "$answer"
}

# Ask a numbered question. Sets REPLY_CHOICE and echoes the chosen number.
_menu_ask_choice() {
    local prompt="$1"; shift
    local -a opts=("$@")
    local i answer
    REPLY_CHOICE=""
    printf '%b\n' "${BLUE}${prompt}${NC}" >&2
    for i in "${!opts[@]}"; do
        printf '  %d) %s\n' "$(( i + 1 ))" "${opts[$i]}" >&2
    done
    printf '\n' >&2
    read -r -p "Choice [1]: " answer
    answer="${answer:-1}"
    if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#opts[@]} )); then
        REPLY_CHOICE="$answer"
        printf '%s\n' "$answer"
        return 0
    fi
    return 1
}

_menu_yesno() {
    local prompt="$1" default="${2:-n}" answer
    local hint="[y/N]"; [[ "$default" == "y" ]] && hint="[Y/n]"
    read -r -p "$prompt $hint: " answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

_menu_ok() { printf '%b\n' "${GREEN}✔ $*${NC}"; }
_menu_err() { printf '%b\n' "${RED}✘ $*${NC}" >&2; }

# ---- top level --------------------------------------------------------
menu_main() {
    local choice
    while true; do
        _menu_banner "encrypt · decrypt · convert"
        printf '%b\n' "  ${CYAN}1)${NC} encrypt   ${DIM}seal a folder or files with a password${NC}"
        printf '%b\n' "  ${CYAN}2)${NC} decrypt   ${DIM}unseal what you encrypted${NC}"
        printf '%b\n' "  ${CYAN}3)${NC} convert   ${DIM}shrink, reformat, strip, zip, video${NC}"
        printf '%b\n' "  ${CYAN}4)${NC} keys      ${DIM}list or remove encryption keys${NC}"
        printf '%b\n' "  ${CYAN}5)${NC} doctor    ${DIM}check external tools${NC}"
        printf '%b\n' "  ${CYAN}6)${NC} exit"
        printf '\n'
        read -r -p "Select option: " choice
        case "$choice" in
            1) menu_encrypt ;;
            2) menu_decrypt ;;
            3) menu_convert ;;
            4) menu_keys ;;
            5) menu_doctor ;;
            6|q|Q) clear 2>/dev/null; exit 0 ;;
            "") ;;
            *) _menu_err "invalid choice: $choice"; _menu_pause ;;
        esac
    done
}

# ---- encrypt ----------------------------------------------------------
menu_encrypt() {
    local choice
    while true; do
        _menu_banner "encrypt — seal with a generated key"
        printf '%b\n' "  ${CYAN}1)${NC} encrypt a ${YELLOW}folder${NC}  ${DIM}zip it, then encrypt the zip${NC}"
        printf '%b\n' "  ${CYAN}2)${NC} encrypt ${YELLOW}files${NC}     ${DIM}encrypt each file individually${NC}"
        printf '%b\n' "  ${CYAN}3)${NC} back"
        printf '\n'
        read -r -p "Select option: " choice
        case "$choice" in
            1) menu_encrypt_dir ;;
            2) menu_encrypt_files ;;
            3|b|B) return ;;
            "") ;;
            *) _menu_err "invalid choice: $choice"; _menu_pause ;;
        esac
    done
}

# Shared: confirm before deleting sources.
_menu_confirm_delete() {
    local what="$1"
    printf '\n'
    printf '%b\n' "${DIM}The key is saved to $WS_KEYS and printed at the end.${NC}"
    printf '%b\n' "${DIM}Without the key the data cannot be recovered.${NC}"
    if _menu_yesno "Delete $what after a successful seal?" "n"; then
        return 0
    else
        return 1
    fi
}

menu_encrypt_dir() {
    . "$ARC_LIB_DIR/seal.sh"
    _menu_banner "encrypt — folder"
    local path
    path="$(_menu_ask_path "Folder to encrypt:" "$HOME/Workspace")"
    [[ -d "$path" ]] || { _menu_err "not a directory: $path"; _menu_pause; return; }

    local -a args=("$path")
    _menu_confirm_delete "the original folder" || args+=(--keep)

    printf '\n'
    seal_dir "${args[@]}"
    _menu_pause
}

menu_encrypt_files() {
    . "$ARC_LIB_DIR/seal.sh"
    _menu_banner "encrypt — files"
    local path
    path="$(_menu_ask_path "File or folder of files:" "$HOME/Workspace")"
    [[ -e "$path" ]] || { _menu_err "does not exist: $path"; _menu_pause; return; }

    local -a args=("$path")
    _menu_confirm_delete "the original files" || args+=(--keep)

    printf '\n'
    seal_files "${args[@]}"
    _menu_pause
}

# ---- decrypt ----------------------------------------------------------
menu_decrypt() {
    . "$ARC_LIB_DIR/seal.sh"
    _menu_banner "decrypt — unseal"

    local choice
    if ! _menu_ask_choice "What do you want to decrypt?" \
            "Everything in $WS_ENCRYPTED (files)" \
            "Everything in $WS_ARCHIVES (folders)" \
            "A folder I choose"; then
        _menu_err "invalid choice"; _menu_pause; return
    fi
    choice="$REPLY_CHOICE"

    local src
    case "$choice" in
        1) src="$WS_ENCRYPTED" ;;
        2) src="$WS_ARCHIVES" ;;
        3) src="$(_menu_ask_path "Folder containing .gpg files:")" ;;
    esac

    [[ -d "$src" ]] || { _menu_err "no such folder: $src"; _menu_pause; return; }

    local to
    to="$(_menu_ask_path "Write decrypted files to:" "$WS_DECRYPTED")"

    printf '\n'
    unseal "$src" --to "$to"
    _menu_pause
}

# ---- convert ----------------------------------------------------------
menu_convert() {
    local choice
    while true; do
        _menu_banner "convert — process files"
        printf '%b\n' "  ${CYAN}1)${NC} shrink images      ${DIM}reach a target KB (jpg/webp/png)${NC}"
        printf '%b\n' "  ${CYAN}2)${NC} change image format ${DIM}png -> jpg / webp, no size target${NC}"
        printf '%b\n' "  ${CYAN}3)${NC} strip metadata      ${DIM}remove EXIF/GPS from photos${NC}"
        printf '%b\n' "  ${CYAN}4)${NC} rename + strip      ${DIM}strip metadata and give fake names${NC}"
        printf '%b\n' "  ${CYAN}5)${NC} zip a folder        ${DIM}plain .zip, no encryption${NC}"
        printf '%b\n' "  ${CYAN}6)${NC} shrink video        ${DIM}re-encode smaller with ffmpeg${NC}"
        printf '%b\n' "  ${CYAN}7)${NC} back"
        printf '\n'
        read -r -p "Select option: " choice
        case "$choice" in
            1) menu_convert_shrink ;;
            2) menu_convert_format ;;
            3) menu_convert_strip ;;
            4) menu_convert_rename ;;
            5) menu_convert_zip ;;
            6) menu_convert_video ;;
            7|b|B) return ;;
            "") ;;
            *) _menu_err "invalid choice: $choice"; _menu_pause ;;
        esac
    done
}

menu_convert_shrink() {
    . "$ARC_LIB_DIR/img.sh"
    _menu_banner "convert — shrink images"
    local path
    path="$(_menu_ask_path "Image file or folder:" "$HOME/Pictures/wallpapers")"
    [[ -e "$path" ]] || { _menu_err "does not exist: $path"; _menu_pause; return; }

    local kb
    kb="$(_menu_ask_path "Target size (KB):" "200")"
    printf '\n'
    img_compress "$path" "$kb" jpg
    _menu_pause
}

menu_convert_format() {
    . "$ARC_LIB_DIR/img.sh"
    _menu_banner "convert — change image format"
    local path
    path="$(_menu_ask_path "Image file or folder:" "$HOME/Pictures")"
    [[ -e "$path" ]] || { _menu_err "does not exist: $path"; _menu_pause; return; }

    local choice fmt
    if ! _menu_ask_choice "Convert to which format?" "jpg" "png" "webp"; then
        _menu_err "invalid choice"; _menu_pause; return
    fi
    choice="$REPLY_CHOICE"
    case "$choice" in 1) fmt=jpg ;; 2) fmt=png ;; 3) fmt=webp ;; esac

    printf '\n'
    # target 0 means "no size goal": pass a huge number so nothing is rejected
    OUT_DIR="${OUT_DIR:-$WS/image_compressor/converted_$(date +%Y%m%d_%H%M%S)}" \
        img_compress "$path" 100000 "$fmt"
    _menu_pause
}

menu_convert_strip() {
    . "$ARC_LIB_DIR/strip.sh"
    _menu_banner "convert — strip metadata"
    local path out
    path="$(_menu_ask_path "Image file or folder:" "$HOME/Pictures")"
    [[ -e "$path" ]] || { _menu_err "does not exist: $path"; _menu_pause; return; }
    out="$(_menu_ask_path "Write cleaned copies to:" "$WS_CLEANED")"
    printf '\n'
    img_strip "$path" "$out"
    _menu_pause
}

menu_convert_rename() {
    . "$ARC_LIB_DIR/strip.sh"
    _menu_banner "convert — strip metadata + fake names"
    local path out
    path="$(_menu_ask_path "Image file or folder:" "$HOME/Pictures")"
    [[ -e "$path" ]] || { _menu_err "does not exist: $path"; _menu_pause; return; }
    out="$(_menu_ask_path "Write renamed copies to:" "$WS_CLEANED")"
    printf '\n'
    img_strip_rename "$path" "$out"
    _menu_pause
}

menu_convert_zip() {
    _menu_banner "convert — zip a folder"
    local path
    path="$(_menu_ask_path "Folder to zip:" "$HOME/Workspace")"
    [[ -d "$path" ]] || { _menu_err "not a directory: $path"; _menu_pause; return; }
    need zip

    mkdir -p "$WS_ARCHIVES" || { _menu_err "cannot create $WS_ARCHIVES"; _menu_pause; return; }
    local out="$WS_ARCHIVES/$(basename "$(realpath "$path")")_$(date +%Y%m%d_%H%M%S).zip"
    local parent; parent="$(dirname "$(realpath "$path")")"
    local base; base="$(basename "$(realpath "$path")")"

    printf '\n'
    if ( cd "$parent" && zip -qry "$out" "$base" -x '*/.git/*' ); then
        _menu_ok "zip created: $out ($(human "$(stat -c%s "$out")"))"
    else
        _menu_err "zip failed"
    fi
    _menu_pause
}

menu_convert_video() {
    . "$ARC_LIB_DIR/vid.sh"
    _menu_banner "convert — shrink video"
    local path
    path="$(_menu_ask_path "Video file or folder:" "$HOME/Videos")"
    [[ -e "$path" ]] || { _menu_err "does not exist: $path"; _menu_pause; return; }

    local choice quality
    if ! _menu_ask_choice "How much smaller?" \
            "Light   (high quality)" \
            "Balanced" \
            "Small   (lower quality)"; then
        _menu_err "invalid choice"; _menu_pause; return
    fi
    choice="$REPLY_CHOICE"
    case "$choice" in 1) quality=88 ;; 2) quality=75 ;; 3) quality=55 ;; esac

    printf '\n'
    vid_compress "$path" "$quality"
    _menu_pause
}

# ---- keys / doctor ----------------------------------------------------
menu_keys() {
    . "$ARC_LIB_DIR/seal.sh"
    _menu_banner "keys"
    keys list
    printf '\n'
    if _menu_yesno "Remove a key?" "n"; then
        local name
        printf '%b\n' "${YELLOW}Key filename to remove:${NC}"
        read -r -p "> " name
        [[ -n "$name" ]] && keys rm "$name"
    fi
    _menu_pause
}

menu_doctor() {
    _menu_banner "doctor"
    doctor
    _menu_pause
}
