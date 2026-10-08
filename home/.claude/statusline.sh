#!/bin/bash
# Claude Code status line. Also stores the subscription limits (rate_limits) for the waybar
# module ~/.config/waybar/scripts/claude-usage, since Claude Code is the only thing that gets them.
input=$(cat)
cache="$HOME/.cache/claude-usage.json"
if limits=$(jq -ce '.rate_limits // empty' <<<"$input" 2>/dev/null); then
    jq -n --argjson l "$limits" --arg t "$(date +%s)" '{updated: ($t | tonumber), rate_limits: $l}' \
        > "$cache.tmp" && mv "$cache.tmp" "$cache"
fi
jq -r '
    def left(x): if x == null then empty else (100 - x | round | tostring) + "%" end;
    [ (.model.display_name // empty),
      ((.rate_limits.five_hour.used_percentage | left(.)) | "5ч " + .),
      ((.rate_limits.seven_day.used_percentage | left(.)) | "нед " + .)
    ] | join("  ·  ")' <<<"$input" 2>/dev/null
