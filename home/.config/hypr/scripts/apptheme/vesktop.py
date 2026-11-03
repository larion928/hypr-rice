"""Vesktop (Discord): a Vencord theme."""
import json
import subprocess

from .colors import css_rgba, mix, rgb
from .files import GENERATED, write
from .paths import HOME

VESKTOP_CSS = """/**
 * @name Hypr {label}
 * @description Colours of the hypr-rice theme {label}. {generated}
 * @author hypr-rice
 * @version 1.0.0
 */
/* Discord's visual-refresh tokens; !important because Discord sets them on deeper selectors. */
:root, .theme-dark, .theme-darker, .theme-midnight, .visual-refresh, .visual-refresh.theme-dark {{
    --font-primary: "{body}", "gg sans", sans-serif !important;
    --font-display: "{display}", "{body}", sans-serif !important;
    --font-code: "{mono}", monospace !important;

    --background-base-lowest: {lowest} !important;
    --background-base-lower: {bg} !important;
    --background-base-low: {low} !important;
    --background-surface-high: {bg2} !important;
    --background-surface-higher: {higher} !important;
    --background-surface-highest: {highest} !important;
    --background-gradient-chat: {bg} !important;
    --chat-background-default: {bg} !important;
    --modal-background: {bg2} !important;
    --card-background-default: {bg2} !important;
    --input-background-default: {input} !important;
    --channeltextarea-background: {input} !important;
    --app-frame-border: {border} !important;

    --background-mod-subtle: {hover} !important;
    --background-mod-muted: {hover} !important;
    --background-mod-normal: {hover2} !important;
    --background-mod-strong: {hover3} !important;
    --interactive-background-hover: {hover} !important;
    --interactive-background-active: {hover2} !important;
    --interactive-background-selected: {selected} !important;
    --message-background-hover: {msghover} !important;

    --border-subtle: {border} !important;
    --border-muted: {border} !important;
    --border-normal: {border2} !important;
    --border-strong: {border3} !important;
    --border-focus: {accent} !important;

    --text-default: {fg} !important;
    --text-strong: {strong} !important;
    --text-muted: {muted} !important;
    --text-subtle: {muted} !important;
    --text-link: {accent} !important;
    --text-brand: {accent} !important;
    --text-code: {accent2} !important;
    --text-feedback-critical: {crit} !important;
    --text-feedback-positive: {good} !important;
    --text-feedback-warning: {warn} !important;
    --interactive-text-default: {muted} !important;
    --interactive-text-hover: {fg} !important;
    --interactive-text-active: {strong} !important;
    --input-placeholder-text-default: {faint} !important;
    --channel-text-area-placeholder: {faint} !important;
    --channel-icon: {muted} !important;
    --icon-default: {fg} !important;
    --icon-strong: {strong} !important;
    --icon-muted: {muted} !important;
    --icon-subtle: {muted} !important;

    --brand-360: {accent_light} !important;
    --brand-400: {accent_light} !important;
    --brand-500: {accent} !important;
    --brand-530: {accent_dark} !important;
    --brand-560: {accent_dark} !important;
    --brand-600: {accent_darker} !important;
    --brand-500-hsl: {accent_hsl} !important;
    --background-brand: {accent} !important;
    --control-brand-foreground: {accent} !important;
    --control-primary-background-default: {accent} !important;
    --control-primary-background-hover: {accent_dark} !important;
    --control-primary-background-active: {accent_darker} !important;
    --control-primary-text-default: {bg} !important;
    --mention-background: {mention} !important;
    --mention-foreground: {accent} !important;

    --status-positive: {good} !important;
    --status-danger: {crit} !important;
    --status-warning: {warn} !important;
    --background-feedback-critical: {critbg} !important;
    --background-feedback-positive: {goodbg} !important;
    --background-feedback-warning: {warnbg} !important;

    --scrollbar-thin-thumb: {thumb} !important;
    --scrollbar-auto-thumb: {thumb} !important;
    --scrollbar-thin-track: transparent !important;
    --scrollbar-auto-track: transparent !important;
}}
::selection {{ background: {sel}; }}
"""

ROOTS = (".config/vesktop", ".var/app/dev.vencord.Vesktop/config/vesktop")
THEME_FILE = "hypr-rice.theme.css"



def hsl(color):
    r, g, b = (v / 255 for v in rgb(color))
    hi, lo = max(r, g, b), min(r, g, b)
    light = (hi + lo) / 2
    if hi == lo:
        return f"0 0% {light * 100:.1f}%"
    chroma = hi - lo
    sat = chroma / (2 - hi - lo) if light > 0.5 else chroma / (hi + lo)
    hue = ((g - b) / chroma % 6) if hi == r else ((b - r) / chroma + 2) if hi == g else ((r - g) / chroma + 4)
    return f"{hue * 60:.1f} calc(var(--saturation-factor, 1)*{sat * 100:.1f}%) {light * 100:.1f}%"


def apply(theme):
    """A Vencord theme in Vesktop's themes folder; Vencord reloads it live. It is switched on in
    settings.json only while Vesktop is closed, since a running Vesktop writes its own copy back."""
    roots = [HOME / r for r in ROOTS if (HOME / r).is_dir()]
    if not roots:
        return
    colors = theme.colors
    css = VESKTOP_CSS.format(
        label=theme.label, generated=GENERATED, body=theme.body_font, display=theme.display, mono=theme.font,
        **colors,
        lowest=mix(colors["bg"], "#000000", 0.25), low=mix(colors["bg"], colors["bg2"], 0.5),
        higher=mix(colors["bg2"], colors["fg"], 0.04), highest=mix(colors["bg2"], colors["fg"], 0.08),
        input=mix(colors["bg2"], colors["fg"], 0.03),
        border=css_rgba(colors["muted"], 0.18), border2=css_rgba(colors["muted"], 0.3),
        border3=css_rgba(colors["muted"], 0.45),
        hover=css_rgba(colors["fg"], 0.06), hover2=css_rgba(colors["fg"], 0.1), hover3=css_rgba(colors["fg"], 0.16),
        selected=css_rgba(colors["accent"], 0.18), msghover=css_rgba(colors["fg"], 0.03),
        strong=mix(colors["fg"], "#ffffff", 0.4), faint=mix(colors["muted"], colors["bg"], 0.3),
        accent_light=mix(colors["accent"], "#ffffff", 0.2), accent_dark=mix(colors["accent"], "#000000", 0.15),
        accent_darker=mix(colors["accent"], "#000000", 0.3), accent_hsl=hsl(colors["accent"]),
        mention=css_rgba(colors["accent"], 0.15), critbg=css_rgba(colors["crit"], 0.15),
        goodbg=css_rgba(colors["good"], 0.15), warnbg=css_rgba(colors["warn"], 0.15),
        thumb=css_rgba(colors["muted"], 0.4), sel=css_rgba(colors["accent"], 0.3))
    running = subprocess.run(["pgrep", "-x", "vesktop"], capture_output=True).returncode == 0
    for root in roots:
        write(root / "themes" / THEME_FILE, css)
        settings = root / "settings/settings.json"
        if running or not settings.exists():
            continue
        try:
            data = json.loads(settings.read_text())
        except ValueError:
            continue
        themes = data.setdefault("enabledThemes", [])
        if THEME_FILE not in themes:
            themes.append(THEME_FILE)
            settings.write_text(json.dumps(data, indent=4) + "\n")
