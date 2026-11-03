"""Firefox, Zen and LibreWolf: userChrome, the new tab page and a few prefs; picked up on the next
browser start."""
import base64
import json
import shutil

from . import browser
from .files import GENERATED, with_block, write, write_bytes
from .paths import HOME

FIREFOX_CHROME_CSS = """/* Hypr {label}. {generated} */
:root {{
    --hypr-radius: {radius}px;
    --toolbox-background-color: {side} !important;
    --toolbox-background-color-inactive: {side} !important;
    --toolbox-text-color: {fg} !important;
    --toolbox-text-color-inactive: {muted} !important;
    --toolbar-background-color: {side} !important;
    --toolbar-text-color: {fg} !important;
    --toolbar-field-background-color: {field} !important;
    --toolbar-field-background-color-focus: {field} !important;
    --toolbar-field-text-color: {fg} !important;
    --toolbar-field-text-color-focus: {fg} !important;
    --toolbar-field-border-color: transparent !important;
    --toolbar-field-border-color-focus: {accent} !important;
    --toolbarbutton-icon-fill: {fg} !important;
    --toolbarbutton-background-color-hover: {hover} !important;
    --toolbarbutton-background-color-active: {selected} !important;
    --toolbarbutton-border-radius: var(--hypr-radius) !important;
    --tab-background-color-selected: {selected} !important;
    --tab-text-color-selected: {fg} !important;
    --tab-icon-fill-loading: {accent} !important;
    --tab-border-radius: var(--hypr-radius) !important;
    --lwt-tab-line-color: {accent} !important;
    --tabs-navbar-separator-color: transparent !important;
    --chrome-content-separator-color: transparent !important;
    --tabpanel-background-color: {bg} !important;
    --sidebar-background-color: {side} !important;
    --sidebar-text-color: {fg} !important;
    --sidebar-border-color: transparent !important;
    --panel-background-color: {bg2} !important;
    --panel-text-color: {fg} !important;
    --panel-border-color: {border} !important;
    --panel-border-radius: var(--hypr-radius) !important;
    --urlbarview-background-color-selected: {accent} !important;
    --urlbarview-text-color-selected: {bg} !important;
    --urlbarview-background-color-hover: {hover} !important;
    --border-color: {border} !important;
    --focus-outline-color: {accent} !important;
    --color-accent-primary: {accent} !important;
    --color-accent-primary-hover: {accent2} !important;
    --color-accent-primary-active: {accent2} !important;
    --button-background-color-primary: {accent} !important;
    --button-background-color-primary-hover: {accent2} !important;
    --button-text-color-primary: {bg} !important;
    /* Zen mixes most of its colours from these two. */
    --zen-primary-color: {accent} !important;
    --zen-branding-bg: {bg} !important;
    --zen-colors-border: {border} !important;
}}

#navigator-toolbox, #sidebar-box, menupopup, panel {{
    font-family: "{font}", sans-serif !important;
}}

.tabbrowser-tab:not([selected], [visuallyselected]):hover > .tab-stack > .tab-background {{
    background: {hover} !important;
}}
.tabbrowser-tab:is([selected], [visuallyselected], [multiselected]) > .tab-stack > .tab-background {{
    background: {selected} !important;
}}

:is(#urlbar-background, #urlbar .urlbar-background) {{
    background-color: {field} !important;
    border-radius: var(--hypr-radius) !important;
}}
#urlbar:is([focused], [open]) :is(#urlbar-background, .urlbar-background) {{
    outline: {line}px solid {accent} !important;
    box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45){glow} !important;
}}

menupopup, panel {{
    --panel-border-radius: var(--hypr-radius) !important;
}}
menuitem:hover, menu:hover, menuitem[_moz-menuactive], menu[_moz-menuactive] {{
    background-color: {selected} !important;
}}
"""

FIREFOX_EMBLEM_CSS = """
#PanelUI-menu-button .toolbarbutton-icon {
    list-style-image: url("hypr-rice-emblem.svg") !important;
}
"""

# Firefox: horizontal tabs, the selected one underlined in the accent.
FIREFOX_TABS_CSS = """
.tabbrowser-tab:is([selected], [multiselected]) > .tab-stack > .tab-background {{
    box-shadow: inset 0 -{line}px 0 {accent}{glow} !important;
}}
"""

