# Fallback: свой демон вместо webcamize

Обычно **не нужен**. Берите его, только если:

1. webcamize не собрался или не завёлся у вас (например, конфликт `v4l2loopback`
   с GStreamer/Chromium — такая связка ломалась в 2025–2026);
2. нужен **кроп 16:9** — webcamize кадрировать не умеет, а здесь это есть.

Устройство называется по метке `CARD_LABEL` (по умолчанию «Canon EOS»), а не
«… Webcamize» — чтобы в Zoom было видно, что запущен именно fallback.

## Установка

```bash
sudo apt install gphoto2 v4l2loopback-dkms v4l2loopback-utils ffmpeg v4l-utils
sudo usermod -aG video "$USER"        # затем перелогиниться

sudo install -m 755 webcam.sh                     /usr/local/bin/canon-webcam-fallback
sudo install -m 644 canon-webcam-fallback.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now canon-webcam-fallback
```

Важно: сначала выключите основной юнит, иначе два процесса подерутся за камеру.

```bash
sudo systemctl disable --now canon-webcam
```

## Настройки (переменные окружения)

| Переменная | По умолчанию | Смысл |
|---|---|---|
| `CARD_LABEL` | `Canon EOS` | имя виртуального устройства |
| `OUT_SIZE` | пусто | `W:H`, например `1280:720`. Пусто = отдавать кадр как есть |
| `OUT_MODE` | `crop` | `crop` — заполнить, обрезав края; `pad` — вписать, добавив поля |
| `EXTRA_GPHOTO_ARGS` | пусто | доп. аргументы gphoto2, напр. `--set-config viewfinder=1` |

Менять — через drop-in, не редактируя юнит:

```bash
sudo systemctl edit canon-webcam-fallback
```
```ini
[Service]
Environment=OUT_SIZE=1280:720
Environment=OUT_MODE=crop
```

Затем `sudo systemctl restart canon-webcam-fallback`.

## Про кроп

Liveview у EOS — 3:2, а вебкамеры и Zoom ждут 16:9, поэтому по бокам появляются поля.
Фильтр:

- `crop`: `scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720` —
  масштабирует «с заполнением» и срезает лишнее по центру. Так делает и Canon'овская
  утилита (у неё за это отвечают `APIFrameCrop`/`APIFrameLayout`).
- `pad`: `scale=…:decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2` — вписывает целиком,
  добавляя чёрные поля. Если важно не терять края кадра (например, видна доска).

Кадр при этом всё равно апскейлится с ~1024×576 — деталей не прибавится, меняется
только геометрия и поведение в приложениях.

## Диагностика и удаление

```bash
systemctl status canon-webcam-fallback
journalctl -u canon-webcam-fallback -f
v4l2-ctl --list-devices
```

```bash
sudo systemctl disable --now canon-webcam-fallback
sudo rm /usr/local/bin/canon-webcam-fallback /etc/systemd/system/canon-webcam-fallback.service
sudo systemctl daemon-reload
```
