#!/usr/bin/env bash
# Copies what apt downloaded in this job to ~/apt-cache, which actions/cache saves.
set -euo pipefail
C="${APT_CACHE_DIR:?}"
rm -rf ~/apt-cache && mkdir -p ~/apt-cache
sudo cp -a "$C/." ~/apt-cache/
sudo chown -R "$USER" ~/apt-cache
rm -rf ~/apt-cache/*/partial ~/apt-cache/*/lock
echo "apt cache: $(find ~/apt-cache/archives -name '*.deb' | wc -l) packages, $(du -sh ~/apt-cache | cut -f1)"
