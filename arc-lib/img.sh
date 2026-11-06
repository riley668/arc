# arc-lib/img.sh — image compression
# Sourced by `arc` (see ~/.local/bin/arc). Not executable on its own.

img_usage() {
    cat <<'EOF'
arc img compress <path> [target_kb] [formats...]

  Shrink images to roughly target_kb by stepping JPEG/WebP quality down.
  Formats: jpg webp png   (default: jpg)
  Default target: 200 KB

  A single file or an entire folder (non-recursive) may be given.
  Output goes to $WS/image_compressor/compressed_<timestamp>/
  unless OUT_DIR is set.

Examples
  arc img compress photo.png
  arc img compress ~/Pictures 500 jpg webp
  OUT_DIR=/tmp/out arc img compress pic.jpg 100

arc img strip <path> [outdir]
  Strip metadata (EXIF/GPS) from images, copying results to outdir
  (default $WS/cleaned). Originals are never modified.
EOF
}

_img_magick() {
    if command -v magick >/dev/null 2>&1; then
        IMG_MAGICK=(magick)
    elif command -v convert >/dev/null 2>&1; then
        IMG_MAGICK=(convert)
    else
        die "ImageMagick not found (install imagemagick)"
    fi
}

_img_files() {
    local input="$1"
    local -a found=()
    shopt -s nullglob nocaseglob
    if [[ -d "$input" ]]; then
        local f
        for f in "$input"/*; do
            [[ -f "$f" ]] || continue
            case "${f##*.}" in
                jpg|jpeg|png|webp) found+=("$f") ;;
            esac
        done
    else
        case "${input##*.}" in
            jpg|jpeg|png|webp) found=("$input") ;;
            *) die "unsupported image type: $input" ;;
        esac
    fi
    shopt -u nullglob nocaseglob
    (( ${#found[@]} )) || die "no supported images found in: $input"
    printf '%s\n' "${found[@]}"
}

img_compress() {
    case "${1:-}" in -h|--help) img_usage; return 0 ;; esac
    _img_magick

    local input="${1:-}"
    [[ -z "$input" ]] && { img_usage; return 1; }
    # expand leading ~
    [[ "$input" == "~" ]] && input="$HOME"
    [[ "$input" == "~/"* ]] && input="$HOME/${input#~/}"
    [[ -e "$input" ]] || die "path does not exist: $input"
    shift || true

    local target_kb=200
    if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
        target_kb="$1"; shift
    fi
    (( target_kb > 0 )) || die "target size must be greater than zero"
    local target_bytes=$(( target_kb * 1024 ))

    local -a formats=(jpg)
    (( $# )) && formats=("$@")
    local f
    for f in "${formats[@]}"; do
        case "$f" in
            jpg|webp|png) ;;
            *) die "unsupported format '$f' (supported: jpg webp png)" ;;
        esac
    done

    local out_dir="${OUT_DIR:-$WS/image_compressor/compressed_$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$out_dir" || die "cannot create output dir: $out_dir"

    local -a files=()
    local list
    if ! list=$(_img_files "$input"); then
        die "no supported images found in: $input"
    fi
    mapfile -t files < <(printf '%s\n' "$list")
    (( ${#files[@]} )) || die "no supported images found in: $input"

    say "arc: compressing ${#files[@]} image(s) to <= ${target_kb}KB"
    say "arc: output $out_dir"

    local src
    for src in "${files[@]}"; do
        local base out src_bytes=true
        base="$(basename "${src%.*}")"
        for f in "${formats[@]}"; do
            out="$out_dir/${base}.${f}"
            # Skip work if the source is already the right format and small enough
            local src_ext="${src##*.}"
            src_ext="$(printf '%s' "$src_ext" | tr '[:upper:]' '[:lower:]')"
            [[ "$src_ext" == "jpeg" ]] && src_ext="jpg"
            if [[ "$src_ext" == "$f" ]] && (( $(stat -c%s "$src") <= target_bytes )); then
                cp -f "$src" "$out"
                printf '  %-4s  %s  (%s, copied)\n' "$f" "$out" "$(human "$(stat -c%s "$out")")"
                continue
            fi

            case "$f" in
                jpg)  _img_jpg  "$src" "$out" "$target_bytes" ;;
                webp) _img_webp "$src" "$out" "$target_bytes" ;;
                png)  _img_png  "$src" "$out" ;;
            esac

            if [[ -f "$out" ]]; then
                local sz
                sz=$(stat -c%s "$out")
                if (( sz <= target_bytes )) && [[ "$f" != "png" ]]; then
                    printf '  %-4s  %s  (%s)\n' "$f" "$out" "$(human "$sz")"
                else
                    printf '  %-4s  %s  (%s, target not reached)\n' "$f" "$out" "$(human "$sz")"
                fi
            else
                warn "failed to create $out"
            fi
        done
    done
    say "arc: done -> $out_dir"
}

_img_jpg() {
    local src="$1" out="$2" target="$3" q=85
    while (( q >= 10 )); do
        "${IMG_MAGICK[@]}" "$src" -auto-orient -strip \
            -background white -alpha remove -alpha off \
            -quality "$q" "$out" 2>/dev/null || return 1
        (( $(stat -c%s "$out") <= target )) && return 0
        q=$(( q - 5 ))
    done
    return 0
}

_img_webp() {
    local src="$1" out="$2" target="$3" q=80
    while (( q >= 10 )); do
        "${IMG_MAGICK[@]}" "$src" -auto-orient -strip -quality "$q" "$out" 2>/dev/null || return 1
        (( $(stat -c%s "$out") <= target )) && return 0
        q=$(( q - 5 ))
    done
    return 0
}

_img_png() {
    local src="$1" out="$2" tmp="${2}.tmp.png"
    if command -v pngquant >/dev/null 2>&1; then
        if pngquant --force --quality=40-80 --speed 3 --output "$tmp" "$src" >/dev/null 2>&1; then
            mv -f "$tmp" "$out"; return 0
        fi
        rm -f "$tmp"
    fi
    "${IMG_MAGICK[@]}" "$src" -auto-orient -strip \
        -define png:compression-level=9 \
        -define png:compression-filter=5 \
        -define png:compression-strategy=1 "$out" 2>/dev/null
}
