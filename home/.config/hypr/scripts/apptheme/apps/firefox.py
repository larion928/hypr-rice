"""Firefox, Zen and LibreWolf: userChrome, the new tab page and a few prefs; picked up on the next
browser start."""
import base64
import json
import shutil
from pathlib import Path
from string import Template

from ..files import GENERATED, with_block, write, write_bytes
from ..paths import HOME
from . import browser

# The stylesheets are in firefox_css/, ${name} marks what browser.look fills in:
#   chrome.css     the browser's colours, shape and font; emblem.css adds the theme's picture to the menu button
#   tabs.css       Firefox: horizontal tabs, the selected one underlined in the accent
#   zen-tabs.css   Zen: vertical tabs in the sidebar, the selected one marked on its left edge (not the
#                  essentials grid on top). Zen redefines the selected colour on the tab itself, hence the
#                  tab selectors
#   wallpaper.css  Firefox: the wallpaper, heavily dimmed, behind the tab strip and the toolbar. Its URL is
#                  absolute: Firefox resolves a relative one against the sheet that uses the variable
#   zen-wallpaper.css  Zen: its window background (behind the sidebar and on empty tabs) is the wallpaper.
#                  Zen sets these variables inline from its own gradient picker; a user !important still wins
#   newtab.css     the new tab page
CSS_TEMPLATES = Path(__file__).parent / "firefox_css"

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
    found = list(profiles())
    if not found:
        return  # nothing to theme, and the wallpaper not even decoded
    look = browser.look(theme)
    emblem = browser.theme_emblem(theme)
    chrome_css = stylesheet("chrome", generated=GENERATED, **look)
    if emblem:
        chrome_css += stylesheet("emblem")
    newtab_css = None
    if wallpaper and emblem:
        newtab_css = stylesheet(
            "newtab", generated=GENERATED,
            wallpaper=base64.b64encode(browser.wallpaper_jpeg(wallpaper, 1600, 72)).decode(),
            emblem=base64.b64encode(emblem.read_bytes()).decode(), **look)
    window_wallpaper = wallpaper and browser.wallpaper_jpeg(wallpaper, 2560, 82)

    for profile, kind in found:
        chrome = profile / "chrome"
        tabs, wallpaper_sheet = ("zen-tabs", "zen-wallpaper") if kind == "zen" else ("tabs", "wallpaper")
        css = chrome_css + stylesheet(tabs, **look)
        if wallpaper:
            wallpaper_file = chrome / "hypr-rice-wallpaper.jpg"
            write_bytes(wallpaper_file, window_wallpaper)
            css += stylesheet(wallpaper_sheet, wallpaper_url=wallpaper_file.as_uri(), **look)
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


def stylesheet(name, **values):
    return Template((CSS_TEMPLATES / f"{name}.css").read_text()).substitute(values)


def import_sheet(sheet, name):
    text = sheet.read_text() if sheet.exists() else ""
    if f'@import "{name}"' not in text:
        write(sheet.resolve(), f'@import "{name}";\n' + text)


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
    write(path.resolve(), with_block(text, USER_JS_BEGIN, USER_JS_END, block))
