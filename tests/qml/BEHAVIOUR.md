# What the menus do

The behaviour the Quickshell menus keep across rewrites. `[auto]` marks what `tests/qml/test_menus.py` checks
offscreen (see the end of this file); everything else is checked by hand on the desktop.

## Every menu

- Opens on the monitor that has keyboard focus at the moment it is opened, not on the first monitor.
- A second press of its key, waybar button or launcher entry closes it (toggle). `[auto]`: through the shell's
  IPC and through each launcher script.
- Closes on Esc, except where Esc first steps back inside the menu (listed per menu). `[auto]`
- Closes on a click outside its card (full-screen menus: on the dimmed area; the launcher and the notification
  panel: anywhere outside them).
- Fades in when it opens and out when it closes; nothing is left on screen or in memory once it is closed.
- Takes colours, fonts, radii, title style (italic, upper case), header icon or glyph from the current theme
  (`~/.config/hypr/palette.json`, `ui.json`, and the theme's folder for pictures). `[auto]`
- Follows a theme switch: a menu open during `changetheme` redraws in the new theme. `[auto]` (palette and ui
  rewritten while the menu is open).
- Letter shortcuts work by key position, so they work on the Russian layout too (H is "р").
- Closing a menu while it runs something (a file dialog, a hotkey capture, a test of monitor settings) undoes or
  finishes that thing: the capture gives Hyprland its binds back, untested monitor settings are reverted.

## Launcher — Alt+R, `~/.local/bin/launcher`

- Lists desktop applications plus the rice's commands: one per theme ("Тема …"), theme picker, screenshots, Telegram
  theme, games, settings (all pages, monitors, keys, features), network, power modes, battery care, notifications,
  lock, suspend, logout, reboot, poweroff. `[auto]` (commands present, one per theme, «Настройки: функции» opens
  the features page)
- Empty query: most launched first, then alphabetical; dangerous commands and per-theme commands are hidden.
  `[auto]`
- Search: exact > prefix > word prefix > substring > fuzzy (3+ letters); keywords count 0.7; a query typed in the
  wrong layout (ru/us) still matches at 0.9; frequent use adds to the score; at most 60 results. `[auto]`
- Down/Tab/Ctrl+J next, Up/Shift+Tab/Ctrl+K previous, Enter runs; logout/reboot/poweroff need a second Enter
  ("Нажми Enter ещё раз"). `[auto]` (arming)
- Each launch is counted in `~/.local/state/launcher/usage.json`.
- Window 680×560 centered; a click outside closes it.

## Settings — Alt+F2, waybar gear, launcher; `settings-panel [monitors|keys|theme|theme:<name>[:<section>]|features]`

- Opens on the page given (default: monitors); `theme:<name>:<section>` opens that theme's settings on that
  section. `[auto]` (also through `settings-panel`)
- Esc steps back: Wallpaper Engine picker, frame picker, theme dialog, install dialog (a theme's or a feature's; not
  while the password is checked), icon picker, a theme's settings; then closes. `[auto]` (a theme's settings → theme
  list → closed; a feature's install dialog → features)
- Monitors: drag to arrange (snaps to edges, top-left kept at 0×0), resolution, rate, scale, on/off; "Применить"
  applies live with a 15 s "keep?" countdown that reverts; "Оставить" writes `monitors.lua`, keeping any other
  fields and lines the user had there; closing the window while the countdown runs reverts. `[auto]` (parsing,
  snapping, the written file)
- Keys: main modifier Alt/Super (binds on their defaults move along), change/disable/reset a bind with a
  captured combo (passthrough submap while capturing, 15 s timeout, Esc cancels, mouse middle/side buttons count),
  conflict warning with "Всё равно назначить", program shortcuts (hyprctl globalshortcuts), own binds; "Сохранить"
  writes `binds-user.lua` and reloads Hyprland. `[auto]` (combo parsing and labels, conflicts, the written file)
- Theme: the theme list (8 to a tab), import, restore removed, per theme: edit, copy, export, factory reset,
  delete; a theme's settings: fonts, colours (+ Papirus folder colour), wallpapers (add, on/off, remove, frame
  from GIF/video, Wallpaper Engine), panel layout (drag, icons, top/bottom, for all themes), icon theme and
  battery drawing, cursor (+ size, add/remove from file), windows (gaps, border, rounding, opacity, blur,
  animations); "Сохранить" writes `~/.config/hypr-rice/theme-edits.json` (only what differs from the theme)
  and re-applies the current theme; package installs ask for the sudo password and run in the background.
  `[auto]` (the edits written, pruning)
