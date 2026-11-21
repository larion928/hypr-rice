# Packages: pacman with retries and fallback mirrors, the hypr-rice repo of prebuilt AUR packages,
# the AUR itself, multilib; the rice's own package lists.

MIRRORLIST=/etc/pacman.d/mirrorlist
PACMAN_CONF=/etc/pacman.conf

# Mirrors that answered well from Russia and Europe; used when the configured ones fail.
FALLBACK_MIRRORS=(
    "https://mirror.yandex.ru/archlinux/\$repo/os/\$arch"
    "https://mirror.truenetwork.ru/archlinux/\$repo/os/\$arch"
    "https://geo.mirror.pkgbuild.com/\$repo/os/\$arch"
    "https://mirrors.dotsrc.org/archlinux/\$repo/os/\$arch"
    "https://ftp.fau.de/archlinux/\$repo/os/\$arch"
    "https://mirror.netcologne.de/archlinux/\$repo/os/\$arch"
)
MIRRORS_SWAPPED=0
use_fallback_mirrors() {
    [ "$MIRRORS_SWAPPED" = 1 ] && return 1
    [ -f "$MIRRORLIST" ] || return 1
    # Only plain Arch: derivatives (CachyOS, EndeavourOS) ship their own mirror setup.
    grep -q "^Include = /etc/pacman.d/mirrorlist" "$PACMAN_CONF" || return 1
    sudo cp -n "$MIRRORLIST" "$MIRRORLIST.rice-backup"
    { echo "# Fallback mirrors added by hypr-rice; the original is mirrorlist.rice-backup."
      printf 'Server = %s\n' "${FALLBACK_MIRRORS[@]}"
      cat "$MIRRORLIST.rice-backup"; } | sudo_write "$MIRRORLIST"
    MIRRORS_SWAPPED=1
    info "зеркала не отвечают, переключаюсь на запасные (старый список: mirrorlist.rice-backup)"
}

# pacman's messages for a download that failed on the way, as opposed to a refusal (missing
# package, conflict, broken database), where a retry or another mirror changes nothing. A 404
# is not among them: it means a stale package database, which `pacman -Syu` fixes, not a retry.
NETWORK_ERROR='Operation too slow|Could not resolve host|Connection timed out|Connection reset|Failed to connect|SSL connect error|transfer closed|Recv failure|failed to synchronize all databases'

pac() {  # pacman that retries downloads cut off by a flaky network
    # Stalled downloads ("Operation too slow") are common behind throttling; whatever was already
    # fetched stays in the cache, so every retry gets further. From the 2nd failure the fallback
    # mirrors go first, from the 3rd pacman stops giving up on slow transfers.
    local try extra=() errors status
    errors=$(mktemp)
    for try in 1 2 3 4 5 6; do
        # stderr goes to a file for the check below and is shown right after; stdout stays on the
        # terminal with its progress bars. (Copying it live through tee left nothing to wait on
        # safely: $! is the sudo keeper, which runs as long as rice does.)
        status=0
        sudo pacman --noconfirm "${extra[@]}" "$@" 2>"$errors" || status=$?
        cat "$errors" >&2
        if [ "$status" -eq 0 ]; then
            rm -f "$errors"
            return 0
        fi
        grep -qE "$NETWORK_ERROR" "$errors" || break
        [ "$try" -ge 2 ] && { use_fallback_mirrors || true; }
        [ "$try" -ge 3 ] && extra=(--disable-download-timeout)
        [ "$try" -lt 6 ] && info "загрузка прервалась, повтор $((try + 1))/6"
        sleep 3
    done
    rm -f "$errors"
    return 1
}

enable_multilib() {
    grep -q '^\[multilib\]' "$PACMAN_CONF" && return 0
    sudo sed -i '/^#\[multilib\]/{N;s/#\[multilib\]\n#Include/[multilib]\nInclude/}' "$PACMAN_CONF"
    grep -q '^\[multilib\]' "$PACMAN_CONF" || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' \
        | sudo_append "$PACMAN_CONF"
    # With the upgrade, as in setup_pkg_repo: a sync alone would leave a partial upgrade.
    pac -Syu || return 1
    ok "включён репозиторий multilib"
}

# ---------- the hypr-rice repo: prebuilt AUR packages (works where aur.archlinux.org is blocked) ----------

PKG_REPO_URL="https://github.com/larion928/hypr-rice-pkgs/releases/download/repo"
PKG_KEY_FPR=E9E510D6FB25450E897102A01CEA86E55DC9094D

pkg_repo_enabled() { grep -q '^\[hypr-rice\]' "$PACMAN_CONF"; }

