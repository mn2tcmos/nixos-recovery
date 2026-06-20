#!/usr/bin/env bash
# bootstrap.sh — doomsday entry point (public nixos-recovery)
#   화면 출력 = ASCII 영어 (ISO TTY 호환). 주석(#) = 한글.
#
# minimal ISO 에서 (sudo -i 후) — bootstrap.sh 받기까지 github 독립(미러 3사):
#
#  [A] 복붙 한 방 — 3곳 자동 시도(github -> codeberg -> gitlab):
#    for b in \
#      https://raw.githubusercontent.com/mn2tcmos/nixos-recovery/main \
#      https://codeberg.org/mn2tcmos/nixos-recovery/raw/branch/main \
#      https://gitlab.com/mn2tcmos/nixos-recovery/-/raw/main ; do \
#      curl -fLO "$b/bootstrap.sh" && break; done && bash bootstrap.sh
#
#  [B] 수동 — github 막혔으면 아래 중 한 줄만 받고 -> bash bootstrap.sh:
#      https://raw.githubusercontent.com/mn2tcmos/nixos-recovery/main/bootstrap.sh
#      https://codeberg.org/mn2tcmos/nixos-recovery/raw/branch/main/bootstrap.sh
#      https://gitlab.com/mn2tcmos/nixos-recovery/-/raw/main/bootstrap.sh
#
# 하는 일:
#   - (minimal ISO 대비) nix 실험기능 켜고, 필요한 도구를 nix shell 로 채워 자기 재실행
#   - auth.tar.gpg 받아 gpg 복호(headless=loopback) -> /root/.ssh (git/borg/ghost + config + known_hosts, 600)
#   - nixos-config 를 RAM(/root)에 clone -> setup.sh 메뉴(툴박스) 실행
set -euo pipefail

# minimal ISO 는 nix-command/flakes 가 기본 꺼져 있음 -> 켜고 시작
# (export 라 재실행된 자신 + 이후 nixos-install --flake 까지 상속됨)
export NIX_CONFIG="experimental-features = nix-command flakes"

# ISO 에 없을 수 있는 도구를 nix shell 로 채워 자기 자신을 재실행
if ! command -v git >/dev/null || ! command -v gpg >/dev/null || ! command -v sgdisk >/dev/null \
   || ! command -v mkfs.btrfs >/dev/null || ! command -v rsync >/dev/null; then
  echo "preparing tools (git/gnupg/gptfdisk/btrfs-progs/rsync/...)..."
  exec nix shell nixpkgs#git nixpkgs#gnupg nixpkgs#gptfdisk nixpkgs#dosfstools \
       nixpkgs#e2fsprogs nixpkgs#btrfs-progs nixpkgs#parted nixpkgs#rsync \
       --command bash "$0" "$@"
fi

# 미러: GitHub 우선, 죽으면 Codeberg → GitLab 로 폴백(단일 회사 의존 차단).
#   nixos-recovery(공개) = auth.tar.gpg 를 raw(https) 로 받음.
#   nixos-config(비공개) = ssh 로 clone (같은 git_ed25519 가 3곳 다 등록돼 있음).
RAW_BASES=(
  "https://raw.githubusercontent.com/mn2tcmos/nixos-recovery/main"
  "https://codeberg.org/mn2tcmos/nixos-recovery/raw/branch/main"
  "https://gitlab.com/mn2tcmos/nixos-recovery/-/raw/main"
)
REPO_SSHS=(
  "git@github.com:mn2tcmos/nixos-config"
  "git@codeberg.org:mn2tcmos/nixos-config"
  "git@gitlab.com:mn2tcmos/nixos-config"
)

echo "=== recovery bootstrap ==="
cd /root
echo "1) fetching key bundle (mirror fallback)..."
ok=
for b in "${RAW_BASES[@]}"; do
  echo "   try: $b"
  if curl -fLO "$b/auth.tar.gpg"; then ok=1; echo "   ok"; break; fi
done
[ -n "$ok" ] || { echo "ERROR: auth.tar.gpg fetch failed on ALL mirrors"; exit 1; }

echo "2) decrypt (enter gpg passphrase at the prompt):"
# 헤드리스 ISO 엔 pinentry 창이 없음 -> loopback 으로 터미널에서 직접 입력
mkdir -p /root/.gnupg && chmod 700 /root/.gnupg
grep -q allow-loopback-pinentry /root/.gnupg/gpg-agent.conf 2>/dev/null \
  || echo allow-loopback-pinentry >> /root/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent 2>/dev/null || true
gpg --pinentry-mode loopback -d auth.tar.gpg | tar -xz

mkdir -p /root/.ssh
cp git_ed25519 borg_ed25519 config known_hosts /root/.ssh/
chmod 700 /root/.ssh; chmod 600 /root/.ssh/*
echo "   keys installed -> /root/.ssh"

echo "3) cloning nixos-config to RAM (mirror fallback)..."
rm -rf /root/nixos-config
# 3곳 모두 같은 git_ed25519 등록됨 → 키 명시 + 호스트키 자동수락으로 어느 미러든 clone.
export GIT_SSH_COMMAND="ssh -i /root/.ssh/git_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
ok=
for u in "${REPO_SSHS[@]}"; do
  echo "   try: $u"
  if git clone "$u" /root/nixos-config; then ok=1; break; fi
  rm -rf /root/nixos-config
done
[ -n "$ok" ] || { echo "ERROR: nixos-config clone failed on ALL mirrors"; exit 1; }

echo "4) launching toolbox menu (pick disk + action there)..."
exec bash /root/nixos-config/setup.sh