- Features: `features.py list` by group in its order, each with its name, what it does (muted) and a switch; a
  switch runs `features.py on|off <id>` (which applies it: Hyprland reload, systemd unit) and the list is read again,
  so the switch shows the result; a refusal shows features.py's message under the list. A feature with missing
  packages says so; switching it on opens the install dialog for all of them (one sudo password), and once they are
  installed the installer switches the feature on, also when the dialog was hidden meanwhile; the list is read again
  whenever features.json changes. Declined or failed: it stays off. An experimental feature says so in warning
  colour. A feature that needs what the system does not allow yet — ports ufw keeps closed (`closedPorts`), a
  group the user is not in (`missingGroups`, input for the layout fixer, with the warning that any program could
  read the keys then and that it works after logging in again) — asks first: «Разрешить» (`features.py grant
  <id>`, one password in the polkit window, then on; a cancelled password leaves it off with the reason),
  «Включить без этого», «Отмена» or Esc.
  `[auto]` (the list and groups, on/off calls and the switch following them, a refusal's message, Esc out of the
  install dialog, two packages installed with one password then the feature switched on, the same with the dialog
  hidden during the install, the access question: on without it, grant then on)

## Theme picker — Alt+Shift+T, waybar palette, launcher

- Every theme as a card in its own colours and fonts, the current one selected; 8 to a tab (dots for tabs).
  `[auto]`
- ←→/H L/Tab move by one, ↑↓/K J by a row (wrapping), PgUp/PgDn turn tabs, 1–8 picks on the tab, Enter or a
  click applies (`changetheme`, not for the current theme) and closes; wheel moves. `[auto]` (moves, tabs)

## Help — Alt+F1, waybar "?"

- Hotkey cards from `hyprctl binds` descriptions "group | text [| keys]", known groups first in a fixed order, then
  the static cards (bar, terminal, Code - OSS, own settings files). `[auto]`
- The main modifier's name from the binds registry. Esc, F1 or Q closes. `[auto]` (Esc, F1)

## Power — Alt+M, waybar power

- Lock, logout, suspend, reboot, poweroff; logout/reboot/poweroff need a second press within 3.5 s. `[auto]`
- Letters L E S R P pick directly; ←→↑↓, H J K, Tab move; Enter/Space activate. `[auto]` (arrows, Enter, arming)
- Look per theme: cards, or a terminal-style list (ui.json `powerStyle: terminal`). `[auto]` (both load)

## Notifications — waybar bell, launcher

- histui's history, newest first, grouped by day (Сегодня, Вчера, date); search; unread count; click expands and
  marks read; copy and delete on hover; mark all read; Do Not Disturb; "Очистить всё" needs a second press.
  `[auto]` (grouping, plain text from markup)
- Refreshes every 4 s without losing the scroll position or an open card; actions run in order.
- Slides in from the right; Esc in the search clears it first.

## Network — waybar network, launcher

- Wi-Fi on/off, current connection with IP, other connected devices, nearby networks (best signal per SSID, saved
  first), password asked in place (8+ characters, sent to nmcli on stdin), forget, rescan, "Все настройки сети…".
  `[auto]` (nmcli field parsing, the list)
- Refreshes every 5 s without losing a typed password.

## Games — Alt+G, launcher

- The library from `games.py list` as cards with covers; search by typing; arrows move; Enter/click launches;
  edit (rename, cover, remove); add from a file, Steam or installed programs. Esc closes a dialog, then the menu.
  `[auto]` (filter, Esc out of a dialog)

## Clipboard history — Alt+Shift+V, launcher; `clipboard-history`

- `cliphist list` newest first, a picture as «картинка W×H, N КБ»; typing filters; arrows move; Enter/click copies
  the entry back (`cliphist decode | wl-copy`) and closes; Delete (at the end of the typed text) removes the entry;
  «Очистить» wipes the history on a second press. The feature off (Alt+F2 → Функции): nothing is read, the menu
  says where to switch it on. `[auto]` (labels and filter, Enter, Delete, the second press, off)

## Screenshot gallery — waybar camera

- `~/Pictures/screenshots`, newest first; click/Enter opens a preview (←→/H L flip); C copies, Enter opens in the
  viewer, Del trashes (second press); Esc leaves the preview, then closes. `[auto]` (date label, Esc steps)

## Screenshot — Print / Shift+Print, `shot [full]`

- Freezes every monitor first, then the overlay: drag a region or click a window (or the whole screen), Enter takes
  the whole screen, Esc or right click cancels; `full` takes the focused monitor at once; the theme's
  `screenshot.qml` draws the selection and the capture animation; the result goes to `~/Pictures/screenshots`
  and the clipboard. A second Print while the overlay is up does nothing. `[auto]` (Esc cancels, `full` saves and
  copies)

## Text recognition — Alt+Shift+Print, `shot ocr`

- The screenshot overlay in mode "ocr": a region is selected as for a screenshot; its text, read by tesseract in
  Russian and English, goes to the clipboard with a notification. The feature off: `shot` says so in a notification.

## Colour picker — Alt+Shift+C, `shot color`, menu "picker"

- Over the frozen screen: a magnifier in the theme's colours follows the pointer; a click copies that physical
  pixel's colour as #rrggbb to the clipboard with a notification; Esc or a right click cancels.

## Player — waybar custom/player, `player-panel`

- The active MPRIS player (the one that started playing last or was picked in the card; else the first playing,
  else the first): cover (a note without one), title, artist, program; seek bar when the player can seek;
  previous, play/pause, next (dimmed when the player cannot); shuffle, loop and volume only when supported; the
  other players as a list when there are several, a click makes one active. playerctld's mirror is not listed.
