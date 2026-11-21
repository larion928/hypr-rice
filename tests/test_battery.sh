# The waybar battery module.

battery() { POWER_SUPPLY_DIR="$HOME/power_supply" python3 "$REPO/home/.config/hypr-rice/waybar/scripts/battery"; }

supply() {  # supply NAME TYPE [FILE=VALUE...]
    local dir="$HOME/power_supply/$1" pair
    mkdir -p "$dir"
    echo "$2" > "$dir/type"
    shift 2
    for pair in "$@"; do echo "${pair#*=}" > "$dir/${pair%%=*}"; done
}

# A desktop has no battery: the module stays hidden instead of showing a red 0%.
test_battery_hidden_without_battery() {
    supply AC Mains online=1
    [ "$(battery | jq -r .text)" = "" ] || fail "модуль виден без батареи: $(battery)"
}

# Batteries and chargers are found by type, whatever the laptop calls them.
test_battery_any_names() {
    supply BAT1 Battery capacity=57 status=Discharging
    supply AC Mains online=1
    local out
    out=$(battery)
    [ "$(jq -r .text <<<"$out")" = "57%" ] || fail "не тот заряд: $out"
    jq -e '.class | index("plugged")' <<<"$out" >/dev/null || fail "зарядка не найдена: $out"
}

# A wireless mouse reports its battery too (scope Device); it is not the laptop's.
test_battery_ignores_mouse() {
    supply hidpp_battery_0 Battery capacity=90 status=Discharging scope=Device
    [ "$(battery | jq -r .text)" = "" ] || fail "батарея мышки принята за батарею ноутбука: $(battery)"
}
