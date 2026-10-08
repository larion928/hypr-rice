#!/usr/bin/env bash
# hypr-rice installer. Run it as your normal user (not root) on Arch or an Arch-based distro:
#
#   curl -fsSL https://raw.githubusercontent.com/larion928/hypr-rice/main/install.sh | bash
#
# It asks its questions first, then installs everything unattended. Safe to run again:
# packages are installed with --needed, files are refreshed, the old ones go to a backup.
#
# Environment overrides: RICE_THEME (default: current theme, else claude), RICE_BRANCH (default main),
# RICE_SRC (where the repo is kept, default ~/.local/share/hypr-rice),
# RICE_ASSUME=y|n answers every yes/no question without asking (unattended runs),
# RICE_APPS=all|none|id,id,... skips the program picker (ids are in packages/apps.txt).
set -euo pipefail

REPO_URL="https://github.com/larion928/hypr-rice.git"
BRANCH="${RICE_BRANCH:-main}"
SRC="${RICE_SRC:-$HOME/.local/share/hypr-rice}"
# An update keeps the theme that is active now.
THEME="${RICE_THEME:-$(cat "$HOME/.config/hypr/current-theme" 2>/dev/null || echo claude)}"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$HOME/.rice-backup-$STAMP"
MARKER="$HOME/.config/hypr/.rice-installed"

# ---------- output ----------

if [ -t 1 ]; then
    B=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYN=$'\e[36m'; R=$'\e[0m'
else
    B=; DIM=; RED=; GRN=; YEL=; CYN=; R=
fi
step() { printf '\n%s==>%s %s%s%s\n' "$CYN" "$R" "$B" "$*" "$R"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓%s %s\n' "$GRN" "$R" "$*"; }
warn() { printf '    %s!%s %s\n' "$YEL" "$R" "$*" >&2; WARNINGS+=("$*"); }
die()  { printf '\n%sОшибка:%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }
WARNINGS=()

# curl | bash: stdin is the script itself, so questions are read from the terminal.
have_tty() { { : </dev/tty; } 2>/dev/null; }
ask() {  # ask "question" default(y|n) -> returns 0 for yes
    local q=$1 def=${2:-n} a hint
    [ "$def" = y ] && hint="[Y/n]" || hint="[y/N]"
    if [ -n "${RICE_ASSUME:-}" ]; then
        info "$q $hint ${RICE_ASSUME} (RICE_ASSUME)"
        [[ $RICE_ASSUME =~ ^[Yy] ]]
        return
    fi
    if ! have_tty; then
        [ "$def" = y ]
        return
    fi
    read -r -p "    $q $hint " a </dev/tty || a=""
    a=${a:-$def}
    [[ $a =~ ^[YyДд] ]]
}

list() {  # package names from a list file, without comments
    grep -v '^[[:space:]]*#' "$1" | sed 's/[[:space:]]*#.*//' | grep -v '^[[:space:]]*$'
}

trim() { local v=$1; v=${v#"${v%%[![:space:]]*}"}; printf '%s' "${v%"${v##*[![:space:]]}"}"; }

# ---------- program catalog (packages/apps.txt) ----------

APP_IDS=()
declare -A APP_GROUP APP_NAME APP_SRC
load_apps() {
    local id group name src
    while IFS='|' read -r id group name src; do
        id=$(trim "$id")
        APP_IDS+=("$id")
        APP_GROUP[$id]=$(trim "$group")
        APP_NAME[$id]=$(trim "$name")
        APP_SRC[$id]=$(trim "$src")
    done < <(list "$1")
}

app_installed() {  # every source of the app is already present
    local tok
    for tok in ${APP_SRC[$1]}; do
        case "$tok" in
            appimage:*) [ -x "$HOME/Applications/$1.AppImage" ] || return 1 ;;
            file:*) [ -e "$HOME/${tok#file:}" ] || return 1 ;;
            aur:*) pacman -Qq "${tok#aur:}" >/dev/null 2>&1 || return 1 ;;
            *) pacman -Qq "$tok" >/dev/null 2>&1 || return 1 ;;
        esac
    done
}

# Pinned and checksummed: gum 2.x toggles only with "x", 0.17 also with space.
GUM_VERSION=0.17.0
GUM_SHA256=69ee169bd6387331928864e94d47ed01ef649fbfe875baed1bbf27b5377a6fdb
GUM=""
fetch_gum() {
    local dir tgz
    dir=$(mktemp -d)
    tgz="$dir/gum.tgz"
    curl -fsSL -o "$tgz" \
        "https://github.com/charmbracelet/gum/releases/download/v$GUM_VERSION/gum_${GUM_VERSION}_Linux_x86_64.tar.gz" \
        && echo "$GUM_SHA256  $tgz" | sha256sum -c --quiet - >/dev/null 2>&1 \
        && tar -xzf "$tgz" -C "$dir" \
        && GUM=$(find "$dir" -name gum -type f | head -n1) && [ -n "$GUM" ]
}

