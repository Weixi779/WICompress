#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="$SCRIPT_DIR/corpora/manifest.json"
LOCK_FILE="$SCRIPT_DIR/corpora/manifest.lock.json"
DATA_ROOT="$SCRIPT_DIR/data/corpora"
FETCH_LOCK="$DATA_ROOT/.fetch.lock"
RECEIPT_NAME=".wicompress-corpus"
WORK_DIR=""
RECEIPT_TEMP=""
LOCK_HELD=false

readonly SCRIPT_DIR MANIFEST_FILE LOCK_FILE DATA_ROOT FETCH_LOCK RECEIPT_NAME

usage() {
    cat <<'EOF'
Fetch a verified local corpus for the target-compression benchmark.

Usage:
  fetch-corpora.sh <corpus> [<corpus> ...]
  fetch-corpora.sh --list

Corpora:
  clic-professional-valid  CLIC 2020 Professional validation (41 PNG, ~129 MB)
  clic-mobile-valid        CLIC 2020 Mobile validation (61 PNG, ~226 MB)
  jpeg-ai-cfe              JPEG AI Call for Evidence test images (16 PNG)
  all                      Fetch all three corpora explicitly

No corpus is downloaded by default. Verified destinations are reused and never replaced.
EOF
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$WORK_DIR" && "$WORK_DIR" == "$DATA_ROOT"/.fetch.* ]]; then
        rm -rf -- "$WORK_DIR"
    fi
    if [[ -n "$RECEIPT_TEMP" && "$RECEIPT_TEMP" == "$DATA_ROOT"/*/"$RECEIPT_NAME".tmp.* ]]; then
        /bin/rm -f -- "$RECEIPT_TEMP"
    fi
    if [[ "$LOCK_HELD" == true ]]; then
        /bin/rmdir "$FETCH_LOCK" 2>/dev/null || true
    fi
}

trap cleanup EXIT

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

json_value() {
    /usr/bin/plutil -extract "$1" raw -n -- "$LOCK_FILE"
}

manifest_value() {
    /usr/bin/plutil -extract "$1" raw -n -- "$MANIFEST_FILE"
}

corpus_index() {
    case "$1" in
        clic-professional-valid) printf '0' ;;
        clic-mobile-valid) printf '1' ;;
        jpeg-ai-cfe) printf '2' ;;
        *) fail "unknown corpus: $1" ;;
    esac
}

add_selection() {
    local candidate="$1"
    local selected

    corpus_index "$candidate" >/dev/null
    for selected in "${SELECTED[@]:-}"; do
        [[ "$selected" == "$candidate" ]] && return
    done
    SELECTED+=("$candidate")
}

download() {
    local url="$1"
    local destination="$2"
    local expected_bytes="$3"

    printf 'Downloading %s\n' "$url"
    /usr/bin/curl \
        --connect-timeout 20 \
        --fail \
        --location \
        --max-filesize "$expected_bytes" \
        --proto '=https' \
        --proto-redir '=https' \
        --show-error \
        --silent \
        --speed-limit 1024 \
        --speed-time 60 \
        --retry 3 \
        --output "$destination" \
        "$url"
    [[ -s "$destination" ]] || fail "downloaded an empty file: $url"
    verify_byte_length "$destination" "$expected_bytes"
}

verify_md5() {
    local file="$1"
    local expected="$2"
    local actual

    actual="$(/sbin/md5 -q "$file")"
    [[ "$actual" == "$expected" ]] \
        || fail "MD5 mismatch for $(basename "$file"): expected $expected, got $actual"
}

verify_byte_length() {
    local file="$1"
    local expected="$2"
    local actual

    actual="$(/usr/bin/stat -f '%z' "$file")"
    [[ "$actual" == "$expected" ]] \
        || fail "byte length mismatch for $(basename "$file"): expected $expected, got $actual"
}

zip_member_uncompressed_size() {
    local archive="$1"
    local member="$2"
    local size

    size="$(/usr/bin/zipinfo -l "$archive" "$member" \
        | /usr/bin/awk '$1 ~ /^-/ && $4 ~ /^[0-9]+$/ { print $4 }')"
    [[ "$size" =~ ^[0-9]+$ ]] \
        || fail "could not determine the uncompressed size of $member"
    printf '%s' "$size"
}

verify_archive_expansion_limit() {
    local archive="$1"
    local listing="$2"
    local maximum_bytes="$3"
    local entry
    local entry_bytes
    local total_bytes=0

    while IFS= read -r entry || [[ -n "$entry" ]]; do
        entry_bytes="$(zip_member_uncompressed_size "$archive" "$entry")"
        ((entry_bytes <= maximum_bytes - total_bytes)) \
            || fail "ZIP exceeds the $maximum_bytes-byte extraction limit: $(basename "$archive")"
        ((total_bytes += entry_bytes))
    done < "$listing"
}

directory_byte_length() {
    local directory="$1"
    local entry
    local entry_bytes
    local total_bytes=0

    shopt -s nullglob
    for entry in "$directory"/*.png; do
        entry_bytes="$(/usr/bin/stat -f '%z' "$entry")"
        ((total_bytes += entry_bytes))
    done
    shopt -u nullglob
    printf '%s' "$total_bytes"
}

corpus_digest() {
    local directory="$1"
    local entry
    local name
    local byte_length
    local sha256

    {
        shopt -s nullglob
        for entry in "$directory"/*.png; do
            name="$(basename "$entry")"
            byte_length="$(/usr/bin/stat -f '%z' "$entry")"
            sha256="$(/usr/bin/shasum -a 256 "$entry" | /usr/bin/awk '{ print $1 }')"
            printf '%s\t%s\t%s\n' "$name" "$byte_length" "$sha256"
        done
        shopt -u nullglob
    } | LC_ALL=C /usr/bin/sort | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }'
}

receipt_value() {
    local receipt="$1"
    local key="$2"

    /usr/bin/awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2) }' "$receipt"
}

corpus_lock_fingerprint() {
    local id="$1"
    local index
    local kind
    local contents_prefix

    index="$(corpus_index "$id")"
    kind="$(json_value "corpora.$index.kind")"
    contents_prefix="corpora.$index.contents"

    {
        printf 'id=%s\n' "$(json_value "corpora.$index.id")"
        printf 'kind=%s\n' "$kind"
        printf 'fileCount=%s\n' "$(json_value "$contents_prefix.fileCount")"
        printf 'layout=%s\n' "$(json_value "$contents_prefix.layout")"
        printf 'fileExtension=%s\n' "$(json_value "$contents_prefix.fileExtension")"

        if [[ "$kind" == "single-archive" ]]; then
            local archive_prefix="corpora.$index.archive"
            printf 'archive.url=%s\n' "$(json_value "$archive_prefix.url")"
            printf 'archive.fileName=%s\n' "$(json_value "$archive_prefix.fileName")"
            printf 'archive.byteLength=%s\n' "$(json_value "$archive_prefix.byteLength")"
            printf 'archive.md5=%s\n' "$(json_value "$archive_prefix.md5")"
            printf 'archive.checksumSource=%s\n' "$(json_value "$archive_prefix.checksumSource")"
            printf 'maximumExtractedByteLength=%s\n' \
                "$(json_value "$contents_prefix.maximumExtractedByteLength")"
        elif [[ "$kind" == "one-archive-per-image" ]]; then
            local files_prefix="corpora.$index.files"
            local file_count
            local item_index
            file_count="$(json_value "$files_prefix")"
            printf 'indexURL=%s\n' "$(json_value "corpora.$index.indexURL")"
            printf 'checksumURL=%s\n' "$(json_value "corpora.$index.checksumURL")"
            printf 'archiveChecksumStatus=%s\n' \
                "$(json_value "corpora.$index.archiveChecksumStatus")"
            printf 'archiveByteLengthSource=%s\n' \
                "$(json_value "corpora.$index.archiveByteLengthSource")"
            printf 'imageByteLengthSource=%s\n' \
                "$(json_value "corpora.$index.imageByteLengthSource")"
            printf 'archiveMemberPolicy=%s\n' \
                "$(json_value "corpora.$index.archiveMemberPolicy")"

            for ((item_index = 0; item_index < file_count; item_index += 1)); do
                local item_prefix="$files_prefix.$item_index"
                printf 'files.%s.url=%s\n' "$item_index" "$(json_value "$item_prefix.url")"
                printf 'files.%s.archiveFileName=%s\n' \
                    "$item_index" "$(json_value "$item_prefix.archiveFileName")"
                printf 'files.%s.archiveByteLength=%s\n' \
                    "$item_index" "$(json_value "$item_prefix.archiveByteLength")"
                printf 'files.%s.imageFileName=%s\n' \
                    "$item_index" "$(json_value "$item_prefix.imageFileName")"
                printf 'files.%s.imageByteLength=%s\n' \
                    "$item_index" "$(json_value "$item_prefix.imageByteLength")"
                printf 'files.%s.imageMD5=%s\n' \
                    "$item_index" "$(json_value "$item_prefix.imageMD5")"
            done
        else
            fail "unsupported corpus lock kind: $kind"
        fi
    } | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }'
}

write_receipt() {
    local directory="$1"
    local id="$2"
    local digest
    local lock_fingerprint

    digest="$(corpus_digest "$directory")"
    lock_fingerprint="$(corpus_lock_fingerprint "$id")"
    RECEIPT_TEMP="$(/usr/bin/mktemp "$directory/$RECEIPT_NAME.tmp.XXXXXX")"
    printf 'schema=1\ncorpus=%s\nlockSHA256=%s\ncontentSHA256=%s\n' \
        "$id" "$lock_fingerprint" "$digest" > "$RECEIPT_TEMP"
    /bin/mv -f "$RECEIPT_TEMP" "$directory/$RECEIPT_NAME"
    RECEIPT_TEMP=""
}

verify_flat_png_listing() {
    local listing="$1"
    local expected_count="$2"
    local entry
    local actual_count=0
    local sorted_listing="$WORK_DIR/sorted-$(basename "$listing")"

    while IFS= read -r entry || [[ -n "$entry" ]]; do
        [[ "$entry" =~ ^[^/[:cntrl:]]+\.png$ ]] \
            || fail "unexpected ZIP member name: $entry"
        ((actual_count += 1))
    done < "$listing"

    [[ "$actual_count" -eq "$expected_count" ]] \
        || fail "ZIP member count mismatch: expected $expected_count, got $actual_count"

    LC_ALL=C /usr/bin/sort "$listing" > "$sorted_listing"
    if [[ "$(/usr/bin/uniq -d "$sorted_listing" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" != "0" ]]; then
        fail "ZIP contains duplicate member names"
    fi
}

verify_flat_png_directory() {
    local directory="$1"
    local expected_count="$2"
    local allows_receipt="${3:-false}"
    local entry
    local actual_count=0
    local entries

    shopt -s nullglob
    entries=("$directory"/* "$directory"/.[!.]* "$directory"/..?*)
    shopt -u nullglob

    for entry in "${entries[@]}"; do
        if [[ "$allows_receipt" == true && "$(basename "$entry")" == "$RECEIPT_NAME" ]]; then
            [[ -f "$entry" && ! -L "$entry" ]] \
                || fail "corpus receipt is not a regular file: $entry"
            continue
        fi
        [[ -f "$entry" && ! -L "$entry" ]] \
            || fail "extracted corpus contains a non-regular entry: $(basename "$entry")"
        [[ "$(basename "$entry")" =~ ^[^/[:cntrl:]]+\.png$ ]] \
            || fail "extracted corpus contains an unexpected file: $(basename "$entry")"
        ((actual_count += 1))
    done

    [[ "$actual_count" -eq "$expected_count" ]] \
        || fail "extracted file count mismatch: expected $expected_count, got $actual_count"
}

verify_jpeg_ai_listing() {
    local listing="$1"
    local image_name="$2"
    local archive_name="$3"
    local entry
    local image_count=0
    local metadata_count=0
    local directory_count=0

    while IFS= read -r entry || [[ -n "$entry" ]]; do
        case "$entry" in
            "$image_name") ((image_count += 1)) ;;
            "__MACOSX/._$image_name") ((metadata_count += 1)) ;;
            "__MACOSX/") ((directory_count += 1)) ;;
            *) fail "unexpected JPEG AI ZIP member in $archive_name: $entry" ;;
        esac
    done < "$listing"

    [[ "$image_count" -eq 1 ]] \
        || fail "JPEG AI ZIP must contain its target PNG exactly once: $archive_name"
    [[ "$metadata_count" -le 1 && "$directory_count" -le 1 ]] \
        || fail "JPEG AI ZIP repeats macOS metadata members: $archive_name"
}

assert_locked_corpus() {
    local id="$1"
    local index="$2"
    local expected_kind="$3"
    local locked_id
    local locked_kind

    locked_id="$(json_value "corpora.$index.id")"
    locked_kind="$(json_value "corpora.$index.kind")"
    [[ "$locked_id" == "$id" ]] \
        || fail "lock order mismatch: expected $id at index $index, found $locked_id"
    [[ "$locked_kind" == "$expected_kind" ]] \
        || fail "lock kind mismatch for $id: expected $expected_kind, found $locked_kind"
}

assert_flat_png_contents() {
    local index="$1"
    local layout
    local extension

    layout="$(json_value "corpora.$index.contents.layout")"
    extension="$(json_value "corpora.$index.contents.fileExtension")"
    [[ "$layout" == "flat" ]] \
        || fail "unsupported corpus layout at index $index: $layout"
    [[ "$extension" == "png" ]] \
        || fail "unsupported corpus file extension at index $index: $extension"
}

assert_https_url() {
    [[ "$1" == https://* ]] || fail "refusing a non-HTTPS corpus URL: $1"
}

assert_leaf_name() {
    local name="$1"

    [[ -n "$name" && "$name" != */* && "$name" != "." && "$name" != ".." ]] \
        || fail "invalid corpus file name in lock: $name"
}

