# ~/.local/bin/proton-run: the Proton it picks, its log and progress card, GameMode.

# A fake umu for proton-run: a package on PYTHONPATH whose main() records PROTONPATH, prints the
# lines in $HOME/umu-output and exits with the status in $HOME/umu-status (0 without the file).
fake_umu() {
    mkdir -p "$HOME/pylib/umu" "$HOME/bin"
    : > "$HOME/pylib/umu/__init__.py"
    cat > "$HOME/pylib/umu/__main__.py" <<'PY'
import os, sys
from pathlib import Path
home = Path(os.environ["HOME"])
def main():
    (home / "protonpath").write_text(os.environ.get("PROTONPATH", ""))
    output = home / "umu-output"
    if output.exists():
        print(output.read_text(), file=sys.stderr, end="")
    status = home / "umu-status"
    return int(status.read_text()) if status.exists() else 0
PY
    for name in quickshell hyprctl; do printf '#!/bin/sh\n:\n' > "$HOME/bin/$name"; done
    printf '#!/bin/sh\necho "$*" >> "%s/notified"\n' "$HOME" > "$HOME/bin/notify-send"
    chmod +x "$HOME/bin"/*
}

proton_run() { PATH="$HOME/bin:$PATH" PYTHONPATH="$HOME/pylib" XDG_RUNTIME_DIR="$HOME" "$REPO/home/.local/bin/proton-run" "$@"; }

# proton-run hands umu the Proton picked in rice proton: a path (Steam's Proton too), or a folder
# name in compatibilitytools.d as older rice wrote it.
test_proton_run_uses_picked_proton() {
    fake_umu
    local steam="$HOME/.local/share/Steam" conf="$HOME/.config/hypr-rice/proton.conf"
    mkdir -p "$HOME/.config/hypr-rice" "$steam/compatibilitytools.d/GE-Proton10-1" \
        "$steam/steamapps/common/Proton - Experimental"

    echo "proton=$steam/steamapps/common/Proton - Experimental" > "$conf"
    proton_run game.exe || fail "proton-run завершился с ошибкой"
    [ "$(cat "$HOME/protonpath")" = "$steam/steamapps/common/Proton - Experimental" ] \
        || fail "по пути: $(cat "$HOME/protonpath")"

    echo "proton=GE-Proton10-1" > "$conf"
    proton_run game.exe
    [ "$(cat "$HOME/protonpath")" = "$steam/compatibilitytools.d/GE-Proton10-1" ] \
        || fail "по имени: $(cat "$HOME/protonpath")"
}

# umu's output goes to the program's log; a start that fails says so (status, notification).
test_proton_run_reports_failed_start() {
    fake_umu
    printf 'INFO: umu-launcher version 1.4.4\nERROR: something broke\n' > "$HOME/umu-output"
    echo 3 > "$HOME/umu-status"
    proton_run game.exe
    [ $? -eq 3 ] || fail "код выхода не передан"
    grep -q 'something broke' "$HOME/.cache/hypr-rice/proton/game.log" || fail "вывод umu не попал в лог"
    grep -q 'game.exe не запустился' "$HOME/notified" || fail "нет уведомления о сбое"
    [ -z "$(ls "$HOME/proton-run")" ] || fail "файл состояния карточки остался"
}

# The card's percent and stage follow umu's output; a download fills its span by the bytes written.
test_proton_run_progress() {
    python3 - "$REPO/home/.local/bin/proton-run" "$HOME" <<'PY' || fail "прогресс считается не так"
import importlib.machinery, importlib.util, json, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("proton_run", sys.argv[1])
spec = importlib.util.spec_from_loader("proton_run", loader)
proton_run = importlib.util.module_from_spec(spec)
loader.exec_module(proton_run)
home = Path(sys.argv[2])
state_file = home / "state.json"
progress = proton_run.Progress(state_file, "game.exe")
def state():
    return json.loads(state_file.read_text())

progress.line("INFO: umu-launcher version 1.4.4")
assert state()["percent"] == 2 and state()["stage"] == "Запускаю umu", state()
progress.line("INFO: Downloading steamrt4 (4.0.1), please wait...")
part = home / "SteamLinuxRuntime_4.tar.xz.parts"
part.write_bytes(b"x" * 1000)
progress.line(f"@@download 2000 {part}")
progress.tick()
assert state()["percent"] == 25, state()  # half of the span from 5 to 45
assert state()["detail"].startswith("0 из 0 МБ"), state()
progress.line("INFO: Running 'Proton - Experimental' using runtime 'steamrt4'")
assert state()["percent"] == 85 and state()["detail"] == "", state()
progress.line("INFO: umu-launcher version 1.4.4")  # an earlier stage again: no step back
assert state()["percent"] == 85, state()
progress.line("fsync: up and running.")
assert state()["stage"] == "Wine запущен, жду окно программы", state()
progress.finish("Запущено")
assert state()["status"] == "done" and state()["percent"] == 100, state()
PY
}

# proton-run starts the game under gamemoderun when GameMode is on.
test_proton_run_gamemode() {
    fake_umu
    printf '#!/bin/sh\necho gamemoderun >> "%s/wrapped"\nexec "$@"\n' "$HOME" > "$HOME/bin/gamemoderun"
    chmod +x "$HOME/bin/gamemoderun"
    proton_run game.exe
    [ ! -e "$HOME/wrapped" ] || fail "gamemoderun без включённого GameMode"
    mkdir -p "$HOME/.config/hypr-rice"
    touch "$HOME/.config/hypr-rice/gamemode"
    proton_run game.exe
    [ "$(cat "$HOME/wrapped")" = gamemoderun ] || fail "игра запущена не через gamemoderun"
}
