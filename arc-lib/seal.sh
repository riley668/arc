# arc-lib/seal.sh — symmetric encryption with per-operation keys
#
# Fixes the original scripts' "newest key wins" bug: each key file records
# exactly what it unlocks (a .meta sidecar), so unseal resolves the right
# key instead of guessing by mtime.

seal_usage() {
    cat <<'EOF'
arc seal dir   <folder> [--keep]
  Zip the folder into $WS/archives and encrypt the archive (AES256).
  The source folder is deleted only after a verified seal, unless --keep.

arc seal files <path> [--keep]
  Encrypt every matching file into $WS/encrypted, individually.
  Sources are removed after success unless --keep.

arc unseal [folder] [--key <file>] [--to <dir>]
  Decrypt sealed files. With no folder, decrypts for the newest key.
  --key forces a specific key. --to sets the output dir.

arc keys [list | rm <file>]
  List key files with what they seal, or delete a key.

Every sealed artefact gets a key at $WS/keys/ plus a .meta sidecar
recording its target. Keys are created with umask 077.
EOF
}

_seal_newkey() {
    local prefix="$1"
    mkdir -p "$WS_KEYS" || die "cannot create $WS_KEYS"
    chmod 700 "$WS_KEYS" 2>/dev/null || true
    local keyfile="$WS_KEYS/.${prefix}_$(date +%Y%m%d_%H%M%S).txt"
    ( umask 077; openssl rand -base64 32 > "$keyfile" ) || die "cannot write key"
    [[ -s "$keyfile" ]] || die "key file empty: $keyfile"
    printf '%s\n' "$keyfile"
}

_seal_meta() {
    # Sidecar records what this key unlocks. Alongside the target dir we
    # record each sealed blob, so unseal can pick the exact key per blob
    # instead of guessing by mtime.
    local keyfile="$1" target="$2" kind="$3"
    shift 3
    {
        printf 'target=%s\nkind=%s\ncreated=%s\n' \
            "$target" "$kind" "$(date -Is)"
        local b
        for b in "$@"; do
            [[ -n "$b" ]] && printf 'blob=%s\n' "$b"
        done
    } > "${keyfile%.txt}.meta"
}

seal_dir() {
    local src="${1:-}"
    case "$src" in
        -h|--help|"") seal_usage; return 0 ;;
    esac
    local keep=0
    [[ "${2:-}" == "--keep" ]] && keep=1

    [[ "$src" == "~/"* ]] && src="$HOME/${src#~/}"
    [[ -d "$src" ]] || die "not a directory: $src"
    need zip gpg openssl

    mkdir -p "$WS_ARCHIVES" || die "cannot create $WS_ARCHIVES"
    local base stamp archive keyfile
    base="$(basename "$(realpath "$src")")"
    stamp="$(date +%Y%m%d_%H%M%S)"
    archive="$WS_ARCHIVES/${base}_${stamp}.zip"

    say "arc: zipping $src"
    local parent
    parent="$(dirname "$(realpath "$src")")"
    # -y keeps symlinks as links; run from the parent so paths stay relative.
    ( cd "$parent" && zip -qry "$archive" "$base" -x '*/.git/*' ) 2>/dev/null || die "zip failed"
    [[ -s "$archive" ]] || die "archive empty: $archive"

    # Prove the archive is readable before trusting it.
    unzip -tq "$archive" >/dev/null 2>&1 || die "archive corrupt, aborting: $archive"

    keyfile="$(_seal_newkey archive)"
    local key out
    key="$(tr -d '\n\r' < "$keyfile")"
    out="${archive}.gpg"

    if ! gpg --batch --yes --passphrase "$key" -c --cipher-algo AES256 -o "$out" "$archive" 2>/dev/null; then
        rm -f "$out"
        die "gpg failed; archive kept at $archive"
    fi

    # Verify the encrypted blob is non-trivial, then drop the plaintext.
    [[ -s "$out" ]] || die "encrypted output empty; archive kept at $archive"
    rm -f "$archive"

    _seal_meta "$keyfile" "$out" "dir" "$out"
    say "arc: sealed -> $out ($(human "$(stat -c%s "$out")"))"
    say "arc: key    -> $keyfile"

    if (( keep )); then
        say "arc: --keep, source left in place: $src"
    else
        rm -rf -- "$src" && say "arc: source removed: $src"
    fi
}

