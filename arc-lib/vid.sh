# arc-lib/vid.sh — video compression
# Sourced by `arc`. libx264 is NOT available in this ffmpeg build (Fedora
# ships it without x264); VAAPI fails to init here, so libopenh264 is the
# only working software encoder. Bitrate is the quality knob instead of CRF.

vid_usage() {
    cat <<'EOF'
arc vid compress <path> [quality]

  Re-encode videos smaller. Output is written BESIDE the original as
  <name>-compressed.mp4. Existing outputs are skipped.

  quality: 0-100, higher = better (default 75). Maps to libopenh264 bitrate.

  Encoder note: this ffmpeg build has no libx264 and VAAPI does not
  initialise on this machine, so libopenh264 is used. Metadata
  (-map_metadata -1) is stripped.

Examples
  arc vid compress movie.mkv
  arc vid compress ~/Videos 60
EOF
}

_vid_find() {
    find "$1" -type f \
        \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" \
        -o -iname "*.avi" -o -iname "*.flv" -o -iname "*.webm" \
        -o -iname "*.m4v" \) 2>/dev/null
}

_vid_encode() {
    local in="$1" quality="$2"
    local dir name out
    dir="$(dirname "$in")"
    name="$(basename "${in%.*}")"
    out="$dir/${name}-compressed.mp4"

    if [[ -f "$out" ]]; then
        say "  skip (exists): $out"
        return 0
    fi

    # Map 0-100 quality onto a sane bitrate range, scaled by resolution.
    local height bitrate
    height=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=height -of csv=p=0 "$in" 2>/dev/null | head -1)
    [[ "$height" =~ ^[0-9]+$ ]] || height=720
    # ~1.0x height as a base kbps, adjusted by quality
    bitrate=$(( height * quality / 100 ))

    local orig_h
    orig_h=$(human "$(stat -c%s "$in")")
    say "  encoding: $in ($orig_h, ${height}p @ ${bitrate}k)"

    if ! ffmpeg -y -loglevel error -i "$in" \
            -vcodec libopenh264 -preset medium -b:v "${bitrate}k" \
            -map_metadata -1 -c:a aac -b:a 128k \
            "$out" 2>/dev/null; then
        warn "ffmpeg failed on $in"
        rm -f "$out"
        return 1
    fi

    local new_size orig_size reduction=0
    new_size=$(stat -c%s "$out")
    orig_size=$(stat -c%s "$in")
    (( orig_size > 0 )) && reduction=$(( 100 - new_size * 100 / orig_size ))
    say "    $(human "$orig_size") -> $(human "$new_size")  (${reduction}% smaller)  $out"
}

vid_compress() {
    case "${1:-}" in -h|--help) vid_usage; return 0 ;; esac

    local input="${1:-}"
    if [[ -z "$input" ]]; then
        read -r -p "file or folder: " input
    fi
    [[ -z "$input" ]] && { vid_usage; return 1; }
    [[ "$input" == "~/"* ]] && input="$HOME/${input#~/}"
    [[ -e "$input" ]] || die "does not exist: $input"

    local quality="${2:-75}"
    [[ "$quality" =~ ^[0-9]+$ ]] || die "quality must be a number 0-100"
    (( quality >= 1 && quality <= 100 )) || die "quality must be 1-100"

    need ffmpeg
    need ffprobe

    if [[ -f "$input" ]]; then
        _vid_encode "$input" "$quality"
    else
        local -a vids=()
        mapfile -t vids < <(_vid_find "$input")
        (( ${#vids[@]} )) || { say "no video files in: $input"; return 0; }
        say "arc: found ${#vids[@]} video(s)"
        local v
        for v in "${vids[@]}"; do
            _vid_encode "$v" "$quality"
        done
    fi
}
