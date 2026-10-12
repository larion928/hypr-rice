#!/usr/bin/env bash
# hypr-rice installer. Run it as your normal user (not root) on Arch or an Arch-based distro:
#
#   curl -fsSL https://raw.githubusercontent.com/larion928/hypr-rice/main/install.sh | bash
#
# This only fetches the rice and hands over to its manager, `rice install`; afterwards `rice`
# stays in ~/.local/bin for adding programs, updating and repairs.
#
# Environment: RICE_THEME (default: current theme, else claude), RICE_BRANCH (default main),
# RICE_SRC (where the repo is kept, default ~/.local/share/hypr-rice),
# RICE_ASSUME=y|n answers every yes/no question without asking (unattended runs),
# RICE_APPS=all|none|id,id,... skips the program picker (ids are in packages/apps.txt).
set -euo pipefail

REPO_URL="https://github.com/larion928/hypr-rice.git"
BRANCH="${RICE_BRANCH:-main}"
SRC="${RICE_SRC:-$HOME/.local/share/hypr-rice}"

die() { printf '\n\e[31mОшибка:\e[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "запускай от обычного пользователя, не от root (sudo спросят сам)"
command -v pacman >/dev/null || die "нужен Arch Linux или производный дистрибутив (pacman не найден)"
curl -fsSI --max-time 15 https://github.com >/dev/null || die "нет доступа к github.com (интернет?)"

if ! command -v git >/dev/null; then
    echo "    Нужен git, введи пароль sudo:"
    if { : </dev/tty; } 2>/dev/null; then sudo -v </dev/tty; else sudo -v; fi || die "sudo не сработал"
    sudo pacman -S --needed --noconfirm git >/dev/null || sudo pacman -Sy --needed --noconfirm git >/dev/null \
        || die "не удалось поставить git"
fi

echo "==> Скачиваю hypr-rice"
if [ -d "$SRC/.git" ]; then
    git -C "$SRC" fetch -q --depth 1 origin "$BRANCH"
    git -C "$SRC" reset -q --hard "origin/$BRANCH"
else
    rm -rf "$SRC"
    git clone -q --depth 1 -b "$BRANCH" "$REPO_URL" "$SRC"
fi
echo "    $(git -C "$SRC" log -1 --format='%h  %s')"

exec "$SRC/rice" install