verify_jpeg_ai_images() {
    local directory="$1"
    local index="2"
    local files_prefix="corpora.$index.files"
    local expected_count
    local item_index

    expected_count="$(json_value "corpora.$index.contents.fileCount")"
    verify_flat_png_directory "$directory" "$expected_count" true

    for ((item_index = 0; item_index < expected_count; item_index += 1)); do
        local item_prefix="$files_prefix.$item_index"
        local image_name
        local expected_bytes
        local expected_md5
        local image

        image_name="$(json_value "$item_prefix.imageFileName")"
        expected_bytes="$(json_value "$item_prefix.imageByteLength")"
        expected_md5="$(json_value "$item_prefix.imageMD5")"
        image="$directory/$image_name"
        assert_leaf_name "$image_name"
        [[ -f "$image" && ! -L "$image" ]] || fail "missing JPEG AI image: $image_name"
        verify_byte_length "$image" "$expected_bytes"
        verify_md5 "$image" "$expected_md5"
    done
}

verify_installed_corpus() {
    local id="$1"
    local directory="$DATA_ROOT/$id"
    local index
    local expected_count
    local receipt="$directory/$RECEIPT_NAME"
    local current_lock_fingerprint
    local expected_digest
    local actual_digest
    local receipt_is_current=false

    index="$(corpus_index "$id")"
    expected_count="$(json_value "corpora.$index.contents.fileCount")"
    [[ -d "$directory" && ! -L "$directory" ]] \
        || fail "existing corpus is not a regular directory: $directory"
    current_lock_fingerprint="$(corpus_lock_fingerprint "$id")"

    if [[ -f "$receipt" && ! -L "$receipt" ]]; then
        if [[ "$(receipt_value "$receipt" schema)" == "1"
            && "$(receipt_value "$receipt" corpus)" == "$id"
            && "$(receipt_value "$receipt" lockSHA256)" == "$current_lock_fingerprint"
        ]]; then
            receipt_is_current=true
        fi
    fi

    if [[ "$receipt_is_current" != true ]]; then
        if [[ "$id" == "jpeg-ai-cfe" ]]; then
            verify_jpeg_ai_images "$directory"
            write_receipt "$directory" "$id"
        else
            fail "existing corpus is not verified against the current lock; move it aside and fetch again: $directory"
        fi
    fi

    verify_flat_png_directory "$directory" "$expected_count" true
    [[ -f "$receipt" && ! -L "$receipt" ]] \
        || fail "invalid corpus receipt: $receipt"
    [[ "$(receipt_value "$receipt" schema)" == "1" ]] \
        || fail "unsupported corpus receipt: $receipt"
    [[ "$(receipt_value "$receipt" corpus)" == "$id" ]] \
        || fail "corpus receipt identity mismatch: $receipt"
    [[ "$(receipt_value "$receipt" lockSHA256)" == "$current_lock_fingerprint" ]] \
        || fail "corpus receipt does not match the current manifest lock: $receipt"
    expected_digest="$(receipt_value "$receipt" contentSHA256)"
    [[ "$expected_digest" =~ ^[0-9a-f]{64}$ ]] \
        || fail "invalid corpus digest in receipt: $receipt"
    actual_digest="$(corpus_digest "$directory")"
    [[ "$actual_digest" == "$expected_digest" ]] \
        || fail "installed corpus content does not match its receipt: $directory"
    printf 'Already ready: %s\n' "$directory"
}

