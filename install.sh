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
# RICE_MODE=replace|coexist decides what happens to an existing rice without asking.
set -euo pipefail

REPO_URL="https://github.com/larion928/hypr-rice.git"
BRANCH="${RICE_BRANCH:-main}"
SRC="${RICE_SRC:-$HOME/.local/share/hypr-rice}"
# Written by the first install: the key the rice's commits are signed with (see `rice update`).
TRUST="$HOME/.config/hypr-rice/allowed_signers"

die() { printf '\n\e[31mОшибка:\e[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "запускай от обычного пользователя, не от root (sudo спросят сам)"
command -v pacman >/dev/null || die "нужен Arch Linux или производный дистрибутив (pacman не найден)"
curl -fsSI --max-time 15 https://github.com >/dev/null || die "нет доступа к github.com (интернет?)"

if ! command -v git >/dev/null; then
    echo "    Нужен git, введи пароль sudo:"
    if { : </dev/tty; } 2>/dev/null; then sudo -v </dev/tty; else sudo -v; fi || die "sudo не сработал"
    # A stale database is fixed by a sync together with the upgrade: Arch does not support one without it.
    sudo pacman -S --needed --noconfirm git >/dev/null || sudo pacman -Syu --needed --noconfirm git >/dev/null \
        || die "не удалось поставить git"
fi

# The same check as in rice; it cannot be borrowed from there, rice is not verified yet at this point.
signed_by_author() {
    [ -f "$TRUST" ] || return 0
    git -C "$SRC" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$TRUST" verify-commit "$1" >/dev/null 2>&1
}

# A clone of hypr-rice, by the URL it was cloned from; any other git repository is the user's own.
is_rice_clone() {
    [[ $(git -C "$SRC" config --get remote.origin.url 2>/dev/null) =~ github\.com[:/]larion928/hypr-rice(\.git)?$ ]]
}

echo "==> Скачиваю hypr-rice"
if [ -d "$SRC/.git" ]; then
    is_rice_clone || die "папка $SRC — чужой git-репозиторий, не hypr-rice; выбери другую (RICE_SRC)"
    # The clone is single-branch: another branch is fetched into its own origin/ ref explicitly.
    git -C "$SRC" fetch -q --depth 1 origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
    signed_by_author "origin/$BRANCH" || die "версия на GitHub не подписана ключом автора, ничего не изменено"
    # Checked out as a branch of that name: rice update follows the branch HEAD is on.
    git -C "$SRC" checkout -q -f -B "$BRANCH" "origin/$BRANCH"
else
    # Only an empty or missing folder: RICE_SRC may point at something of the user's.
    [ ! -e "$SRC" ] || [ -z "$(ls -A "$SRC" 2>/dev/null)" ] || die "папка $SRC не пустая и это не hypr-rice, выбери другую (RICE_SRC)"
    rm -rf "$SRC"
    git clone -q --depth 1 -b "$BRANCH" "$REPO_URL" "$SRC"
    signed_by_author HEAD || { rm -rf "$SRC"; die "версия на GitHub не подписана ключом автора, ничего не изменено"; }
fi
echo "    $(git -C "$SRC" log -1 --format='%h  %s')"

exec "$SRC/rice" install
