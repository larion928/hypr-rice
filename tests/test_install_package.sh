# ~/.local/bin/rice-install-package: the settings window's package install with the sudo password.

# rice-install-package takes the sudo password on stdin: a wrong one ends with status 2, a right one
# starts the install in the background (repo package through pacman, AUR one through yay with the sudo
# wrapper), whose log ends with "@@done 0"; the password is in no command's arguments, and nothing of
# it is left behind once the install is over.
test_install_package_password() {
    local bin="$HOME/bin" calls="$HOME/calls"
    mkdir -p "$bin" "$HOME/run"
    cat > "$bin/sudo" <<'EOF'
#!/bin/sh
# The fake sudo: -S reads the password from stdin; only "right" passes.
echo "sudo $*" >> "$CALLS"
[ "$1" = -S ] || exit 1
IFS= read -r given
[ "$given" = right ] || exit 1
shift 3  # -S -p ""
[ "$1" = -v ] && exit 0
"$@"
EOF
    printf '#!/bin/sh\necho "pacman $*" >> "$CALLS"\ncase "$1" in -Si) [ "$2" = repo-pkg ] ;; -Q) exit 0 ;; esac\n' > "$bin/pacman"
    printf '#!/bin/sh\necho "yay $*" >> "$CALLS"\n' > "$bin/yay"
    printf '#!/bin/sh\necho "notify-send $*" >> "$CALLS"\n' > "$bin/notify-send"
    chmod +x "$bin"/*
    export CALLS="$calls" XDG_RUNTIME_DIR="$HOME/run" PATH="$bin:$PATH"
    local tool="$REPO/home/.local/bin/rice-install-package" status
    echo wrong | "$tool" repo-pkg >/dev/null; status=$?
    [ "$status" -eq 2 ] || fail "неверный пароль дал код $status"
    [ -z "$(ls -A "$HOME/run")" ] || fail "после неверного пароля остались файлы: $(ls "$HOME/run")"

    echo right | "$tool" repo-pkg >/dev/null || fail "установка из репозитория не запустилась"
    install_finished repo-pkg
    grep -q "^sudo -S -p  pacman -S --needed --noconfirm repo-pkg$" "$calls" || fail "pacman вызван не через sudo -S: $(cat "$calls")"
    echo right | "$tool" aur-pkg >/dev/null || fail "установка из AUR не запустилась"
    install_finished aur-pkg
    grep -q "^yay -S .*--sudo $HOME/run/rice-sudo\.[^ ]*/sudo --mflags --config .*makepkg.conf aur-pkg$" "$calls" || fail "yay вызван без обёртки sudo: $(grep yay "$calls")"
    grep -q "^notify-send .*Установлено: aur-pkg" "$calls" || fail "нет уведомления об установке"
    ! grep -q "right\|wrong" "$calls" || fail "пароль попал в аргументы команд"
    [ -z "$(ls -d "$HOME"/run/rice-sudo.* 2>/dev/null)" ] || fail "остались файлы с паролем"
}

# Waits up to 5 s for the background install of $1 to write its last line.
install_finished() {
    local log="$HOME/run/rice-install-$1.log" tries
    for tries in $(seq 50); do
        grep -q "^@@done 0$" "$log" 2>/dev/null && return 0
        sleep 0.1
    done
    fail "фоновая установка $1 не закончилась: $(cat "$log" 2>/dev/null)"
}