fetch_clic() {
    local id="$1"
    local index="$2"
    local archive_prefix="corpora.$index.archive"
    local contents_prefix="corpora.$index.contents"
    local url
    local archive_name
    local expected_bytes
    local expected_md5
    local expected_count
    local maximum_extracted_bytes
    local archive
    local listing
    local extraction

    assert_locked_corpus "$id" "$index" "single-archive"
    assert_flat_png_contents "$index"
    url="$(json_value "$archive_prefix.url")"
    archive_name="$(json_value "$archive_prefix.fileName")"
    expected_bytes="$(json_value "$archive_prefix.byteLength")"
    expected_md5="$(json_value "$archive_prefix.md5")"
    expected_count="$(json_value "$contents_prefix.fileCount")"
    maximum_extracted_bytes="$(json_value "$contents_prefix.maximumExtractedByteLength")"
    archive="$WORK_DIR/$archive_name"
    listing="$WORK_DIR/$id.listing"
    extraction="$WORK_DIR/$id"

    assert_https_url "$url"
    assert_leaf_name "$archive_name"

    download "$url" "$archive" "$expected_bytes"
    verify_md5 "$archive" "$expected_md5"

    /usr/bin/unzip -Z -1 "$archive" > "$listing" \
        || fail "could not read ZIP directory: $archive_name"
    verify_flat_png_listing "$listing" "$expected_count"
    verify_archive_expansion_limit "$archive" "$listing" "$maximum_extracted_bytes"

    /bin/mkdir "$extraction"
    /usr/bin/unzip -q "$archive" -d "$extraction" \
        || fail "could not extract ZIP: $archive_name"
    verify_flat_png_directory "$extraction" "$expected_count"
    [[ "$(directory_byte_length "$extraction")" -le "$maximum_extracted_bytes" ]] \
        || fail "extracted corpus exceeds its safety limit: $id"
    printf 'Verified: %s\n' "$id"
}

