#!/usr/bin/env bash
# How slow are synchronous writes on this runner right now? (300 x 4 KiB, each one synced)
f=$(sudo mktemp /var/tmp/fsync-bench.XXXXXX)
echo "fsync bench, $(awk '{printf "%d", $1}' /proc/uptime)s after boot: $(sudo dd if=/dev/zero of="$f" bs=4k count=300 oflag=dsync 2>&1 | tail -1)"
sudo rm -f "$f"
