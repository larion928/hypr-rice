# ~/.config/fish/conf.d/idle_drift.fish

set -g __drift_idle_seconds 120
set -g __drift_runtime (set -q XDG_RUNTIME_DIR; and echo $XDG_RUNTIME_DIR; or echo /tmp)
set -g __drift_marker  $__drift_runtime/fish_drift_$fish_pid.done
set -g __drift_pidfile $__drift_runtime/fish_drift_$fish_pid.timer

function __drift_cleanup_timer
    if test -e $__drift_pidfile
        set -l p (cat $__drift_pidfile 2>/dev/null)
        if test -n "$p"
            kill -9 -$p 2>/dev/null   # убить группу процессов (sh + sleep)
            kill -9  $p 2>/dev/null   # на всякий случай — сам sh
        end
        rm -f $__drift_pidfile
    end
end

# Срабатывает по сигналу USR1 — выполняется в контексте fish, в форграунде
function __drift_run --on-signal SIGUSR1
    test -e $__drift_marker; and return   # уже запускали — не повторяем
    touch $__drift_marker                 # ставим защёлку
    drift --duration 20
end

# Каждый раз при появлении приглашения
function __drift_start --on-event fish_prompt
    test -e $__drift_marker; and return   # drift уже отработал в этом простое — не запускаем таймер
    __drift_cleanup_timer
    sh -c "sleep $__drift_idle_seconds; kill -USR1 $fish_pid" &
    set -l p $last_pid
    echo $p > $__drift_pidfile
    disown
end

# Пользователь начал вводить команду — сбрасываем таймер и защёлку
function __drift_stop --on-event fish_preexec
    __drift_cleanup_timer
    rm -f $__drift_marker
end
