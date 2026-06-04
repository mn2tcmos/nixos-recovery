#!/usr/bin/env bash
# bootstrap.sh — doomsday entry point (public nixos-recovery)
#   화면 출력 = ASCII 영어 (ISO TTY 호환). 주석(#) = 한글.
#
# minimal ISO 에서:
#   sudo -i
#   curl -fLO https://raw.githubusercontent.com/mn2tcosm/nixos-recovery/main/bootstrap.sh
#   bash bootstrap.sh
#
# 하는 일:
#   - keys.tar.gpg 받아 gpg 복호 -> /root/.ssh (git/borg/ghost keys + config + known_hosts, 600)
#   - nixos-config 를 RAM(/root)에 clone -> setup.sh 메뉴(툴박스) 실행
#   (그 메뉴에서 fresh/keep-p3/개별작업 골라 진행. 재부팅·borgbase 복원은 그 후 수동.)
set -euo pipefail

# ISO 에 없을 수 있는 도구를 nix shell 로 채워 자기 자신을 재실행
if ! command -v git >/dev/null || ! command -v gpg >/dev/null || ! command -v sgdisk >/dev/null; then
  echo "preparing tools (git/gnupg/gptfdisk/dosfstools)..."
  exec nix shell nixpkgs#git nixpkgs#gnupg nixpkgs#gptfdisk nixpkgs#dosfstools \
       nixpkgs#e2fsprogs nixpkgs#parted --command bash "$0" "$@"
fi

RAW="https://raw.githubusercontent.com/mn2tcosm/nixos-recovery/main"
REPO_SSH="git@github.com:mn2tcosm/nixos-config"

echo "=== recovery bootstrap ==="
cd /root
echo "1) fetching key bundle..."
curl -fLO "$RAW/keys.tar.gpg"
echo "2) decrypt (enter gpg passphrase):"
gpg -d keys.tar.gpg | tar -xz
mkdir -p /root/.ssh
cp git_ed25519 borg_ed25519 ghost_ed25519 config known_hosts /root/.ssh/
chmod 700 /root/.ssh; chmod 600 /root/.ssh/*
echo "   keys installed -> /root/.ssh"

echo "3) cloning nixos-config to RAM..."
rm -rf /root/nixos-config
git clone "$REPO_SSH" /root/nixos-config

echo "4) launching toolbox menu (pick disk + action there)..."
exec bash /root/nixos-config/setup.sh