# Firefox: the wallpaper, heavily dimmed, behind the tab strip and the toolbar.
# The URL is absolute: Firefox resolves a relative one against the sheet that uses the variable.
FIREFOX_WALLPAPER_CSS = """
#navigator-toolbox {{
    background: linear-gradient({dim}, {dim}), url("{wallpaper_url}") center 35% / cover !important;
}}
#TabsToolbar, #nav-bar, #PersonalToolbar {{
    background: transparent !important;
}}
"""

# Zen: vertical tabs in the sidebar, the selected one marked on its left edge (not the essentials
# grid on top). Zen redefines the selected colour on the tab itself, hence the tab selectors.
ZEN_TABS_CSS = """
:root {{
    --zen-toolbar-element-bg: {hover} !important;
    --zen-toolbar-element-bg-hover: {selected} !important;
}}
.tabbrowser-tab:not([zen-essential]):is([visuallyselected], [multiselected]) > .tab-stack > .tab-background {{
    box-shadow: inset {line_zen}px 0 0 {accent}{glow} !important;
}}
.tabbrowser-tab:is([visuallyselected], [multiselected]) {{
    --tab-background-color-selected: {selected} !important;
}}
/* The sidebar gets its own dimmed glass over the wallpaper, so the tab list stays readable. */
#navigator-toolbox {{
    background: {sidebar_glass} !important;
    backdrop-filter: blur(18px) !important;
}}
#urlbar[zen-floating-urlbar="true"] .urlbar-background {{
    background-color: {field} !important;
    outline: {line}px solid {accent_soft} !important;
}}
"""

# Zen: its window background (behind the sidebar and on empty tabs) is the wallpaper. Zen sets
# these variables inline from its own gradient picker; a user !important still wins.
ZEN_WALLPAPER_CSS = """
#zen-browser-background, #zen-toolbar-background {{
    --zen-main-browser-background: linear-gradient({dim}, {dim}), url("{wallpaper_url}") center / cover !important;
    --zen-main-browser-background-toolbar: linear-gradient({dim}, {dim}), url("{wallpaper_url}") center / cover !important;
}}
"""

FIREFOX_NEWTAB_CSS = """/* Hypr {label}: the new tab page. {generated} */
@-moz-document url("about:newtab"), url("about:home") {{
    :root {{
        --newtab-background-color: {bg} !important;
        --newtab-background-color-secondary: {bg2} !important;
        --newtab-text-primary-color: {fg} !important;
        --newtab-text-secondary-color: {muted} !important;
        --newtab-primary-action-background: {accent} !important;
        --newtab-element-hover-color: {hover} !important;
        --color-accent-primary: {accent} !important;
        --color-accent-primary-hover: {accent2} !important;
        --color-accent-primary-active: {accent2} !important;
        --button-background-color-primary: {accent} !important;
        --button-background-color-primary-hover: {accent2} !important;
        --button-text-color-primary: {bg} !important;
    }}
    body {{
        background: linear-gradient(rgba(0, 0, 0, 0.25), rgba(0, 0, 0, 0.45)),
                    {bg} url("data:image/jpeg;base64,{wallpaper}") center / cover no-repeat fixed !important;
    }}
    .logo-and-wordmark .logo {{
        background-image: url("data:image/svg+xml;base64,{emblem}") !important;
        background-size: contain !important;
        filter: drop-shadow(0 4px 14px rgba(0, 0, 0, 0.6));
    }}
    .logo-and-wordmark .wordmark {{
        display: none !important;
    }}
    .logo-and-wordmark::after {{
        content: "{label}";
        margin-inline-start: 18px;
        font: {title_style} 600 46px "{display}", serif;
        text-transform: {title_case};
        color: {fg};
        text-shadow: 0 2px 14px rgba(0, 0, 0, 0.7);
    }}
    /* The search box is a custom element; its shadow DOM only takes these variables. */
    .search-wrapper content-search-handoff-ui {{
        --content-search-handoff-ui-background-color: {dim} !important;
        --content-search-handoff-ui-color: {fg} !important;
        --content-search-handoff-ui-fill: {muted} !important;
        --content-search-handoff-ui-border-radius: {radius}px !important;
        --content-search-handoff-ui-border-width: {line}px !important;
        --content-search-handoff-ui-unfocused-border-color: {accent_soft} !important;
        --content-search-handoff-ui-fakefocus-border-color: {accent} !important;
        --content-search-handoff-ui-fakefocus-box-shadow-inner: {accent_soft} !important;
        backdrop-filter: blur(14px);
        border-radius: {radius}px;
        box-shadow: 0 8px 30px rgba(0, 0, 0, 0.4){glow};
    }}
    .top-site-outer .tile {{
        background-color: {dim} !important;
        border-radius: {radius}px !important;
        backdrop-filter: blur(10px);
    }}
    .top-site-outer:hover .tile {{
        outline: {line}px solid {accent} !important;
    }}
    .top-site-outer .title {{
        color: {fg} !important;
        text-shadow: 0 1px 6px rgba(0, 0, 0, 0.9);
    }}
}}
"""

