#!/usr/bin/env bash
#
# Canon EOS как веб-камера на Linux — установщик.
#
#   curl -fsSL https://raw.githubusercontent.com/michaelyosta/canon-eos-webcam-linux/main/install.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/michaelyosta/canon-eos-webcam-linux/main/install.sh | sudo bash -s -- --crop
#   curl -fsSL https://raw.githubusercontent.com/michaelyosta/canon-eos-webcam-linux/main/install.sh | sudo bash -s -- --uninstall
#
# Ставит: зависимости, webcamize (из исходников), systemd-службу.
# Ничего не удаляет и не трогает ваши файлы, кроме своих собственных.

set -euo pipefail

REPO="${REPO:-michaelyosta/canon-eos-webcam-linux}"
BRANCH="${BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

UNIT="canon-webcam.service"
FB_UNIT="canon-webcam-fallback.service"
UNIT_DIR="/etc/systemd/system"
FB_BIN="/usr/local/bin/canon-webcam-fallback"

MODE="webcamize"
CROP=""

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=""; G=""; Y=""; R=""; N=""
fi

step() { printf '\n%s▸ %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%s✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

usage() {
  cat <<EOF
${B}Canon EOS как веб-камера на Linux${N}

  bash install.sh [опции]

Опции:
  (без опций)    установить webcamize + службу (рекомендуется)
  --crop         fallback-демон с кадрированием в 16:9 (1280x720)
  --fallback     только fallback-демон (gphoto2 + ffmpeg), без webcamize
  --uninstall    удалить службы и файлы
  -h, --help     эта справка

Переменные окружения:
  REPO=<owner/repo>   другой репозиторий-источник
  BRANCH=<branch>     другая ветка (по умолчанию main)
  NO_COLOR=1          без цветного вывода
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --crop)      CROP="1280:720"; MODE="fallback" ;;
    --fallback)  MODE="fallback" ;;
    --uninstall) MODE="uninstall" ;;
    -h|--help)   usage; exit 0 ;;
    *)           printf 'Неизвестная опция: %s\n\n' "$1"; usage; exit 1 ;;
  esac
  shift
done

[ "$(id -u)" -eq 0 ] || die "Нужны права root. Запустите через sudo:
    curl -fsSL ${RAW}/install.sh | sudo bash"

detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v pacman >/dev/null 2>&1; then echo pacman
  else echo unknown
  fi
}

install_deps() {
  local pm; pm=$(detect_pm)
  step "Зависимости (пакетный менеджер: $pm)"
  case "$pm" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y --no-install-recommends \
        build-essential pkg-config git curl ca-certificates kmod \
        libgphoto2-dev libavutil-dev libavcodec-dev libavformat-dev libswscale-dev libkmod-dev \
        v4l2loopback-dkms v4l2loopback-utils v4l-utils gphoto2 ffmpeg
      apt-get install -y --no-install-recommends "linux-headers-$(uname -r)" \
        || warn "нет пакета linux-headers-$(uname -r) — DKMS может не собрать модуль"
      ;;
    pacman)
      pacman -Sy --needed --noconfirm \
        base-devel git pkgconf kmod gphoto2 libgphoto2 \
        v4l2loopback-dkms v4l-utils ffmpeg linux-headers \
        || die "Не удалось поставить пакеты (для linux-headers может понадобиться свой ядерный пакет)"
      ;;
    dnf)
      dnf install -y gcc gcc-c++ make git pkgconf-pkg-config kmod v4l-utils \
        libgphoto2-devel kmod-devel gphoto2 || die "Не удалось поставить зависимости"
      dnf install -y akmod-v4l2loopback \
        || warn "v4l2loopback: включите RPM Fusion и поставьте akmod-v4l2loopback"
      dnf install -y ffmpeg-free-devel \
        || warn "ffmpeg-devel: включите RPM Fusion, иначе webcamize не соберётся"
      ;;
    *)
      die "Неизвестный дистрибутив. Нужны: libgphoto2, libav*, libkmod, v4l2loopback, ffmpeg."
      ;;
  esac
  ok "зависимости на месте"
}

install_webcamize() {
  if command -v webcamize >/dev/null 2>&1; then
    ok "webcamize уже установлен: $(command -v webcamize)"
    return
  fi
  step "Сборка webcamize"
  local tmp; tmp=$(mktemp -d)
  if ! git clone --depth 1 --branch "$(git ls-remote --symref https://github.com/cowtoolz/webcamize.git HEAD 2>/dev/null | awk '/^ref:/{sub("refs/heads/","",$2); print $2}' | head -1)" \
        https://github.com/cowtoolz/webcamize.git "$tmp/src" >/dev/null 2>&1; then
    rm -rf "$tmp"
    git clone --depth 1 https://github.com/cowtoolz/webcamize.git "$tmp/src" >/dev/null 2>&1 \
      || die "Не удалось склонировать webcamize"
  fi
  ( cd "$tmp/src" && make -j"$(nproc 2>/dev/null || echo 2)" ) >/dev/null \
    || { rm -rf "$tmp"; die "Сборка webcamize не удалась: cd в каталог и запустите make вручную"; }
  ( cd "$tmp/src" && make install ) >/dev/null
  rm -rf "$tmp"
  command -v webcamize >/dev/null 2>&1 || die "webcamize не оказался в PATH после make install"
  ok "webcamize установлен в $(command -v webcamize)"
}

