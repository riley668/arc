# arc-lib/strip.sh — metadata stripping
# Sourced by `arc`. Originals are copied, never modified.

img_strip() {
    case "${1:-}" in -h|--help) img_usage; return 0 ;; esac
    # _img_files lives in img.sh; load it here so strip works standalone.
    . "$ARC_LIB_DIR/img.sh"

    local input="${1:-.}"
    local out_dir="${2:-$WS_CLEANED}"
    [[ "$input" == "~/"* ]] && input="$HOME/${input#~/}"
    [[ -e "$input" ]] || die "path does not exist: $input"

    command -v exiftool >/dev/null 2>&1 || die "exiftool not found (install libimage-exiftool-perl)"
    mkdir -p "$out_dir" || die "cannot create $out_dir"

    local -a files=()
    local list
    if ! list=$(_img_files "$input"); then
        die "no supported images found in: $input"
    fi
    mapfile -t files < <(printf '%s\n' "$list")
    (( ${#files[@]} )) || die "no supported images found in: $input"

    say "arc: stripping metadata from ${#files[@]} image(s) -> $out_dir"
    local src out before after
    for src in "${files[@]}"; do
        out="$out_dir/$(basename "$src")"
        before=$(stat -c%s "$src")
        # all= removes EXIF/GPS/XMP/IPTC comments; keep the pixel data intact.
        if exiftool -q -q -all= -o "$out" -- "$src"; then
            after=$(stat -c%s "$out" 2>/dev/null || echo 0)
            printf '  %s  (%s -> %s)\n' "$(basename "$src")" "$(human "$before")" "$(human "$after")"
        else
            warn "exiftool failed on $src"
        fi
    done
    say "arc: done -> $out_dir"
}

# ---------------------------------------------------------------------------
# img_strip_rename — port of the original strip_meta.sh.
# Strips all metadata, then writes consistent FAKE metadata (author, creator,
# copyright, keywords, and fixed dates) so files look like they came from one
# person on one day. Covers images AND videos. File names are not changed.
# ---------------------------------------------------------------------------
img_strip_rename() {
    case "${1:-}" in -h|--help) img_usage; return 0 ;; esac

    local input="${1:-.}"
    local out_dir="${2:-$WS_CLEANED}"
    [[ "$input" == "~/"* ]] && input="$HOME/${input#~/}"
    [[ -e "$input" ]] || die "path does not exist: $input"

    command -v exiftool >/dev/null 2>&1 || die "exiftool not found (install libimage-exiftool-perl)"
    mkdir -p "$out_dir" || die "cannot create $out_dir"

    local -a male=(Ivan Dmitri Aleksandr Sergei Viktor Boris Nikolai Pyotr Yuri Andrei)
    local -a female=(Olga Natasha Tatiana Elena Irina Svetlana Galina Anya Larisa Nadezhda)
    local -a male_sn=(Petrov Sokolov Volkov Kozlov Lebedev Novikov Morozov Vasiliev Kuznetsov Popov)
    local -a female_sn=(Petrova Sokolova Volkova Kozlova Lebedeva Novikova Morozova Vasilieva Kuznetsova Popova)

    local name
    if (( RANDOM % 2 )); then
        name="${male[RANDOM % ${#male[@]}]} ${male_sn[RANDOM % ${#male_sn[@]}]}"
    else
        name="${female[RANDOM % ${#female[@]}]} ${female_sn[RANDOM % ${#female_sn[@]}]}"
    fi
    local fake_date="1950:04:01 00:00:00"

    local -a files=()
    mapfile -t files < <(find "$input" -maxdepth 1 -type f \( \
        -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.tiff' -o -iname '*.heic' \
        -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.avi' \
        -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.flv' \) 2>/dev/null)
    (( ${#files[@]} )) || die "no supported images or videos in: $input"

    say "arc: stripping metadata as '$name' -> $out_dir"
    local f out n=0 fail=0
    for f in "${files[@]}"; do
        out="$out_dir/$(basename "$f")"
        if exiftool -q -q -all= \
                '-QuickTime:*Date*=' \
                -Artist="$name" -Author="$name" -Creator="$name" \
                -Copyright="$name" -Keywords="$name" \
                -CreateDate="$fake_date" -ModifyDate="$fake_date" \
                -DateTimeOriginal="$fake_date" \
                -MediaCreateDate="$fake_date" -MediaModifyDate="$fake_date" \
                -TrackCreateDate="$fake_date" -TrackModifyDate="$fake_date" \
                -o "$out" -- "$f"; then
            n=$(( n + 1 ))
            say "  $(basename "$f") -> $out"
        else
            fail=$(( fail + 1 ))
            warn "exiftool failed on $f"
        fi
    done
    say "arc: cleaned $n, failed $fail -> $out_dir"
}