fetch_jpeg_ai() {
    local id="jpeg-ai-cfe"
    local index="2"
    local files_prefix="corpora.$index.files"
    local expected_count
    local locked_file_count
    local extraction="$WORK_DIR/$id"
    local item_index

    assert_locked_corpus "$id" "$index" "one-archive-per-image"
    assert_flat_png_contents "$index"
    [[ "$(json_value "corpora.$index.archiveChecksumStatus")" == "not-published-upstream" ]] \
        || fail "JPEG AI archive checksum provenance changed; review the lock before fetching"
    [[ "$(json_value "corpora.$index.archiveMemberPolicy")" == "image-with-optional-macos-metadata" ]] \
        || fail "JPEG AI archive member policy changed; review the lock before fetching"
    expected_count="$(json_value "corpora.$index.contents.fileCount")"
    locked_file_count="$(json_value "$files_prefix")"
    [[ "$locked_file_count" == "$expected_count" ]] \
        || fail "JPEG AI lock count mismatch: contents says $expected_count, files has $locked_file_count"

    /bin/mkdir "$extraction"
    for ((item_index = 0; item_index < locked_file_count; item_index += 1)); do
        local item_prefix="$files_prefix.$item_index"
        local url
        local archive_name
        local expected_archive_bytes
        local image_name
        local expected_image_bytes
        local expected_md5
        local archive
        local listing
        local image

        url="$(json_value "$item_prefix.url")"
        archive_name="$(json_value "$item_prefix.archiveFileName")"
        expected_archive_bytes="$(json_value "$item_prefix.archiveByteLength")"
        image_name="$(json_value "$item_prefix.imageFileName")"
        expected_image_bytes="$(json_value "$item_prefix.imageByteLength")"
        expected_md5="$(json_value "$item_prefix.imageMD5")"
        archive="$WORK_DIR/$archive_name"
        listing="$WORK_DIR/$archive_name.listing"
        image="$extraction/$image_name"

        assert_https_url "$url"
        assert_leaf_name "$archive_name"
        assert_leaf_name "$image_name"
        [[ "${url##*/}" == "$archive_name" ]] \
            || fail "JPEG AI URL and archive name disagree at item $item_index"
        [[ "$archive_name" == "$image_name.zip" ]] \
            || fail "JPEG AI archive and image name disagree at item $item_index"

        download "$url" "$archive" "$expected_archive_bytes"
        /usr/bin/unzip -Z -1 "$archive" > "$listing" \
            || fail "could not read ZIP directory: $archive_name"
        verify_jpeg_ai_listing "$listing" "$image_name" "$archive_name"
        [[ "$(zip_member_uncompressed_size "$archive" "$image_name")" == "$expected_image_bytes" ]] \
            || fail "ZIP member size mismatch for $image_name"

        /usr/bin/unzip -p "$archive" "$image_name" \
            | /usr/bin/head -c "$((expected_image_bytes + 1))" > "$image" \
            || fail "could not extract $image_name"
        [[ -s "$image" ]] || fail "extracted an empty image: $image_name"
        verify_byte_length "$image" "$expected_image_bytes"
        verify_md5 "$image" "$expected_md5"
        /bin/rm -f -- "$archive" "$listing"
    done

    verify_flat_png_directory "$extraction" "$expected_count"
    printf 'Verified: %s\n' "$id"
}

