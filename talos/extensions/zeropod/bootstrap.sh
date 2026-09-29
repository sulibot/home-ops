#!/bin/sh
set -eu

target=/host
test -d "$target"
mkdir -p "$target/bin" "$target/lib" "$target/etc"
for directory in bin lib; do
  for source in "/payload/$directory/"*; do
    [ -f "$source" ] || continue
    destination="$target/$directory/$(basename "$source")"
    staging="$destination.new.$$"
    cp -p "$source" "$staging"
    mv -f "$staging" "$destination"
  done
done
if [ ! -e "$target/etc/shim.json" ]; then
  cp /payload/etc/shim.json "$target/etc/shim.json"
fi
if [ ! -e "$target/etc/criu-default.conf" ]; then
  cp /payload/etc/criu-default.conf "$target/etc/criu-default.conf"
fi
test -x "$target/bin/containerd-shim-zeropod-v2"
test -x "$target/bin/criu"
test -x "$target/bin/tar"
test -x "$target/bin/gzip"
