# arc — Workspace toolbox

One CLI for the scripts that were previously scattered across `~/.aliases`:
image compression, metadata stripping, video re-encoding, and
symmetric sealing (encrypt/decrypt with per-operation keys).

Everything lives in this folder. The only external requirements are
command-line tools that can't reasonably be bundled — `arc doctor` tells you
exactly which ones are missing.

## Install

```sh
cd ~/.aliases/arc
make install		# symlinks ~/.local/bin/arc -> ./arc
make check		# report missing external tools
```

`make install` creates a **symlink**, so keep this folder where it is. Move the
folder and the link breaks; run `make install` again afterwards.

Uninstall with `make uninstall`.

## Requirements

| Tool | Needed for | Notes |
|---|---|---|
| `magick` (ImageMagick) | `arc img` | Fedora package `ImageMagick` |
| `ffmpeg` / `ffprobe` | `arc vid` | `ffprobe` ships with `ffmpeg` |
| `gpg` | `arc seal` / `arc unseal` | AES256 symmetric |
| `zip` / `unzip` | `arc seal dir` | archive verified before source removal |
| `exiftool` | `arc img strip` | optional until you strip |
| `pngquant` | `arc img compress … png` | optional, better PNG ratios |

```sh
arc doctor                    # check what's present
sudo dnf install ImageMagick ffmpeg gnupg2 zip unzip perl-Image-ExifTool
```

## Usage

### Guided mode (recommended for first use)

```sh
arc            # opens the menu
```

```
1) encrypt   seal a folder or files with a password
2) decrypt   unseal what you encrypted
3) convert   shrink, reformat, strip, zip, video
4) keys      list or remove encryption keys
5) doctor    check external tools
6) exit
```

Every step prompts you: pick a path (with a sensible default), then any
options. Nothing is deleted without an explicit yes/no confirmation.

Under **convert**:

| # | Option | Does |
|---|---|---|
| 1 | shrink images | reach a target KB (jpg/webp/png) |
| 2 | change image format | png -> jpg / webp |
| 3 | strip metadata | remove EXIF/GPS |
| 4 | rename + strip | strip, then write fake author/dates |
| 5 | zip a folder | plain .zip, no encryption |
| 6 | shrink video | re-encode smaller |

`arc menu` also opens it explicitly. Bare `arc` only opens the menu when
stdin and stdout are a terminal; otherwise it prints usage, so it stays safe
in scripts and pipes.

### Direct mode (for scripting and repeat use)

```
arc img compress <path> [target_kb] [formats...]   shrink images
arc img strip    <path> [outdir]                   strip EXIF/GPS
arc vid compress <path> [quality]                  re-encode smaller
arc seal dir     <folder> [--keep]                 zip + encrypt a folder
arc seal files   <path>   [--keep]                 encrypt files in place
arc unseal       [folder] [--key <file>] [--to <dir>]
arc keys         [list | rm <file>]
arc doctor
```

Every subcommand takes `--help`.

### Examples

```sh
arc img compress photo.png                      # target 200 KB
arc img compress ~/Pictures 500 jpg webp        # both formats, 500 KB target
OUT_DIR=/tmp/out arc img compress pic.jpg 100   # override output dir
arc img strip ~/Pictures ~/clean
arc vid compress movie.mkv 70                   # quality 0-100
arc seal dir ~/project                          # source removed after seal
arc seal dir ~/project --keep                   # keep the original
arc keys list
arc unseal --to ~/restored
```

## Layout

```
arc/            entry point: arg parsing, dispatch, doctor
arc-lib/img.sh  compression + format stepping
arc-lib/strip.sh metadata stripping
arc-lib/vid.sh  video re-encoding
arc-lib/seal.sh sealing, key management, unseal
Makefile        install / check / test
```

`arc` resolves its own path through symlinks, so `arc-lib/` is always found
next to the real script rather than next to the link.

## Where files go

Defaults are rooted at `$WS` (`~/Workspace`, override with `ARC_WORKSPACE`):

| Path | Contents |
|---|---|
| `$WS/image_compressor/compressed_<ts>/` | compressed images (`OUT_DIR` overrides) |
| `$WS/cleaned/` | metadata-stripped copies |
| `$WS/archives/` | encrypted folder archives (`.zip.gpg`) |
| `$WS/encrypted/` | encrypted individual files (`.gpg`) |
| `$WS/decrypted/` | unsealed output |
| `$WS/keys/` | key files + `.meta` sidecars |

## Design notes

**Sealing safety.** A source is deleted only after the archive is proven
readable (`unzip -t`) and the encrypted blob is non-empty. Any failure leaves
both original and plaintext archive in place.

**Key pairing.** Each key gets a `.meta` sidecar recording `target=`, `kind=`,
`created=` and a `blob=` line per sealed artefact. `unseal` resolves the key
**per blob** from that sidecar. The older scripts picked the newest key by
mtime, so sealing a second time made the first batch undecryptable.

**Video encoder.** This ffmpeg build on Fedora has no `libx264` (no GPL x264)
and VAAPI does not initialise on this hardware, so `libopenh264` is used with
a bitrate derived from resolution × quality instead of CRF.

**Legacy scripts removed.** The four scripts arc replaced
(`image_compressor`, `encrypt_images.sh`, `decrypt_images_fixed.sh`,
`compress-video.sh`) and their shell aliases (`compress`, `encrypt`,
`decrypt`, `compress-video`) have been deleted. Use `arc` instead.

## Test

```sh
make test        # bash -n on every file + smoke tests, no root needed
```
