#!/usr/bin/env bash
# canon-webcam (fallback) — Canon EOS как веб-камера без webcamize.
#
# Нужен только если: (а) webcamize не собрался/не завёлся, (б) нужен кроп 16:9,
# которого webcamize не умеет. Во всех остальных случаях используйте webcamize.
#
# gphoto2 тянет MJPEG-liveview по USB, ffmpeg заливает его в v4l2loopback.
# Скрипт сам ждёт камеру и перезапускает поток при обрыве.

set -uo pipefail

# При выходе (в т.ч. по Ctrl+C) не оставляем висеть ffmpeg/gphoto2.
cleanup() { pkill -P $$ 2>/dev/null; }
trap cleanup EXIT

CARD_LABEL="${CARD_LABEL:-Canon EOS}"
EXTRA_GPHOTO_ARGS="${EXTRA_GPHOTO_ARGS:-}"
# OUT_SIZE пусто = отдать кадр как есть. "1280:720" = привести к 16:9 720p.
OUT_SIZE="${OUT_SIZE:-}"
OUT_MODE="${OUT_MODE:-crop}"   # crop | pad

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Ищем /dev/videoN, созданный v4l2loopback с нашей меткой.
find_dev() {
  local n label
  for n in /sys/class/video4linux/video*; do
    [ -e "$n/name" ] || continue
    label=$(cat "$n/name" 2>/dev/null) || continue
    if [ "$label" = "$CARD_LABEL" ]; then
      echo "/dev/$(basename "$n")"
      return 0
    fi
  done
  return 1
}

ensure_module() {
  if lsmod | grep -q '^v4l2loopback'; then
    find_dev >/dev/null && return 0
    log "v4l2loopback уже загружен без метки '$CARD_LABEL', перезагружаю"
    if ! modprobe -r v4l2loopback 2>/dev/null; then
      log "ОШИБКА: модуль занят (устройство используется?), выгрузить не удалось"
      return 1
    fi
  fi
  modprobe v4l2loopback exclusive_caps=1 max_buffers=2 card_label="$CARD_LABEL" || {
    log "ОШИБКА: modprobe v4l2loopback не удался"
    return 1
  }
}

# gvfs любит захватывать камеру сразу после подключения — освобождаем её.
free_camera() {
  pkill -f gvfs-gphoto2-volume-monitor 2>/dev/null
  pkill -f gvfsd-gphoto2 2>/dev/null
  sleep 1
}

camera_present() {
  gphoto2 --auto-detect 2>/dev/null | grep -qiE 'canon|eos'
}

# Фильтр кадрирования. force_original_aspect_ratio + crop/pad —
# устойчивее, чем ручная арифметика по высоте кадра.
build_filter() {
  [ -z "$OUT_SIZE" ] && return 0
  if [ "$OUT_MODE" = "pad" ]; then
    echo "scale=${OUT_SIZE}:force_original_aspect_ratio=decrease,pad=${OUT_SIZE}:(ow-iw)/2:(oh-ih)/2"
  else
    echo "scale=${OUT_SIZE}:force_original_aspect_ratio=increase,crop=${OUT_SIZE}"
  fi
}

FILTER=$(build_filter)
log "старт, метка: '$CARD_LABEL', кадрирование: ${OUT_SIZE:-как есть} (${OUT_MODE})"

while :; do
  if ! ensure_module; then
    sleep 10
    continue
  fi

  LOOP_DEV=$(find_dev) || { sleep 5; continue; }

  if ! camera_present; then
    sleep 2
    continue
  fi

  free_camera
  log "камера найдена, стрим в $LOOP_DEV"

  FF_ARGS=(-hide_banner -loglevel warning -i - -vcodec rawvideo -pix_fmt yuv420p -threads 0)
  [ -n "$FILTER" ] && FF_ARGS+=(-vf "$FILTER")
  FF_ARGS+=(-f v4l2 "$LOOP_DEV")

  # shellcheck disable=SC2086
  gphoto2 --stdout --capture-movie $EXTRA_GPHOTO_ARGS | ffmpeg "${FF_ARGS[@]}"

  log "поток прерван (камера уснула / кабель / занята), перезапуск через 3 с"
  sleep 3
done
