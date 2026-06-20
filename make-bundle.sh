#!/usr/bin/env bash
# 복구 번들 생성기 — ssh 개인키 + SSH 호스트키 + borg암호 + wg설정을 AES256으로 암호화해서 auth.tar.gpg 생성.
#   (백업은 borgbackup CLI=ai-borg 가 담당. 옛 vorta 프로필 참조는 제거됨 2026-06.)
#
#   - 평문 묶음은 tmpfs(RAM, /run/user/1000)에서만 만들고 끝나면 즉시 삭제 → 디스크에 평문 안 남음.
#   - 암호(passphrase)는 실행할 때 직접 입력. 절대 파일/스크립트에 평문으로 박지 말 것.
#   - 이 스크립트 자체엔 비밀이 없으니 공개 repo에 커밋해도 됨(번들을 어떻게 만들었는지 기록용).
set -euo pipefail

SSH=/mnt/mn2/state/users/mn2tcmos/auth/ssh
OUT="$(dirname "$(realpath "$0")")/auth.tar.gpg"

STG="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/recovery.XXXXXX")"
trap 'rm -rf "$STG"' EXIT

# 복구 후엔 개인키만 복원되고 .pub 이 빠질 수 있다(완전포맷서 겪음) → 개인키에서 자동 재생성.
#   (.pub 은 개인키로부터 항상 도출 가능 — ssh-keygen -y. 없으면 만들어 두고 진행.)
for k in git_ed25519 borg_ed25519; do
  [ -f "$SSH/$k.pub" ] || { ssh-keygen -y -f "$SSH/$k" > "$SSH/$k.pub"; chmod 644 "$SSH/$k.pub"; echo "[fix] $k.pub 재생성"; }
done

# git키=설치용, borg키=borgbase 접속 열쇠(백업 안에서 못 꺼냄=순환), config=ssh 매핑.
cp "$SSH"/{git_ed25519,git_ed25519.pub,borg_ed25519,borg_ed25519.pub,config,known_hosts} "$STG"/

# ghost wg 설정(VPN 비밀) — borg 는 auth 제외(순환방지)라 백업 누락 → 여기 번들로 챙김.
#   복구 시 bootstrap 의 tar -xz 가 /root 에 wg/ghost.conf 로 풀어줌 → auth/wg/ 로 옮기면 됨.
mkdir -p "$STG/wg"
cp /mnt/mn2/state/users/mn2tcmos/auth/wg/ghost.conf "$STG/wg/ghost.conf"

# SSH 호스트키 — 데스크톱 SSH "지문"을 재설치해도 고정(원격 connectbot 이 "호스트키 바뀜"으로
#   막히는 일 차단). /persist/etc/ssh 는 root 600 이라 sudo 로 읽어 사용자소유 STG 로 복사(tar 가 읽게).
#   복구 시 setup.sh seed_install 이 이걸 /persist/etc/ssh 로 되돌려 심음 → 지문 영구 동일.
mkdir -p "$STG/ssh_host"
for f in ssh_host_ed25519_key ssh_host_ed25519_key.pub ssh_host_rsa_key ssh_host_rsa_key.pub; do
  sudo cat "/persist/etc/ssh/$f" > "$STG/ssh_host/$f"
done
chmod 600 "$STG/ssh_host/"*_key; chmod 644 "$STG/ssh_host/"*.pub

# borgbase 데이터 복호용 passphrase 를 번들에 포함 → 평소엔 gpg 암호 하나만 기억하면 됨.
# (borgbase 는 repokey-blake2 라 'borg 키 + 이 암호' 둘 다 있어야 백업 복호 가능)
# ai-borg 가 쓰는 저장 비번 파일이 있으면 그대로 사용(재입력 오타 방지 = 단일 출처). 없으면 직접 입력.
BORG_PASSFILE=/mnt/mn2/state/users/mn2tcmos/auth/borg_passphrase
if [ -s "$BORG_PASSFILE" ]; then
  cp "$BORG_PASSFILE" "$STG/borg-passphrase.txt"
  echo "borg passphrase: 저장파일에서 자동 포함 ($BORG_PASSFILE)"
else
  printf 'borgbase passphrase 입력(화면에 안 보임, 없으면 그냥 Enter): '
  read -rs BORG_PASS; echo
  [ -n "$BORG_PASS" ] && printf '%s' "$BORG_PASS" > "$STG/borg-passphrase.txt"
  unset BORG_PASS
fi

echo "묶을 내용:"; ls -1 "$STG"

# gpg 암호: bash 가 가려서(-s) 입력받아 fd 로 전달 → 터미널 에코 X, ps/디스크 노출 X.
#   (pinentry 가 세션마다 안 잡혀 평문 에코되던 문제 차단. 분실하면 번들 영구히 못 엽니다.)
printf 'auth 번들 암호 입력(화면에 안 보임): '; read -rs GPG_PASS; echo
printf 'auth 번들 암호 재입력(확인): ';          read -rs GPG_PASS2; echo
[ -n "$GPG_PASS" ] || { echo "빈 암호 거부"; exit 1; }
[ "$GPG_PASS" = "$GPG_PASS2" ] || { echo "두 입력이 다름 — 중단(번들 안 만듦)"; exit 1; }

tar -czf - -C "$STG" . | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
    --symmetric --cipher-algo AES256 -o "$OUT" 3<<<"$GPG_PASS"
unset GPG_PASS GPG_PASS2
echo "생성됨: $OUT"