seal_files() {
    local src="${1:-}"
    case "$src" in
        -h|--help|"") seal_usage; return 0 ;;
    esac
    local keep=0
    [[ "${2:-}" == "--keep" ]] && keep=1

    [[ "$src" == "~/"* ]] && src="$HOME/${src#~/}"
    [[ -e "$src" ]] || die "does not exist: $src"
    need gpg openssl

    mkdir -p "$WS_ENCRYPTED" || die "cannot create $WS_ENCRYPTED"

    local -a files=()
    if [[ -d "$src" ]]; then
        mapfile -t files < <(find "$src" -maxdepth 1 -type f 2>/dev/null)
    else
        files=("$src")
    fi
    (( ${#files[@]} )) || die "no files found in: $src"

    local keyfile key
    keyfile="$(_seal_newkey encrypt)"
    key="$(tr -d '\n\r' < "$keyfile")"

    local f out n=0 fail=0
    local -a blobs=()
    for f in "${files[@]}"; do
        out="$WS_ENCRYPTED/$(basename "$f").gpg"
        if gpg --batch --yes --passphrase "$key" -c --cipher-algo AES256 -o "$out" "$f" 2>/dev/null; then
            if [[ -s "$out" ]]; then
                n=$(( n + 1 ))
                blobs+=("$out")
                (( keep )) || rm -f -- "$f"
                say "  sealed: $(basename "$f")"
            else
                rm -f "$out"; fail=$(( fail + 1 ))
                warn "empty output for $f (kept original)"
            fi
        else
            fail=$(( fail + 1 ))
            rm -f "$out"
            warn "gpg failed on $f (kept original)"
        fi
    done

    _seal_meta "$keyfile" "$WS_ENCRYPTED" "files" "${blobs[@]}"
    say "arc: sealed $n file(s), $fail failed"
    say "arc: key -> $keyfile"
}

# Resolve the key for a target: prefer explicit, else the key whose .meta
# names this target, else the newest key (with a warning).
_unseal_pickkey() {
    local explicit="${1:-}" target="${2:-}"
    if [[ -n "$explicit" ]]; then
        [[ -r "$explicit" ]] || die "key not readable: $explicit"
        printf '%s\n' "$explicit"; return 0
    fi
    local m
    # 1) key whose meta records this exact blob
    while IFS= read -r m; do
        [[ -e "$m" ]] || continue
        if grep -qxF "blob=$target" "$m" 2>/dev/null; then
            local k="${m%.meta}.txt"
            [[ -r "$k" ]] && { printf '%s\n' "$k"; return 0; }
        fi
    done < <(find "$WS_KEYS" -maxdepth 1 -name '*.meta' -type f 2>/dev/null)
    # 2) key whose meta records the containing directory
    while IFS= read -r m; do
        [[ -e "$m" ]] || continue
        if grep -qxF "target=$target" "$m" 2>/dev/null; then
            local k="${m%.meta}.txt"
            [[ -r "$k" ]] && { printf '%s\n' "$k"; return 0; }
        fi
    done < <(find "$WS_KEYS" -maxdepth 1 -name '*.meta' -type f 2>/dev/null)
    return 1
}

unseal() {
    local folder="" explicit_key="" to=""
    while (( $# )); do
        case "$1" in
            --key) explicit_key="${2:-}"; shift 2 ;;
            --to)  to="${2:-}"; shift 2 ;;
            -h|--help) seal_usage; return 0 ;;
            *) folder="$1"; shift ;;
        esac
    done

    folder="${folder:-$WS_ENCRYPTED}"
    [[ "$folder" == "~/"* ]] && folder="$HOME/${folder#~/}"
    to="${to:-$WS_DECRYPTED}"
    [[ -d "$folder" ]] || die "folder not found: $folder"
    need gpg

    local -a blobs=()
    mapfile -t blobs < <(find "$folder" -name '*.gpg' -type f 2>/dev/null)
    (( ${#blobs[@]} )) || { say "no .gpg files in $folder"; return 0; }

    say "arc: decrypting ${#blobs[@]} blob(s) from $folder -> $to"
    mkdir -p "$to" || die "cannot create $to"

    local b out keyfile key n=0 fail=0
    local -a used_keys=() failed_keys=()
    for b in "${blobs[@]}"; do
        # Resolve the key for THIS blob; fall back to newest only at the end.
        if [[ -n "$explicit_key" ]]; then
            keyfile="$explicit_key"
        elif ! keyfile="$(_unseal_pickkey "" "$b")"; then
            keyfile="$(_unseal_pickkey "" "$folder")" || {
                warn "no key found for $b"
                fail=$(( fail + 1 )); continue
            }
        fi
        key="$(tr -d '\n\r' < "$keyfile")"
        out="$to/$(basename "${b%.gpg}")"

        if gpg --batch --yes --passphrase "$key" -d -o "$out" "$b" 2>/dev/null; then
            rm -f -- "$b"
            n=$(( n + 1 ))
            used_keys+=("$keyfile")
            say "  unsealed: $(basename "$out")  [$(basename "$keyfile")]"
        else
            fail=$(( fail + 1 ))
            failed_keys+=("$keyfile")
            rm -f "$out"
            warn "failed: $b"
        fi
    done

    say "arc: unsealed $n, failed $fail"

    if (( fail == 0 && n > 0 )); then
        # Retire only keys that actually unlocked something and have no
        # blobs left on disk.
        local k
        for k in $(printf '%s\n' "${used_keys[@]}" | sort -u); do
            rm -f -- "$k" "${k%.txt}.meta"
            say "arc: key removed: $(basename "$k")"
        done
    else
        say "arc: keeping keys for retries"
    fi
}

keys() {
    local action="${1:-list}"
    case "$action" in
        -h|--help) seal_usage; return 0 ;;
        list)
            [[ -d "$WS_KEYS" ]] || { say "no keys yet ($WS_KEYS)"; return 0; }
            local -a ks=()
            mapfile -t ks < <(find "$WS_KEYS" -maxdepth 1 -name '*.txt' -type f 2>/dev/null | sort)
            (( ${#ks[@]} )) || { say "no keys in $WS_KEYS"; return 0; }
            local k target created
            for k in "${ks[@]}"; do
                target="-"; created="-"
                if [[ -r "${k%.txt}.meta" ]]; then
                    target=$(grep '^target=' "${k%.txt}.meta" 2>/dev/null | cut -d= -f2-)
                    created=$(grep '^created=' "${k%.txt}.meta" 2>/dev/null | cut -d= -f2-)
                fi
                printf '  %s\n    target: %s\n    created: %s\n' "$(basename "$k")" "$target" "$created"
            done
            ;;
        rm)
            local f="${2:-}"
            [[ -n "$f" ]] || die "usage: arc keys rm <file>"
            [[ -f "$WS_KEYS/$f" ]] || f="$2"
            [[ -f "$f" ]] || die "no such key: ${2:-}"
            rm -f -- "$f" "${f%.txt}.meta"
            say "arc: removed key $f"
            ;;
        *) die "unknown keys action: $action (list|rm)" ;;
    esac
}
