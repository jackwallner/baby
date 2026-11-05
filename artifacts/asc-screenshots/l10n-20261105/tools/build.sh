#!/bin/sh
set -eu
cd "$(dirname "$0")"
export MACOSX_DEPLOYMENT_TARGET=12.0
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/l10n-build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
for tool in headline ocr; do
    swiftc -O "$tool.swift" -o "$build_dir/$tool"
    mv "$build_dir/$tool" "$tool"
done
printf 'built headline ocr\n'