setup_pkg_repo() {
    if ! curl -fsSIL --max-time 20 "$PKG_REPO_URL/hypr-rice.db" >/dev/null; then
        warn "репозиторий hypr-rice-pkgs недоступен, AUR-пакеты будут собираться на месте"
        return 0
    fi
    if ! sudo pacman-key --list-keys "$PKG_KEY_FPR" >/dev/null 2>&1; then
        sudo pacman-key --init >/dev/null 2>&1 || true
        sudo pacman-key --add "$SRC/system/hypr-rice-pkgs.asc" >/dev/null
        sudo pacman-key --lsign-key "$PKG_KEY_FPR" >/dev/null
    fi
    if ! pkg_repo_enabled; then
        printf '%s\n' "" "[hypr-rice]" "SigLevel = Required DatabaseOptional" "Server = $PKG_REPO_URL" \
            | sudo_append "$PACMAN_CONF"
        ok "подключён репозиторий hypr-rice (собранные AUR-пакеты)"
    fi
    # Without a fresh sync pacman does not know the repo's packages yet. The sync upgrades too: Arch
    # does not support installing from fresher databases than the system was upgraded from.
    pac -Syu || warn "не удалось обновить систему вместе с базой hypr-rice: rice upgrade"
}

# ---------- the AUR ----------

aur_reachable() { curl -fsSI --max-time 10 https://aur.archlinux.org >/dev/null 2>&1; }

aur_install() {  # AUR packages: hypr-rice repo first, then yay, then the GitHub mirror of the AUR
    local pkg failed=() rest=()
    [ $# -gt 0 ] || return 0
    for pkg in "$@"; do
        pacman -Qq "$pkg" >/dev/null 2>&1 && continue
        if pkg_repo_enabled && pacman -Si "hypr-rice/$pkg" >/dev/null 2>&1; then
            pac -S --needed "hypr-rice/$pkg" >/dev/null && continue
        fi
        rest+=("$pkg")
    done
    [ ${#rest[@]} -gt 0 ] || return 0
    if aur_reachable && ensure_yay; then
        yay -S --needed --noconfirm --answerdiff None --answerclean None --removemake "${rest[@]}" >/dev/null 2>&1 \
            && return 0
    fi
    for pkg in "${rest[@]}"; do
        pacman -Qq "$pkg" >/dev/null 2>&1 && continue
        info "собираю $pkg (PKGBUILD с зеркала AUR на GitHub)"
        build_from_github_mirror "$pkg" >/dev/null 2>&1 || failed+=("$pkg")
    done
    [ ${#failed[@]} -eq 0 ] || { warn "не удалось поставить из AUR: ${failed[*]} (логи: ~/.cache/hypr-rice/build-*.log)"; return 1; }
}

ensure_yay() {
    command -v yay >/dev/null && return 0
    # From the hypr-rice repo when it has it.
    if pacman -Si yay-bin >/dev/null 2>&1; then pac -S --needed yay-bin >/dev/null 2>&1 && return 0; fi
    aur_reachable || return 1
    local dir
    dir=$(mktemp -d)
    git clone -q --depth 1 https://aur.archlinux.org/yay-bin.git "$dir/yay-bin" \
        && (cd "$dir/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$dir"
    command -v yay >/dev/null
}

build_from_github_mirror() {  # PKGBUILD from github.com/archlinux/aur, built here
    local pkg=$1 dir log="$CACHE/build-$1.log" deps k
    mkdir -p "$CACHE"
    dir=$(mktemp -d)
    git clone -q --depth 1 --single-branch --branch "$pkg" https://github.com/archlinux/aur.git "$dir/$pkg" \
        >"$log" 2>&1 || { rm -rf "$dir"; return 1; }
    # makepkg's own dependency install has no retries, so flaky mirrors break it: do it here.
    deps=$(cd "$dir/$pkg" && makepkg --printsrcinfo 2>/dev/null \
        | sed -nE 's/^\s*(depends|makedepends) = ([^<>=]+).*/\2/p' | sort -u || true)
    local d need=()
    # Only what is missing and resolvable from the repos: one AUR name would fail the whole call.
    # shellcheck disable=SC2086
    for d in $(pacman -T $deps 2>/dev/null); do
        pacman -Sp --print-format %n "$d" >/dev/null 2>&1 && need+=("$d")
    done
    [ ${#need[@]} -eq 0 ] || pac -S --needed --asdeps "${need[@]}" >>"$log" 2>&1 || true
    # Upstream signing keys the PKGBUILD trusts (papirus-folders checks its git tag).
    for k in $(cd "$dir/$pkg" && makepkg --printsrcinfo 2>/dev/null | sed -nE 's/^\s*validpgpkeys = (.*)/\1/p'); do
        gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$k" >>"$log" 2>&1 \
            || gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$k" >>"$log" 2>&1 || true
    done
    (cd "$dir/$pkg" && makepkg -si --noconfirm --needed) >>"$log" 2>&1 || { rm -rf "$dir"; return 1; }
    rm -rf "$dir"
}

# ---------- the rice's own packages (packages/base.txt, packages/aur.txt) ----------

# The rice's packages count as installed on purpose: one that was already there as some program's
# dependency would otherwise go with that program (pacman -Rs, or a cleanup of orphans), screenshots
# and the theme generator with it.
mark_rice_packages_explicit() {
    local wanted=() installed=()
    mapfile -t wanted < <(list "$SRC/packages/base.txt"; list "$SRC/packages/aur.txt")
    mapfile -t installed < <(pacman -Qq "${wanted[@]}" 2>/dev/null || true)
    [ ${#installed[@]} -eq 0 ] || sudo pacman -D --asexplicit "${installed[@]}" >/dev/null || true
}
