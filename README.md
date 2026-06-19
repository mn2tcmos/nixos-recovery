# nixos-recovery

최악의 상황(삼성·인텔 NVMe 동시 사망, 새 디스크 1개, 주변에 도와줄 컴퓨터 없음)에서
내 NixOS 환경을 맨바닥부터 되살리기 위한 **부트스트랩 키트**.

- `bootstrap.sh` — **도움즈데이 진입점.** ISO에서 이거 한 줄 받아 실행하면
  키 복호·설치 → private `nixos-config` clone → `setup.sh` 메뉴까지 **자동**.
- `keys.tar.gpg` — ssh 개인키들 + borg 암호 + ghost VPN(wg) 설정을 **AES256으로 암호화**한 묶음.
  GitHub 비밀스캔은 평문만 잡으므로 암호화된 이 blob 은 공개 repo에 둬도 안전.
  **단, 암호(passphrase)를 분실하면 영구히 못 엽니다.**
- `make-bundle.sh` — 이 번들을 만든/다시 만드는 스크립트(비밀 없음).

> 실제 설치/복구 작업 메뉴인 **`setup.sh`** 는 이 repo가 아니라 private `nixos-config`에 있다.
> bootstrap.sh 가 그걸 clone 해서 실행한다.

## 들어있는 것 (keys.tar.gpg)
- `git_ed25519` (+.pub) — private repo `nixos-config` clone 용 (설치 단계)
- `borg_ed25519` (+.pub) — borgbase **서버 접속** 열쇠 (백업 안에서 못 꺼냄=순환이라 바깥에 보관)
- `borg-passphrase.txt` — borgbase **데이터 복호** 암호 (repokey-blake2)
- `config` — ssh 매핑(github→git키, *.repo.borgbase.com→borg키)
- `known_hosts` — github·borgbase 서버 신분증(미리 넣어둬서 ssh-keyscan 불필요)
- `wg/ghost.conf` — ghost VPN(WireGuard) 설정 (borg는 auth 제외라 여기 보관)

> borg는 접속 키(ssh) + 데이터 암호(passphrase) **둘 다** 필요 — 성격이 다른 별개의 비밀.
> 둘 다 번들에 넣었으니, 기억할 건 이 번들을 여는 **gpg 암호 하나뿐**.

## 복호화 (gpg 있는 평소 시스템)
```sh
gpg -d keys.tar.gpg | tar -xz
```

## 최악 시나리오 부트스트랩 (NixOS minimal ISO)
**핵심: bootstrap.sh 받아 실행.** 나머지(키 복호·설치·메뉴)는 `bootstrap.sh` 가 알아서 한다.
GitHub·Codeberg·GitLab **3사 미러** → 받는 단계까지 한 회사에 안 묶임.

1. minimal ISO 부팅 → 네트워크 연결 → `sudo -i` (root 로)
2. 진입 — 둘 중 하나:

   **[A] 복붙 한 방 (3곳 자동 시도: github→codeberg→gitlab):**
   ```sh
   for b in \
     https://raw.githubusercontent.com/mn2tcmos/nixos-recovery/main \
     https://codeberg.org/mn2tcmos/nixos-recovery/raw/branch/main \
     https://gitlab.com/mn2tcmos/nixos-recovery/-/raw/main ; do \
     curl -fLO "$b/bootstrap.sh" && break; done && bash bootstrap.sh
   ```
   **[B] 손으로 — github 막혔으면 아래 중 한 줄만 받고 `bash bootstrap.sh`:**
   ```sh
   curl -fLO https://raw.githubusercontent.com/mn2tcmos/nixos-recovery/main/bootstrap.sh
   curl -fLO https://codeberg.org/mn2tcmos/nixos-recovery/raw/branch/main/bootstrap.sh
   curl -fLO https://gitlab.com/mn2tcmos/nixos-recovery/-/raw/main/bootstrap.sh
   ```
3. 진행 중 **gpg 암호**를 한 번 물어본다(번들 복호). 그게 기억할 유일한 비밀.
4. 자동으로 `setup.sh` 툴박스 메뉴가 뜬다. 거기서:
   - 디스크 선택 (`d`)
   - **새 디스크 / 도움즈데이** → `7) FRESH` (파티션→포맷→마운트→clone→설치)
   - **데이터 살리는 재설치** → `8) RESET` (root(@)만 재생성, 데이터 서브볼륨 보존)
5. 설치 끝에 **mn2tcmos 로그인 비번 입력**(=첫 부팅 비번) → machine-id도 자동 시딩.
   재부팅 → **mn2tcmos 으로 바로 로그인** (root는 잠김=리눅스 표준; 예전 "Starting D-Bus..." 브릭도 자동해결).
6. **데이터 복원** (fresh 인 경우) → `restore.sh`(borg CLI, 아래 참고) → `/mnt/mn2`

### bootstrap.sh 가 자동으로 하는 일 (내부)
1. 도구(git/gnupg/gptfdisk/dosfstools/e2fsprogs/parted)를 `nix shell` 로 채우고 자기 재실행
2. `keys.tar.gpg` 내려받아 gpg 복호 → ssh 키를 `/root/.ssh` 에 설치(600)
3. private `nixos-config` 를 RAM(`/root`)에 `git clone`
4. `setup.sh` 툴박스 메뉴 실행

### bootstrap.sh 가 안 되면 (수동 폴백)
위 4단계를 손으로 (github 막혔으면 raw URL 베이스를 위 [A]의 codeberg/gitlab 로 교체):
```sh
cd /root
curl -LO https://raw.githubusercontent.com/mn2tcmos/nixos-recovery/main/keys.tar.gpg
nix run nixpkgs#gnupg -- -d keys.tar.gpg | tar -xz      # ISO엔 gpg 없음
mkdir -p /root/.ssh
cp git_ed25519 borg_ed25519 config known_hosts /root/.ssh/
chmod 700 /root/.ssh; chmod 600 /root/.ssh/*
git clone git@github.com:mn2tcmos/nixos-config /root/nixos-config
bash /root/nixos-config/setup.sh
```
> "REMOTE HOST IDENTIFICATION HAS CHANGED" 뜨면(서버 키 교체 등):
> `ssh-keygen -R github.com -f /root/.ssh/known_hosts && ssh-keyscan github.com >> /root/.ssh/known_hosts`

## 데이터 복원 (borgbase, 설치 후)
fresh 설치라 state 가 비어있으면 borgbase 에서 복원. **`restore.sh`**(borg CLI, **TTY에서 동작** — 데스크탑 불필요):
```sh
sudo BORG_REPO=ssh://exitvb8k@exitvb8k.repo.borgbase.com/./repo bash /mnt/mn2/nixos-config/restore.sh
```
(borg passphrase = 번들에서 푼 borg 암호 — 프롬프트에 1번 입력. borg ssh 키는 설치 때 `/root/.ssh`로 복사돼 있음.)

> 순서가 중요: **설치(껍데기) → 복원(데이터)**. 거꾸로 하면 포맷이 데이터를 밀어버림.
> 상세 절차·시스템 구조는 private `nixos-config/README.md` 참고.
