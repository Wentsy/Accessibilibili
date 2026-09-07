#!/bin/sh
set -eu

SRC_DIR="$1"
SYMLINKS_DIR="$2"

relpath() {
    [ $# -ge 1 ] && [ $# -le 2 ] || return 1
    current="${2:+"$1"}"
    target="${2:-"$1"}"
    [ "$target" != . ] || target=/
    target="/${target##/}"
    [ "$current" != . ] || current=/
    current="${current:="/"}"
    current="/${current##/}"
    appendix="${target##/}"
    relative=''
    while appendix="${target#"$current"/}" \
        && [ "$current" != '/' ] \
        && [ "$appendix" = "$target" ]; do
        if [ "$current" = "$appendix" ]; then
            relative="${relative:-.}"
            echo "${relative#/}"
            return 0
        fi
        current="${current%/*}"
        relative="$relative${relative:+/}.."
    done
    relative="$relative${relative:+${appendix:+/}}${appendix#/}"
    echo "$relative"
}

find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r src; do
    slug="$(basename "$src")"
    name="$(echo "$slug" | cut -d '-' -f 1,3)"
    src_relative="$(relpath "$SYMLINKS_DIR" "$src")"
    ln -s "$src_relative" "$SYMLINKS_DIR/$name"
done
