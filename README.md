<div align="center">

# 📷 Canon EOS как веб-камера на Linux

**Одна команда — и ваша камера работает в Zoom, Meet, Teams, OBS и браузере.**
Без Windows. Без EOS Webcam Utility. Без Wine.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/platform-Linux-informational.svg)](#требования)
[![Powered by libgphoto2](https://img.shields.io/badge/powered%20by-libgphoto2%20%2B%20v4l2loopback-success.svg)](#как-это-работает)

</div>

---

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/michaelyosta/canon-eos-webcam-linux/main/install.sh | sudo bash
```

Всё. Перезагружаться не нужно, камеру можно не выключать — служба сама её дождётся.

Через пару секунд в системе появится виртуальная камера **«Canon EOS … Webcamize»**.
Выберите её в Zoom / Meet / Teams / OBS — и говорите.

Другие режимы:

```bash
# с кадрированием в 16:9 (1280×720) — как это делает Canon'овская утилита
curl -fsSL https://raw.githubusercontent.com/michaelyosta/canon-eos-webcam-linux/main/install.sh | sudo bash -s -- --crop

# удалить всё установленное
curl -fsSL https://raw.githubusercontent.com/michaelyosta/canon-eos-webcam-linux/main/install.sh | sudo bash -s -- --uninstall
```

---

## Что делает установщик

1. Ставит зависимости из вашего пакетного менеджера (`apt`, `dnf` или `pacman`).
2. Собирает [webcamize](https://github.com/cowtoolz/webcamize) из исходников в `/usr/local/bin`.
3. Кладёт systemd-службу `canon-webcam.service` и включает её.
4. Проверяет, что модуль `v4l2loopback` доступен (и предупреждает про Secure Boot).
5. Печатает, что проверить и что настроить на камере.

Скрипт идемпотентен: повторный запуск ничего не ломает. Он не удаляет и не изменяет
пользовательские файлы, кроме своих собственных (`/etc/systemd/system/canon-webcam*.service`,
`/usr/local/bin/canon-webcam-fallback`).

## Как это работает

```
┌─────────────┐  USB (PTP/MTP)   ┌──────────────┐  MJPEG   ┌────────┐  V4L2   ┌──────────────┐
│ Canon EOS   │ ───────────────► │ libgphoto2   │ ───────► │ ffmpeg │ ──────► │ /dev/videoN  │
│ (LiveView)  │  кадры preview   │  (webcamize) │          │        │         │ v4l2loopback │
└─────────────┘                  └──────────────┘          └────────┘         └──────┬───────┘
                                                                                     │
                                                          Zoom / Meet / Teams / OBS ◄─┘
```

Windows-утилита Canon делает ровно то же самое: тонкая обёртка над фирменным EDSDK плюс
виртуальная камера. На Linux эту роль делят два зрелых открытых проекта — `libgphoto2`
(протокол камеры) и `v4l2loopback` (виртуальное устройство). Поэтому ничего
реверс-инжинирить не нужно: протокол уже открыт.

## Требования

| Что | Детали |
|---|---|
| ОС | Linux с systemd: Ubuntu, Debian, Mint, Fedora, Arch и производные |
| Камера | Canon EOS с поддержкой LiveView по USB — [список libgphoto2](http://www.gphoto.org/proj/libgphoto2/support.php) |
| Кабель | micro-USB / USB-C **data**, не «только зарядка» |
| Права | `sudo` (нужен для модуля ядра и службы) |
| Память | ~60 МБ на сборку, дальше ничего не занимает |

## Настройте камеру

| Настройка | Значение |
|---|---|
| Колесо режимов | **Movie** (видео), не фото |
| LiveView | включён (экран камеры показывает картинку) |
| Меню → Wi-Fi/NFC | **Отключить** — конфликтует с USB |
| Меню → Автоотключение питания | **Выкл** — иначе уснёт посреди созвона |

> На EOS M50 нет ни зарядки по USB, ни DC-разъёма: либо заряженная батарея,
> либо USB-«dummy battery» (LP-E12 eliminator).

У новых тел (EOS R6 Mark II, R8, R10, R50, R3, R1, R5 Mark II…) есть **нативный UVC**:
им ничего этого не нужно — камера сама определяется как вебка. Проверьте
`v4l2-ctl --list-devices` до установки.

## Честные ограничения

- **Звука не будет.** Canon EOS не отдаёт аудио по USB. Микрофон выбирайте отдельно —
  в Zoom это две независимые настройки.
- **Не 1080p.** Отдаётся LiveView-поток: обычно ~1024×576 и до 2 Мп. Картинка всё равно
  заметно лучше встроенной вебки, но это не запись с сенсора.
- **Задержка ~150–300 мс**, особенно на USB 2.0.
- **Камера занята эксклюзивно:** пока идёт стрим, `EOS Utility`/`gphoto2` её не увидят.
- Для настоящего 1080p нужен HDMI-выход камеры + USB-граббер (UVC), это другой сценарий.

## Если что-то не так

<details>
<summary><b>Камеры нет в списке приложений</b></summary>

```bash
v4l2-ctl --list-devices                 # есть ли «… Webcamize»?
systemctl status canon-webcam           # служба жива?
journalctl -u canon-webcam -n 50 --no-pager
```

Если устройства нет вовсе — модуль не загрузился. Проверьте:

```bash
cat /sys/module/v4l2loopback/parameters/exclusive_caps   # должно быть Y
sudo modprobe -r v4l2loopback && sudo systemctl restart canon-webcam
```

</details>

<details>
<summary><b>Secure Boot: модуль не загружается</b></summary>

DKMS-модули должны быть подписаны. Либо выключите Secure Boot, либо зарегистрируйте
MOK-ключ при первой установке `v4l2loopback-dkms` (`mokutil --import`).

</details>

<details>
<summary><b>«Could not claim USB device»</b></summary>

Камеру забрал gvfs:

```bash
pkill -f gvfs-gphoto2-volume-monitor; pkill -f gvfsd-gphoto2
sudo systemctl restart canon-webcam
```

</details>

<details>
<summary><b>Камера отвалилась после сна / выдёргивания кабеля</b></summary>

Служба перезапускается сама (`Restart=always`, `RestartSec=5`, без лимита попыток).
Если не поднялась — `journalctl -u canon-webcam -n 50`.

</details>

<details>
<summary><b>Почему в юните нет флага <code>-w</code></b></summary>

`webcamize` документирует `-w/--wait`, но в коде `case 'w'` отсутствует — флаг падает с
`Unsupported option w`. Поэтому служба запускает процесс в foreground (`Type=simple`),
а держит его systemd. И `KillSignal=SIGINT`: webcamize удаляет `/dev/videoN` только по
SIGINT, а по SIGTERM умер бы молча, оставив устройство висеть.

</details>

## Опции установщика

| Опция | Что делает |
|---|---|
| *(без опций)* | webcamize + служба — рекомендуемый вариант |
| `--crop` | fallback-демон с кадрированием 16:9 (1280×720) — вместо webcamize |
| `--fallback` | только свой демон `gphoto2 \| ffmpeg`, без webcamize |
| `--uninstall` | остановить и удалить службы и файлы |

Fallback нужен, если webcamize не собрался/конфликтует с GStreamer или если нужен кроп —
webcamize кадрировать не умеет. Подробности: [`fallback/README.md`](fallback/README.md).

## Совместимость

| Проверено | Статус |
|---|---|
| Canon EOS M50 + Ubuntu 24.04 / Mint 22 | ✅ работает |
| Canon EOS M50 + Arch (AUR: `webcamize`) | ✅ работает |
| Другие EOS с LiveView | 🟡 должно работать, но не проверялось — напишите в Issues |
| EOS с нативным UVC (R6 II, R8, R10, R50…) | ⚪ софт не нужен, камера работает сама |

## FAQ

<details>
<summary><b>Чем это отличается от webcamize?</b></summary>

Ничем по сути — webcamize и есть движок. Здесь добавлено: systemd-служба с корректной
остановкой, автоперезапуск без лимита попыток, защита от Secure Boot-грабли, кроп 16:9
в fallback-режиме и установка одной командой.

</details>

<details>
<summary><b>А почему не EOS Webcam Utility?</b></summary>

Он Windows/macOS-only: kernel-mode драйвер + DirectShow-фильтр, под Wine не живёт.
Внутри — 23 вызова EDSDK поверх обычного PTP; на Linux тот же PTP уже реализован в
`libgphoto2`, поэтому эмуляция утилиты не требуется.

</details>

<details>
<summary><b>Можно ли получить 4K / полный кадр с сенсора?</b></summary>

По USB — нет, это ограничение камеры. Нужен HDMI → USB-граббер.

</details>

<details>
<summary><b>Работает ли одновременно с записью на карту?</b></summary>

Нет. LiveView по USB занимает камеру целиком.

</details>

## Структура репозитория

```
.
├── install.sh                        # установщик (curl | sudo bash)
├── canon-webcam.service              # служба для webcamize
└── fallback/
    ├── webcam.sh                     # свой демон: gphoto2 | ffmpeg (+ кроп)
    ├── canon-webcam-fallback.service
    └── README.md
```

## Разработка

```bash
bash -n install.sh fallback/webcam.sh
shellcheck -S error install.sh fallback/webcam.sh
```

Правки в службах — обычный текстовый редактор, проверка:

```bash
sudo systemctl daemon-reload && sudo systemctl restart canon-webcam
journalctl -u canon-webcam -f
```

## Благодарности

Стоит на плечах гигантов: [webcamize](https://github.com/cowtoolz/webcamize) (BSD-2),
[libgphoto2](https://github.com/gphoto/libgphoto2) (LGPL-2.1),
[v4l2loopback](https://github.com/v4l2loopback/v4l2loopback) (GPL-2.0),
[ffmpeg](https://ffmpeg.org) (LGPL/GPL). Код этого репозитория — MIT, см. [LICENSE](LICENSE).

---

## English

Turn a Canon EOS into a proper webcam on Linux in one command — no Windows, no
EOS Webcam Utility, no Wine. It installs [webcamize](https://github.com/cowtoolz/webcamize)
(libgphoto2 + ffmpeg + v4l2loopback) and a systemd unit that waits for the camera and
recovers from disconnects.

```bash
curl -fsSL https://raw.githubusercontent.com/michaelyosta/canon-eos-webcam-linux/main/install.sh | sudo bash
```

Requirements: any Canon EOS with USB LiveView, a data cable, systemd-based distro.
No audio (the camera doesn't send any over USB), ~1024×576 LiveView stream, ~150–300 ms
latency. Tested on EOS M50 with Ubuntu 24.04 and Arch.