check_module() {
  step "Проверка v4l2loopback"
  if modinfo v4l2loopback >/dev/null 2>&1; then
    ok "модуль найден"
  else
    warn "модуль не найден — виртуальной камеры не будет"
  fi
  if [ -d /sys/firmware/efi ] && command -v mokutil >/dev/null 2>&1 \
     && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    warn "Secure Boot включён: DKMS-модуль должен быть подписан (MOK), иначе он не загрузится"
  fi
}

enable_unit() {
  local unit="$1"
  systemctl daemon-reload
  systemctl enable --now "$unit" >/dev/null
  sleep 2
  if systemctl is-active --quiet "$unit"; then
    ok "служба $unit запущена"
  else
    warn "служба $unit не активна. Смотрите: journalctl -u $unit -n 40 --no-pager"
  fi
}

install_main() {
  step "Служба systemd"
  curl -fsSL "$RAW/$UNIT" -o "$UNIT_DIR/$UNIT" || die "Не удалось скачать $UNIT"
  enable_unit "$UNIT"
}

install_fallback() {
  step "Fallback-демон (gphoto2 + ffmpeg)"
  # Два источника кадров одновременно не уживутся: камера одна.
  if [ -f "$UNIT_DIR/$UNIT" ]; then
    systemctl disable --now "$UNIT" >/dev/null 2>&1 || true
    rm -f "$UNIT_DIR/$UNIT"
    ok "основная служба отключена"
  fi
  curl -fsSL "$RAW/fallback/webcam.sh" -o "$FB_BIN" || die "Не удалось скачать webcam.sh"
  chmod 755 "$FB_BIN"
  curl -fsSL "$RAW/fallback/$FB_UNIT" -o "$UNIT_DIR/$FB_UNIT" || die "Не удалось скачать $FB_UNIT"
  if [ -n "$CROP" ]; then
    mkdir -p "$UNIT_DIR/$FB_UNIT.d"
    printf '[Service]\nEnvironment=OUT_SIZE=%s\nEnvironment=OUT_MODE=crop\n' "$CROP" \
      > "$UNIT_DIR/$FB_UNIT.d/10-crop.conf"
    ok "кадрирование включено: $CROP"
  fi
  enable_unit "$FB_UNIT"
}

do_uninstall() {
  step "Удаление"
  local u
  for u in "$UNIT" "$FB_UNIT"; do
    systemctl disable --now "$u" >/dev/null 2>&1 || true
    rm -f "$UNIT_DIR/$u"
    rm -rf "$UNIT_DIR/$u.d"
    ok "убрано: $u"
  done
  rm -f "$FB_BIN"
  systemctl daemon-reload
  printf '\n%sГотово.%s Сам webcamize оставлен в системе.\n' "$G" "$N"
  printf 'Удалить его: склонируйте репозиторий webcamize и выполните sudo make uninstall\n'
}

final_report() {
  printf '\n%s━━ Готово ━━%s\n\n' "$B" "$N"
  printf 'Камера должна появиться как:\n'
  printf '    %sCanon EOS … Webcamize%s   (или «Canon EOS» для fallback)\n\n' "$G" "$N"
  printf 'Проверить:\n'
  printf '    v4l2-ctl --list-devices\n'
  printf '    systemctl status %s\n' "$([ "$MODE" = fallback ] && echo "$FB_UNIT" || echo "$UNIT")"
  printf '    journalctl -u %s -f\n\n' "$([ "$MODE" = fallback ] && echo "$FB_UNIT" || echo "$UNIT")"
  printf '%sНе забудьте на камере:%s режим Movie, LiveView включён, Wi-Fi/NFC → Отключить,\n' "$Y" "$N"
  printf 'автоотключение питания → Выкл. Звука по USB не будет — выберите отдельный микрофон.\n\n'
  printf 'Дальше в Zoom/Meet/браузере выбираете камеру из списка. Вопросы и разбор проблем:\n'
  printf '    %shttps://github.com/%s%s\n\n' "$B" "$REPO" "$N"
}

case "$MODE" in
  uninstall) do_uninstall; exit 0 ;;
  fallback)  install_deps; check_module; install_fallback; final_report ;;
  *)         install_deps; install_webcamize; install_main; check_module; final_report ;;
esac
