"""Code - OSS: an extension with every theme, built once; the current one picked in settings.json."""
import json
import re
import shutil
import subprocess
import time
import zipfile

from .colors import mix, with_alpha
from .paths import HOME, HYPR

EXTENSION_ID = "larion.hypr-themes"
# Bumped on every build so a running Code - OSS notices the reinstalled themes.
EXTENSION_VERSION = f"1.0.{int(time.time()) // 60}"
SETTINGS = HOME / ".config/Code - OSS/User/settings.json"


def label(theme):
    return f"Hypr {theme.label}"


def apply(theme):
    if not SETTINGS.exists():
        return
    text = SETTINGS.read_text()
    theme_label = label(theme)
    colors = theme.colors
    # Branch lines in Git Graph follow the palette too.
    graph = [colors["accent"], colors["accent2"], colors["good"], colors["warn"],
             colors["accent3"], colors["crit"], colors["muted"]]
    try:
        data = json.loads(text)
        data["workbench.colorTheme"] = theme_label
        data["git-graph.graph.colours"] = graph
        SETTINGS.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    except json.JSONDecodeError:
        # settings.json with comments: patch the single key in place.
        if '"workbench.colorTheme"' in text:
            text = re.sub(r'"workbench\.colorTheme"\s*:\s*"[^"]*"',
                          f'"workbench.colorTheme": "{theme_label}"', text, count=1)
        else:
            text = text.replace("{", f'{{\n  "workbench.colorTheme": "{theme_label}",', 1)
        SETTINGS.write_text(text)