PICKED=()
pick_apps() {
    local id label opts=() pre=() out
    if [ -n "${RICE_APPS:-}" ]; then
        case "$RICE_APPS" in
            all) PICKED=("${APP_IDS[@]}") ;;
            none) PICKED=() ;;
            *) IFS=, read -r -a PICKED <<<"$RICE_APPS" ;;
        esac
        info "программы (RICE_APPS): ${PICKED[*]:-нет}"
        return
    fi
    have_tty || { info "нет терминала, дополнительные программы не ставлю"; return; }
    for id in "${APP_IDS[@]}"; do
        label="${APP_GROUP[$id]} · ${APP_NAME[$id]}"
        opts+=("$label=$id")
        # On an update what is already installed starts ticked.
        if [ -f "$MARKER" ] && app_installed "$id"; then pre+=("$label"); fi
    done
    if fetch_gum; then
        out=$("$GUM" choose --no-limit --height 22 --label-delimiter="=" \
            --header "Какие программы поставить?  пробел — отметить · enter — готово · ничего не отмечено — ничего не ставится" \
            --selected "$(IFS=,; echo "${pre[*]}")" \
            --cursor "› " --cursor-prefix "[ ] " --selected-prefix "[✓] " --unselected-prefix "[ ] " \
            --header.foreground "#d97757" --cursor.foreground "#e8a383" --selected.foreground "#8fa876" \
            "${opts[@]}" </dev/tty) || out=""
        mapfile -t PICKED <<<"$out"
    else
        # No gum (GitHub unreachable, odd terminal): a plain numbered list.
        local i=1 nums n
        info "Какие программы поставить? Номера через пробел, Enter — ничего:"
        for id in "${APP_IDS[@]}"; do
            printf '      %2d) %s · %s\n' "$i" "${APP_GROUP[$id]}" "${APP_NAME[$id]}"
            i=$((i + 1))
        done
        read -r -p "    > " nums </dev/tty || nums=""
        for n in $nums; do
            if [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#APP_IDS[@]} ]; then
                PICKED+=("${APP_IDS[$((n - 1))]}")
            fi
        done
    fi
    local clean=()
    for id in "${PICKED[@]}"; do [ -n "$id" ] && [ -n "${APP_NAME[$id]:-}" ] && clean+=("$id"); done
    PICKED=("${clean[@]}")
    if [ ${#PICKED[@]} -gt 0 ]; then
        ok "выбрано: $(for id in "${PICKED[@]}"; do printf '%s, ' "${APP_NAME[$id]}"; done | sed 's/, $//')"
    else
        ok "дополнительные программы не выбраны"
    fi
}
picked() { local id; for id in "${PICKED[@]}"; do [ "$id" = "$1" ] && return 0; done; return 1; }

# Vulkan for 32-bit games: Steam's lib32-vulkan-driver has several providers and
# --noconfirm would just take the first one, which is wrong for most GPUs.
gpu_vulkan() {
    local v
    for v in /sys/class/drm/card*/device/vendor; do
        case "$(cat "$v" 2>/dev/null)" in
            0x1002) echo "vulkan-radeon lib32-vulkan-radeon" ;;
            0x8086) echo "vulkan-intel lib32-vulkan-intel" ;;
            0x10de) echo "nvidia-utils lib32-nvidia-utils" ;;
            0x1af4) echo "vulkan-virtio lib32-vulkan-virtio" ;;
        esac
    done | tr ' ' '\n' | sort -u
}

# ---------- 1. checks ----------

step "Проверки"
[ "$(id -u)" -ne 0 ] || die "запускай от обычного пользователя, не от root (sudo скрипт спросит сам)"
command -v pacman >/dev/null || die "нужен Arch Linux или производный дистрибутив (pacman не найден)"
curl -fsSI --max-time 10 https://github.com >/dev/null || die "нет интернета (github.com недоступен)"
ok "Arch, пользователь $USER, интернет есть"

