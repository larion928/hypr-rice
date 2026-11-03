"""Obsidian: a CSS snippet in every vault, switched on once; Obsidian reloads changed snippets live."""
import json
from pathlib import Path

from .colors import css_rgba, mix
from .files import GENERATED, write
from .paths import HOME

OBSIDIAN_CSS = """/* Hypr {label}. {generated} */
.theme-dark, .theme-light {{
    --background-primary: {bg};
    --background-primary-alt: {bg2};
    --background-secondary: {side};
    --background-secondary-alt: {bg2};
    --background-modifier-border: {border};
    --background-modifier-hover: {hover};
    --background-modifier-active-hover: {hover};
    --background-modifier-form-field: {bg2};
    --titlebar-background: {side};
    --titlebar-background-focused: {side};
    --tab-container-background: {side};
    --ribbon-background: {side};
    --text-normal: {fg};
    --text-muted: {muted};
    --text-faint: {faint};
    --text-accent: {accent};
    --text-accent-hover: {accent2};
    --text-on-accent: {bg};
    --text-selection: {sel};
    --interactive-accent: {accent};
    --interactive-accent-hover: {accent2};
    --color-accent: {accent};
    --color-accent-1: {accent};
    --color-accent-2: {accent2};
    --link-color: {accent};
    --link-color-hover: {accent2};
    --link-external-color: {accent2};
    --h1-color: {accent};
    --h2-color: {accent2};
    --h3-color: {accent3};
    --code-background: {bg2};
    --code-normal: {fg};
    --blockquote-border-color: {accent};
    --checkbox-color: {accent};
    --tag-color: {accent2};
    --tag-background: {tagbg};
}}
"""


def vaults():
    config = HOME / ".config/obsidian/obsidian.json"
    try:
        return [Path(vault["path"]) for vault in json.loads(config.read_text()).get("vaults", {}).values()]
    except (OSError, ValueError, KeyError, TypeError):
        return []


def apply(theme):
    colors = theme.colors
    css = OBSIDIAN_CSS.format(
        label=theme.label, generated=GENERATED, **colors,
        side=mix(colors["bg"], colors["bg2"], 0.5), border=mix(colors["bg2"], colors["muted"], 0.3),
        hover=css_rgba(colors["accent"], 0.12), faint=mix(colors["muted"], colors["bg"], 0.35),
        sel=css_rgba(colors["accent"], 0.3), tagbg=css_rgba(colors["accent2"], 0.15))
    for vault in vaults():
        settings_dir = vault / ".obsidian"
        if not settings_dir.is_dir():
            continue
        write(settings_dir / "snippets/hypr-rice.css", css)
        appearance = settings_dir / "appearance.json"
        try:
            data = json.loads(appearance.read_text()) if appearance.exists() else {}
        except ValueError:
            continue
        snippets = data.setdefault("enabledCssSnippets", [])
        if "hypr-rice" not in snippets:
            snippets.append("hypr-rice")
            data.setdefault("theme", "obsidian")  # the dark base theme
            appearance.write_text(json.dumps(data, indent=2) + "\n")