if [[ "$#" -eq 0 ]]; then
    usage >&2
    exit 64
fi

if [[ "$#" -eq 1 && "$1" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "$#" -eq 1 && "$1" == "--list" ]]; then
    printf '%s\n' clic-professional-valid clic-mobile-valid jpeg-ai-cfe
    exit 0
fi

declare -a SELECTED=()
for argument in "$@"; do
    case "$argument" in
        all)
            add_selection clic-professional-valid
            add_selection clic-mobile-valid
            add_selection jpeg-ai-cfe
            ;;
        --*) fail "unknown option: $argument" ;;
        *) add_selection "$argument" ;;
    esac
done

require_command curl
require_command awk
require_command head
require_command md5
require_command plutil
require_command shasum
require_command unzip
require_command zipinfo
/usr/bin/plutil -convert xml1 -o /dev/null "$MANIFEST_FILE" \
    || fail "invalid manifest file: $MANIFEST_FILE"
/usr/bin/plutil -convert xml1 -o /dev/null "$LOCK_FILE" \
    || fail "invalid lock file: $LOCK_FILE"
[[ "$(manifest_value schemaVersion)" == "1" && "$(json_value schemaVersion)" == "1" ]] \
    || fail "unsupported corpus manifest schema"
[[ "$(manifest_value lockFile)" == "$(basename "$LOCK_FILE")" ]] \
    || fail "manifest points to an unexpected lock file"