info "Нужны права администратора, введи пароль sudo:"
if have_tty; then sudo -v </dev/tty; else sudo -v; fi || die "sudo не сработал"
# Keep the sudo timestamp fresh for the whole (long) run.
( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
SUDO_KEEPER=$!
trap 'kill $SUDO_KEEPER 2>/dev/null || true' EXIT

# ---------- 2. repo ----------

step "Скачиваю hypr-rice"
sudo pacman -S --needed --noconfirm git >/dev/null
if [ -d "$SRC/.git" ]; then
    git -C "$SRC" fetch -q --depth 1 origin "$BRANCH"
    git -C "$SRC" reset -q --hard "origin/$BRANCH"
else
    rm -rf "$SRC"
    git clone -q --depth 1 -b "$BRANCH" "$REPO_URL" "$SRC"
fi
ok "$(git -C "$SRC" log -1 --format='%h  %s')"
load_apps "$SRC/packages/apps.txt"

# ---------- 3. questions ----------

step "Вопросы (дальше всё пойдёт само)"

RICE_DIRS=(hypr waybar quickshell kitty rofi wofi dunst mako swaync eww ags hyprpanel wlogout
           fuzzel walker histui swaylock alacritty foot)
found=()
for d in "${RICE_DIRS[@]}"; do
    p="$HOME/.config/$d"
    [ -e "$p" ] && [ -n "$(ls -A "$p" 2>/dev/null)" ] && found+=("$p")
done

DO_BACKUP=0
if [ -f "$MARKER" ]; then
    info "hypr-rice уже установлен ($(cat "$MARKER")). Файлы обновятся, текущие уйдут в бэкап."
    ask "Продолжить?" y || die "отменено"
    DO_BACKUP=1
elif [ ${#found[@]} -gt 0 ]; then
    info "Найден уже настроенный рабочий стол:"
    printf '      %s\n' "${found[@]}"
    info "Он будет убран из системы (в бэкап $BACKUP), вместо него встанет hypr-rice."
    ask "Удалить старый райс?" n || die "отменено, ничего не изменено"
    DO_BACKUP=1
else
    ok "система чистая"
fi

pick_apps

REPO_APPS=(); AUR_APPS=(); APPIMAGES=(); DROP_FILES=()
for id in "${APP_IDS[@]}"; do
    for tok in ${APP_SRC[$id]}; do
        if ! picked "$id"; then
            [[ $tok == file:* ]] && DROP_FILES+=("${tok#file:}")
            continue
        fi
        case "$tok" in
            aur:*) AUR_APPS+=("${tok#aur:}") ;;
            appimage:*) APPIMAGES+=("$id ${tok#appimage:}") ;;
            file:*) ;;
            *) REPO_APPS+=("$tok") ;;
        esac
    done
done
if picked steam; then mapfile -t -O "${#REPO_APPS[@]}" REPO_APPS < <(gpu_vulkan); fi

# ---------- 4. packages ----------

step "Пакеты из официальных репозиториев"
if printf '%s\n' "${REPO_APPS[@]}" | grep -qE '^(steam|umu-launcher|lib32-.*)$' \
        && ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    # steam, umu-launcher and lib32-* live in multilib.
    sudo sed -i '/^#\[multilib\]/{N;s/#\[multilib\]\n#Include/[multilib]\nInclude/}' /etc/pacman.conf
    ok "включён репозиторий multilib"
fi
mapfile -t BASE < <(list "$SRC/packages/base.txt")
# pipewire-pulse replaces PulseAudio; --noconfirm would answer "no" to removing it and abort.
if pacman -Qq pulseaudio >/dev/null 2>&1; then
    mapfile -t PA < <(pacman -Qq | grep -E '^pulseaudio(-|$)')
    sudo pacman -Rdd --noconfirm "${PA[@]}" >/dev/null
    info "PulseAudio заменён на PipeWire"
fi
sudo pacman -Syu --needed --noconfirm "${BASE[@]}"
ok "${#BASE[@]} пакетов"

step "AUR"
if ! command -v yay >/dev/null; then
    info "ставлю yay"
    tmp=$(mktemp -d)
    git clone -q --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
fi
mapfile -t AUR < <(list "$SRC/packages/aur.txt")
yay -S --needed --noconfirm --answerdiff None --answerclean None --removemake "${AUR[@]}" \
    || warn "часть пакетов из AUR не встала, повтори установщик позже"