# Profile roots: (path, browser). Newer Firefox keeps profiles under XDG (~/.config/mozilla).
PROFILE_ROOTS = ((".config/mozilla/firefox", "firefox"), (".mozilla/firefox", "firefox"),
                         (".librewolf", "firefox"), (".var/app/io.gitlab.librewolf-community/.librewolf", "firefox"),
                         (".zen", "zen"), (".config/zen", "zen"))
USER_JS_BEGIN = "// hypr-rice begin: rewritten on every theme change"
USER_JS_END = "// hypr-rice end"
# Older rice versions wrote this line on its own, outside the block.
USER_JS_LEGACY = 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'


def profiles():
    for root, browser in PROFILE_ROOTS:
        for profile in (HOME / root).glob("*"):
            if (profile / "prefs.js").exists():
                yield profile, browser


def apply(theme, wallpaper=None):
    look = browser.look(theme)
    emblem = browser.theme_emblem(theme)
    chrome_css = FIREFOX_CHROME_CSS.format(generated=GENERATED, **look)
    if emblem:
        chrome_css += FIREFOX_EMBLEM_CSS
    newtab_css = None
    if wallpaper and emblem:
        newtab_css = FIREFOX_NEWTAB_CSS.format(
            generated=GENERATED,
            wallpaper=base64.b64encode(browser.wallpaper_jpeg(wallpaper, 1600, 72)).decode(),
            emblem=base64.b64encode(emblem.read_bytes()).decode(), **look)
    window_wallpaper = wallpaper and browser.wallpaper_jpeg(wallpaper, 2560, 82)

    for profile, kind in profiles():
        chrome = profile / "chrome"
        tabs_css, wallpaper_css = (ZEN_TABS_CSS, ZEN_WALLPAPER_CSS) if kind == "zen" \
            else (FIREFOX_TABS_CSS, FIREFOX_WALLPAPER_CSS)
        css = chrome_css + tabs_css.format(**look)
        if wallpaper:
            wallpaper_file = chrome / "hypr-rice-wallpaper.jpg"
            write_bytes(wallpaper_file, window_wallpaper)
            css += wallpaper_css.format(wallpaper_url=wallpaper_file.as_uri(), **look)
        write(chrome / "hypr-rice.css", css)
        if emblem:
            shutil.copyfile(emblem, chrome / "hypr-rice-emblem.svg")
        # Our sheets are imported, so userChrome/userContent of the user's own keep working.
        import_sheet(chrome / "userChrome.css", "hypr-rice.css")
        if newtab_css:
            # Inlined: about:newtab does not load file:// images.
            write(chrome / "hypr-rice-content.css", newtab_css)
            import_sheet(chrome / "userContent.css", "hypr-rice-content.css")
        write_user_js(profile / "user.js", prefs_for(kind, look))


def import_sheet(sheet, name):
    text = sheet.read_text() if sheet.exists() else ""
    if f'@import "{name}"' not in text:
        sheet.write_text(f'@import "{name}";\n' + text)


def prefs_for(kind, look):
    prefs = {
        "toolkit.legacyUserProfileCustomizations.stylesheets": True,
        # Dark browser UI and dark-scheme pages: every theme is dark.
        "browser.theme.toolbar-theme": 0,
        "browser.theme.content-theme": 0,
    }
    if kind == "zen":
        prefs.update({
            "zen.theme.accent-color": look["accent"],
            "zen.theme.border-radius": look["radius"],
            "zen.view.window.scheme": 0,
        })
    return prefs


def write_user_js(path, prefs):
    """user.js is applied on every start; our prefs live in one marked block, the rest is the user's."""
    text = path.read_text() if path.exists() else ""
    text = text.replace(USER_JS_LEGACY + "\n", "")
    block = [f"user_pref({json.dumps(key)}, {json.dumps(value)});" for key, value in prefs.items()]
    path.write_text(with_block(text, USER_JS_BEGIN, USER_JS_END, block))