for manifest_index in 0 1 2; do
    manifest_id="$(manifest_value "corpora.$manifest_index.id")"
    locked_id="$(json_value "corpora.$manifest_index.id")"
    [[ "$manifest_id" == "$locked_id" ]] \
        || fail "manifest and lock corpus IDs disagree at index $manifest_index"
done

[[ ! -L "$DATA_ROOT" ]] || fail "data root must not be a symbolic link: $DATA_ROOT"
/bin/mkdir -p "$DATA_ROOT"
[[ -d "$DATA_ROOT" ]] || fail "data root is not a directory: $DATA_ROOT"

if ! /bin/mkdir "$FETCH_LOCK" 2>/dev/null; then
    fail "another corpus fetch is active, or a stale lock needs removal: $FETCH_LOCK"
fi
LOCK_HELD=true

declare -a TO_FETCH=()
for corpus in "${SELECTED[@]}"; do
    if [[ -e "$DATA_ROOT/$corpus" || -L "$DATA_ROOT/$corpus" ]]; then
        verify_installed_corpus "$corpus"
    else
        TO_FETCH+=("$corpus")
    fi
done

[[ "${#TO_FETCH[@]}" -gt 0 ]] || exit 0
WORK_DIR="$(/usr/bin/mktemp -d "$DATA_ROOT/.fetch.XXXXXX")"

for corpus in "${TO_FETCH[@]}"; do
    case "$corpus" in
        clic-professional-valid) fetch_clic "$corpus" "0" ;;
        clic-mobile-valid) fetch_clic "$corpus" "1" ;;
        jpeg-ai-cfe) fetch_jpeg_ai ;;
    esac
done

for corpus in "${TO_FETCH[@]}"; do
    extraction="$WORK_DIR/$corpus"
    destination="$DATA_ROOT/$corpus"
    [[ -d "$extraction" && ! -L "$extraction" ]] \
        || fail "verified corpus staging directory is missing: $extraction"
    [[ ! -e "$destination" && ! -L "$destination" ]] \
        || fail "destination appeared while the fetch lock was held: $destination"
    write_receipt "$extraction" "$corpus"
    /bin/mv "$extraction" "$destination"
    printf 'Ready: %s\n' "$destination"
done