def theme_json(theme):
    colors = theme.code_colors
    bg, bg2, fg, muted = colors["bg"], colors["bg2"], colors["fg"], colors["muted"]
    accent, accent2, accent3 = colors["accent"], colors["accent2"], colors["accent3"]
    border = mix(bg2, muted, 0.3)
    sidebar = mix(bg, bg2, 0.5)
    workbench = {
        "focusBorder": accent, "foreground": fg, "descriptionForeground": muted,
        "selection.background": with_alpha(accent, 0.35), "widget.shadow": "#00000066",
        "editor.background": bg, "editor.foreground": fg,
        "editorCursor.foreground": accent, "editor.selectionBackground": with_alpha(accent, 0.28),
        "editor.inactiveSelectionBackground": with_alpha(accent, 0.14),
        "editor.selectionHighlightBackground": with_alpha(accent2, 0.16),
        "editor.wordHighlightBackground": with_alpha(accent2, 0.14),
        "editor.findMatchBackground": with_alpha(colors["warn"], 0.35),
        "editor.findMatchHighlightBackground": with_alpha(colors["warn"], 0.18),
        "editor.lineHighlightBackground": with_alpha(bg2, 0.8),
        "editorLineNumber.foreground": mix(muted, bg, 0.35), "editorLineNumber.activeForeground": accent,
        "editorIndentGuide.background1": with_alpha(muted, 0.18),
        "editorIndentGuide.activeBackground1": with_alpha(accent, 0.5),
        "editorBracketMatch.background": with_alpha(accent, 0.2), "editorBracketMatch.border": accent,
        "editorWhitespace.foreground": with_alpha(muted, 0.3),
        "editorGutter.addedBackground": colors["good"], "editorGutter.modifiedBackground": colors["warn"],
        "editorGutter.deletedBackground": colors["crit"],
        "editorError.foreground": colors["crit"], "editorWarning.foreground": colors["warn"],
        "editorInfo.foreground": accent2,
        "editorWidget.background": bg2, "editorWidget.border": border,
        "editorSuggestWidget.background": bg2, "editorSuggestWidget.selectedBackground": with_alpha(accent, 0.3),
        "editorSuggestWidget.highlightForeground": accent, "editorHoverWidget.background": bg2,
        "editorGroupHeader.tabsBackground": sidebar, "editorGroup.border": border,
        "tab.activeBackground": bg, "tab.activeForeground": fg, "tab.activeBorderTop": accent,
        "tab.inactiveBackground": sidebar, "tab.inactiveForeground": muted, "tab.border": border,
        "tab.hoverBackground": bg2,
        "titleBar.activeBackground": sidebar, "titleBar.activeForeground": fg,
        "titleBar.inactiveBackground": sidebar, "titleBar.inactiveForeground": muted,
        "activityBar.background": sidebar, "activityBar.foreground": accent,
        "activityBar.inactiveForeground": muted, "activityBar.activeBorder": accent,
        "activityBarBadge.background": accent, "activityBarBadge.foreground": bg,
        "sideBar.background": sidebar, "sideBar.foreground": fg, "sideBar.border": border,
        "sideBarSectionHeader.background": sidebar, "sideBarTitle.foreground": muted,
        "list.activeSelectionBackground": with_alpha(accent, 0.3), "list.activeSelectionForeground": fg,
        "list.inactiveSelectionBackground": with_alpha(accent, 0.16), "list.hoverBackground": with_alpha(accent, 0.1),
        "list.focusOutline": accent, "list.highlightForeground": accent,
        "statusBar.background": sidebar, "statusBar.foreground": muted, "statusBar.border": border,
        "statusBar.debuggingBackground": accent3, "statusBar.debuggingForeground": fg,
        "statusBarItem.remoteBackground": accent, "statusBarItem.remoteForeground": bg,
        "panel.background": bg, "panel.border": border,
        "panelTitle.activeBorder": accent, "panelTitle.activeForeground": fg, "panelTitle.inactiveForeground": muted,
        "input.background": bg2, "input.foreground": fg, "input.border": border,
        "input.placeholderForeground": muted, "inputOption.activeBorder": accent,
        "dropdown.background": bg2, "dropdown.border": border,
        "button.background": accent, "button.foreground": bg, "button.hoverBackground": accent2,
        "button.secondaryBackground": bg2, "button.secondaryForeground": fg,
        "badge.background": accent, "badge.foreground": bg,
        "progressBar.background": accent, "textLink.foreground": accent, "textLink.activeForeground": accent2,
        "scrollbarSlider.background": with_alpha(fg, 0.12), "scrollbarSlider.hoverBackground": with_alpha(fg, 0.22),
        "scrollbarSlider.activeBackground": with_alpha(accent, 0.5),
        "menu.background": bg2, "menu.foreground": fg, "menu.selectionBackground": with_alpha(accent, 0.3),
        "quickInput.background": bg2, "quickInputList.focusBackground": with_alpha(accent, 0.3),
        "notifications.background": bg2, "notificationCenterHeader.background": sidebar,
        "terminal.background": bg, "terminal.foreground": fg, "terminalCursor.foreground": accent,
        "terminal.ansiBlack": bg2, "terminal.ansiRed": colors["crit"], "terminal.ansiGreen": colors["good"],
        "terminal.ansiYellow": colors["warn"], "terminal.ansiBlue": accent, "terminal.ansiMagenta": accent3,
        "terminal.ansiCyan": accent2, "terminal.ansiWhite": fg,
        "terminal.ansiBrightBlack": muted, "terminal.ansiBrightRed": mix(colors["crit"], "#ffffff", 0.2),
        "terminal.ansiBrightGreen": mix(colors["good"], "#ffffff", 0.2),
        "terminal.ansiBrightYellow": mix(colors["warn"], "#ffffff", 0.2),
        "terminal.ansiBrightBlue": accent2, "terminal.ansiBrightMagenta": mix(accent3, "#ffffff", 0.25),
        "terminal.ansiBrightCyan": mix(accent2, "#ffffff", 0.25), "terminal.ansiBrightWhite": "#ffffff",
        "gitDecoration.modifiedResourceForeground": colors["warn"],
        "gitDecoration.untrackedResourceForeground": colors["good"],
        "gitDecoration.deletedResourceForeground": colors["crit"],
        "gitDecoration.ignoredResourceForeground": mix(muted, bg, 0.3),
        "breadcrumb.foreground": muted, "breadcrumb.focusForeground": fg,
        "peekView.border": accent, "peekViewEditor.background": bg2, "peekViewResult.background": sidebar,
    }

    def token(scope, color, style=None):
        settings = {"foreground": color}
        if style:
            settings["fontStyle"] = style
        return {"scope": scope, "settings": settings}

    token_colors = [
        token(["comment", "punctuation.definition.comment"], mix(muted, bg, 0.1), "italic"),
        token(["keyword", "storage.type", "storage.modifier", "keyword.control"], accent),
        token(["keyword.operator", "punctuation"], mix(fg, muted, 0.4)),
        token(["string", "string.quoted", "markup.inline.raw"], colors["good"]),
        token(["constant.character.escape", "string.regexp"], colors["warn"]),
        token(["constant.numeric", "constant.language", "constant.other"], colors["warn"]),
        token(["entity.name.function", "support.function", "meta.function-call"], accent2),
        token(["entity.name.type", "entity.name.class", "support.type", "support.class",
             "entity.other.inherited-class"], mix(accent2, fg, 0.35)),
        token(["variable", "meta.definition.variable"], fg),
        token(["variable.parameter"], mix(fg, accent2, 0.3), "italic"),
        token(["variable.other.property", "variable.other.object.property", "support.variable.property"],
            mix(fg, accent, 0.25)),
        token(["entity.name.tag"], accent),
        token(["entity.other.attribute-name"], accent2, "italic"),
        token(["storage.type.annotation", "meta.annotation", "entity.name.function.decorator"], accent3),
        token(["markup.heading", "entity.name.section"], accent, "bold"),
        token(["markup.bold"], fg, "bold"), token(["markup.italic"], fg, "italic"),
        token(["markup.underline.link"], accent2),
        token(["invalid"], colors["crit"]),
    ]
    return {"name": label(theme), "type": "dark", "colors": workbench, "tokenColors": token_colors,
            "semanticHighlighting": True}