if [ ${#PICKED[@]} -gt 0 ]; then
    step "Выбранные программы"
    [ ${#REPO_APPS[@]} -eq 0 ] || sudo pacman -S --needed --noconfirm "${REPO_APPS[@]}" \
        || warn "часть программ из репозиториев не встала"
    [ ${#AUR_APPS[@]} -eq 0 ] || yay -S --needed --noconfirm --answerdiff None --answerclean None "${AUR_APPS[@]}" \
        || warn "часть программ из AUR не встала"
    for entry in "${APPIMAGES[@]}"; do
        id=${entry%% *}; url=${entry#* }
        dest="$HOME/Applications/$id.AppImage"
        mkdir -p "$HOME/Applications" "$HOME/.local/share/applications"
        if curl -fL --progress-bar -o "$dest.part" "$url"; then
            mv "$dest.part" "$dest"
            chmod +x "$dest"
            # So the launcher (Alt+R) lists it like any installed app.
            printf '%s\n' "[Desktop Entry]" "Type=Application" "Name=${APP_NAME[$id]}" "Exec=$dest" \
                "Icon=applications-games" "Categories=Game;" \
                > "$HOME/.local/share/applications/hypr-rice-$id.desktop"
            ok "${APP_NAME[$id]} → ~/Applications/$id.AppImage"
        else
            rm -f "$dest.part"
            warn "${APP_NAME[$id]} не скачался"
        fi
    done
    ok "программ: ${#PICKED[@]}"
fi

# ---------- 5. files ----------

step "Файлы райса"
cd "$SRC/home"
mapfile -d '' FILES < <(find . -type f -print0 -o -type l -print0)

if [ "$DO_BACKUP" = 1 ]; then
    mkdir -p "$BACKUP"
    # Foreign rice configs leave entirely; for our own paths only what we are about to replace.
    for p in "${found[@]}"; do
        case "$p" in
            "$HOME/.config/hypr") ;;  # handled below, monitors/devices stay
            *) mv "$p" "$BACKUP/" ;;
        esac
    done
    if [ -d "$HOME/.config/hypr" ]; then
        mkdir -p "$BACKUP/hypr"
        find "$HOME/.config/hypr" -mindepth 1 -maxdepth 1 \
            ! -name monitors.lua ! -name devices.lua -exec mv -t "$BACKUP/hypr/" {} +
    fi
    for f in "${FILES[@]}"; do
        f=${f#./}
        [ -e "$HOME/$f" ] || continue
        mkdir -p "$BACKUP/home/$(dirname "$f")"
        mv "$HOME/$f" "$BACKUP/home/$f"
    done
    ok "старое → $BACKUP"
fi

tar -cf - . | tar -C "$HOME" -xf -
for f in "${FILES[@]}"; do
    f="$HOME/${f#./}"
    [ -f "$f" ] && grep -Iq "__HOME__" "$f" 2>/dev/null && sed -i "s|__HOME__|$HOME|g" "$f"
done
chmod +x "$HOME"/.local/bin/* "$HOME"/.config/waybar/scripts/* "$HOME"/.config/hypr/scripts/*.py \
         "$HOME"/.config/hypr/scripts/ru-date "$HOME"/.claude/statusline.sh 2>/dev/null || true
cd "$HOME"
for f in "${DROP_FILES[@]}"; do rm -f "$HOME/$f"; done
ok "${#FILES[@]} файлов"

# Machine-specific files are never overwritten.
if [ ! -f "$HOME/.config/hypr/monitors.lua" ]; then
    cat > "$HOME/.config/hypr/monitors.lua" <<'EOF'
-- Monitors of this machine (not part of hypr-rice). Every output at its preferred mode;
-- name outputs here for fixed layouts, see `hyprctl monitors`.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
EOF
fi
if [ ! -f "$HOME/.config/hypr/devices.lua" ]; then
    cat > "$HOME/.config/hypr/devices.lua" <<'EOF'
-- Per-device input settings. mouse-sens rewrites the sensitivity lines below,
-- keep each hl.device() call on a single line.
EOF
fi
xdg-user-dirs-update 2>/dev/null || true
mkdir -p "$HOME/Pictures/screenshots"

# ---------- 6. system ----------

step "Системные настройки"
sed "s|__HOME__|$HOME|g" "$SRC/system/hypr-theme-root" | sudo tee /usr/local/bin/hypr-theme-root >/dev/null
sudo chmod 755 /usr/local/bin/hypr-theme-root
rule="$USER ALL=(root) NOPASSWD: /usr/local/bin/hypr-theme-root"
tmp=$(mktemp)
echo "$rule" > "$tmp"
if sudo visudo -cqf "$tmp"; then
    sudo install -m 440 -o root -g root "$tmp" /etc/sudoers.d/hypr-theme
    ok "hypr-theme-root (цвет папок и экран входа)"
else
    warn "правило sudoers не прошло проверку, смена цвета папок и SDDM работать не будет"
fi
rm -f "$tmp"

sudo install -Dm644 "$SRC/system/sddm-theme.conf" /etc/sddm.conf.d/10-theme.conf
ok "SDDM: тема sugar-candy"

if ls /sys/bus/platform/drivers/ideapad_acpi/*/fn_lock >/dev/null 2>&1; then
    sudo install -Dm644 "$SRC/system/fn-lock.conf" /etc/tmpfiles.d/fn-lock.conf
    sudo systemd-tmpfiles --create /etc/tmpfiles.d/fn-lock.conf 2>/dev/null || true
    ok "Lenovo IdeaPad: Fn Lock включён"
fi

for s in NetworkManager bluetooth; do
    sudo systemctl enable "$s.service" >/dev/null 2>&1 || warn "не включился $s"
done
# Another display manager would fight SDDM for the seat.
for dm in gdm lightdm ly lxdm greetd; do
    systemctl is-enabled "$dm.service" >/dev/null 2>&1 && sudo systemctl disable "$dm.service" >/dev/null 2>&1 \
        && info "выключен $dm"
done
sudo systemctl enable sddm.service >/dev/null 2>&1 || warn "не включился sddm"
ok "сервисы: NetworkManager, bluetooth, sddm"

systemctl --user daemon-reload 2>/dev/null || true
for u in pipewire.socket pipewire-pulse.socket wireplumber.service histuid.service portal-restart.timer; do
    systemctl --user enable "$u" >/dev/null 2>&1 || warn "не включился $u (включи после входа: systemctl --user enable $u)"
done
ok "пользовательские сервисы"

# GTK, icons, cursor. settings.ini covers GTK apps; gsettings covers portals and libadwaita.
gs() { dbus-run-session gsettings set org.gnome.desktop.interface "$@" 2>/dev/null || gsettings set org.gnome.desktop.interface "$@" 2>/dev/null || true; }
gs gtk-theme Graphite-Dark
gs icon-theme Papirus-Dark
gs cursor-theme WhiteCat
gs cursor-size 24
gs color-scheme prefer-dark
ok "GTK: Graphite-Dark, Papirus-Dark, курсор WhiteCat"

# ---------- 7. apps ----------

step "Приложения"
if command -v code-oss >/dev/null; then
    for ext in mhutchie.git-graph MS-CEINTL.vscode-language-pack-ru; do
        code-oss --install-extension "$ext" --force >/dev/null 2>&1 || warn "Code-OSS: не встало $ext"
    done
    ok "Code-OSS: Git Graph, русский язык"
fi

mkdir -p "$HOME/.claude"
cfg="$HOME/.claude/settings.json"
if [ -f "$cfg" ]; then
    jq '.statusLine = {type: "command", command: "~/.claude/statusline.sh"}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
else
    echo '{ "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }' | jq . > "$cfg"
fi
ok "Claude Code: строка лимитов (и модуль в waybar темы claude)"

info "собираю темы для Code-OSS, AyuGram, drift и иконки"
python3 "$HOME/.config/hypr/scripts/themegen.py" build >/dev/null 2>&1 \
    || warn "themegen build завершился с ошибкой (python3 ~/.config/hypr/scripts/themegen.py build)"
ok "темы приложений"

# ---------- 8. theme ----------

step "Тема $THEME"
dbus-run-session "$HOME/.local/bin/changetheme" --offline "$THEME" >/dev/null 2>&1 \
    || "$HOME/.local/bin/changetheme" --offline "$THEME" >/dev/null 2>&1 \
    || warn "changetheme --offline $THEME не отработал, после входа выполни: changetheme $THEME"
ok "применена (менять: Alt+Shift+T или changetheme <тема>)"

echo "$(git -C "$SRC" log -1 --format='%h %cs') $STAMP" > "$MARKER"

# ---------- done ----------

step "Готово"
[ "$DO_BACKUP" = 1 ] && info "Старые файлы: $BACKUP"
if [ ${#WARNINGS[@]} -gt 0 ]; then
    printf '    %sПредупреждения:%s\n' "$YEL" "$R"
    printf '      - %s\n' "${WARNINGS[@]}"
fi
info "Перезагрузись и выбери сеанс Hyprland на экране входа."
info "Alt+F1 — справка по хоткеям, Alt+R — лаунчер, Alt+Enter — терминал."
# Never reboot on RICE_ASSUME alone: an unattended run should leave that to the caller.
if [ -z "${RICE_ASSUME:-}" ] && ask "Перезагрузить сейчас?" n; then
    sudo systemctl reboot
fi