- No player: "Ничего не играет". `[auto]` (the empty state; the sandbox has no session bus)
- The media keys (`player-panel play-pause|next|previous`) and the bar module (`player-panel bar`) use the same
  active player; `bar` never starts the shell and shows the icon alone while it is down. `[auto]`

## Phone — waybar custom/phone, `phone-panel` (feature "kdeconnect")

- The phone KDE Connect shows (picked in the menu; else the first paired one in reach; else the first paired):
  name, in reach or not, charge and charging; when paired and in reach: «Найти телефон» (rings), «Пинг»,
  «Отправить файлы» (zenity picks them), «Отправить буфер», «Файлы телефона» (sftp mount opened in Thunar, the
  menu closes; a failure is a notification). Not paired, in reach: «Сопрячь»; the phone's request: the key,
  «Принять» / «Отклонить»; our request: the key, «Отменить». Paired: «Разорвать сопряжение». Several devices: a
  list, a click shows that one. A failed action's reason under the buttons.
- Feature off: the menu says where to switch it on; the bar module is empty (hidden). `[auto]` (the sandbox has no
  session bus)
- The bar (`phone-panel bar`): phone glyph, charge, charging glyph; tooltip name and charge. No paired phone in
  reach: the glyph alone (tooltip: not found / not paired, click to pair / out of reach), so the menu can still be
  opened to pair; empty only with the feature off or the shell down. Signalled (12) on every change; never starts
  the shell. `[auto]` (the bar text from a phone, the glyph alone for an unpaired one)

## Wallpaper sound — waybar custom/wallpaper, `wallpaper-panel`, the player card (feature "wallpaper-sound")

- services/Wallpaper.qml drives the animated wallpaper's mpv over its control socket. The player starts silent
  (aid=no, volume 0); with the feature on and a sound track in the clip, the track is switched on and the volume
  fades in over 1 s; it fades out while the wallpaper is hidden (wallpaper-hidden), the screen is locked
  (rice-lock) or another MPRIS player plays, and the track is switched off once silent. Hidden with the feature
  "wallpaper-pause" on: paused only after the fade; shown: resumed at once. `[auto]` (a fake mpv socket)
- Volume ±10 (`wallpaper-panel louder|quieter`, the card, the player's row), kept in
  ~/.config/hypr-rice/wallpaper-sound.json. The sound button switches the feature. `[auto]`
- The card (menu "wallpaper"): cover, title and artist from the theme's ui.json "wallpaperCard" (title "Обои"
  without one), the state ("звук выключен", why it is quiet, the volume), −, sound, + over the cover, how far
  the clip has played along the bottom edge. No animated wallpaper / no sound track: says so, no controls.
- The player card lists "Обои" under "Звук обоев" while the wallpaper has a sound track.
- The bar (`wallpaper-panel bar`): a volume glyph (on / quiet / off) with the state in the tooltip; empty while
  the wallpaper has no sound or the shell is down. Signalled (13) on every change; never starts the shell.
- A theme's ui.json "headerIcon" may be an animated GIF or WebP: it plays once when a menu opens, then rests on
  its first frame.
- A theme's ui.json "titleScale" scales every title of the menus and its card in the theme lists (a wide pixel font
  is drawn larger than most at the same size).
- A theme's ui.json "fonts" (files in its folder) are in the menus as soon as the theme is the current one, with no
  restart of the shell.

## Administrator password — polkit, always running

- When a program asks polkit for an administrator's rights: the password window in the theme; Esc, a click
  outside or «Отмена» cancel; a wrong password keeps it open with the error and the field still active.

## OSD — always running

- Shows volume (PipeWire default sink) and brightness (first backlight) changes for 1.4 s in the theme's
  `osdStyle` (pill, ascii, neon, minimal, retro, wave); ignores the values at start; follows theme switches. `[auto]`
  (loads, follows the theme)

## Automated checks

`python3 -m unittest discover -s tests/qml` runs `quickshell` offscreen (`QT_QPA_PLATFORM=offscreen`) on a copy of
the menus (`$RICE_HOME/.config/quickshell`, default the live `~`), in a fake `$HOME` with stub `hyprctl`, `histui`,
`nmcli`, `games.py`, `themegen.py`, `features.py`, `rice-install-package` and a fixed theme list. Layer-shell
windows cannot exist offscreen, so the copy has `PanelWindow` replaced by a floating window with the same properties
and the `WlrLayershell` lines dropped (`tests/qml/harness.py`). Keys are sent with QtTest's `keyClick`, which
carries no scan code: letter shortcuts by key position (the Russian layout) stay a manual check. The tests skip when
`quickshell` is not installed. The launcher scripts are run with a fake `quickshell` that records the IPC calls (and
the start of the shell when it is not running). The same suite passes on the per-panel menus kept in
`/home/larion/hypr-rice/.claude/menus-before` (`RICE_HOME=...`); the resident-shell tests skip there.