def build(themes):
    """Writes the extension to ~/.config/hypr/build/vscode, packs it as a .vsix and installs it."""
    out = HYPR / "build/vscode"
    shutil.rmtree(out, ignore_errors=True)
    extension = out / "extension"
    (extension / "themes").mkdir(parents=True)
    contributes = []
    for theme in themes:
        (extension / "themes" / f"{theme.name}.json").write_text(json.dumps(theme_json(theme), indent=2))
        contributes.append({"label": label(theme), "uiTheme": "vs-dark",
                            "path": f"./themes/{theme.name}.json"})
    publisher, name = EXTENSION_ID.split(".")
    package = {"name": name, "displayName": "Hypr Themes", "publisher": publisher,
               "version": EXTENSION_VERSION, "description": "Color themes generated from the Hyprland palettes",
               "engines": {"vscode": "^1.60.0"}, "categories": ["Themes"],
               "contributes": {"themes": contributes}}
    (extension / "package.json").write_text(json.dumps(package, indent=2))
    vsix = out / f"{name}-{EXTENSION_VERSION}.vsix"
    pack(extension, vsix, name, publisher)
    if shutil.which("code-oss"):
        subprocess.run(["code-oss", "--install-extension", str(vsix), "--force"], check=False)
    return vsix


VSIX_MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="{name}" Version="{version}" Publisher="{publisher}"/>
    <DisplayName>Hypr Themes</DisplayName>
    <Description xml:space="preserve">Color themes generated from the Hyprland palettes</Description>
    <Categories>Themes</Categories>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.60.0"/>
    </Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
  </Assets>
</PackageManifest>
"""
VSIX_CONTENT_TYPES = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>
"""


def pack(extension, vsix, name, publisher):
    """A .vsix is a zip of the extension folder plus two manifests."""
    with zipfile.ZipFile(vsix, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", VSIX_CONTENT_TYPES)
        archive.writestr("extension.vsixmanifest",
                         VSIX_MANIFEST.format(name=name, version=EXTENSION_VERSION, publisher=publisher))
        for file in extension.rglob("*"):
            if file.is_file():
                archive.write(file, "extension/" + str(file.relative_to(extension)))
