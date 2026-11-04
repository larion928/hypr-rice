"""Telegram (AyuGram): a theme file per theme, offered to a running client as a cloud theme link."""
import io
import subprocess
import zipfile

from PIL import Image, ImageEnhance, ImageFilter

from . import wallpaper_still
from .colors import mix
from .files import GENERATED
from .paths import HOME

THEMES_DIR = HOME / ".local/share/hypr-themes/telegram"


def offer(theme):
    # Telegram cannot be themed from outside. A cloud theme link opens its preview with an "Apply"
    # button (a theme file passed on the command line only offers to forward it). Only offered
    # while a client runs, so nothing pops up otherwise. The link (ui.json "telegramSlug") is made
    # by uploading ~/.local/share/hypr-themes/telegram/<name>.tdesktop-theme from a Telegram
    # account; a theme without one (made in the settings window) has nothing to offer.
    slug = theme.ui.get("telegramSlug")
    if not slug:
        return
    link = f"tg://addtheme?slug={slug}"
    for binary in ("AyuGram", "Telegram"):
        if subprocess.run(["pgrep", "-x", binary], capture_output=True).returncode == 0:
            subprocess.Popen([binary, "--", link], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return


def colors_of(theme):
    colors = theme.code_colors
    bg, bg2, fg, muted = colors["bg"], colors["bg2"], colors["fg"], colors["muted"]
    accent, accent2 = colors["accent"], colors["accent2"]
    over = mix(bg, fg, 0.06)
    active = mix(bg, accent, 0.35)
    out_bg = mix(bg2, accent, 0.28)
    return {
        "windowBg": bg, "windowFg": fg, "windowBgOver": over, "windowBgRipple": mix(bg, fg, 0.12),
        "windowFgOver": fg, "windowSubTextFg": muted, "windowSubTextFgOver": mix(muted, fg, 0.3),
        "windowBoldFg": fg, "windowBoldFgOver": fg, "windowBgActive": accent, "windowFgActive": bg,
        "windowActiveTextFg": accent, "windowShadowFg": "#000000", "windowShadowFgFallback": bg2,
        "shadowFg": "#00000040", "imageBg": "#000000", "imageBgTransparent": "#ffffff",
        "activeButtonBg": accent, "activeButtonBgOver": mix(accent, fg, 0.15),
        "activeButtonBgRipple": mix(accent, bg, 0.3),
        "activeButtonFg": bg, "activeButtonFgOver": bg, "activeButtonSecondaryFg": mix(bg, accent, 0.4),
        "activeButtonSecondaryFgOver": mix(bg, accent, 0.4), "activeLineFg": accent,
        "activeLineFgError": colors["crit"],
        "lightButtonBg": bg, "lightButtonBgOver": over, "lightButtonBgRipple": mix(bg, accent, 0.2),
        "lightButtonFg": accent, "lightButtonFgOver": accent, "attentionButtonFg": colors["crit"],
        "attentionButtonFgOver": colors["crit"], "attentionButtonBgOver": mix(bg, colors["crit"], 0.12),
        "outlineButtonBg": bg, "outlineButtonBgOver": over, "outlineButtonOutlineFg": accent,
        "menuBg": bg2, "menuBgOver": mix(bg2, fg, 0.07), "menuBgRipple": mix(bg2, fg, 0.12),
        "menuIconFg": muted, "menuIconFgOver": fg, "menuSubmenuArrowFg": muted, "menuFgDisabled": mix(muted, bg, 0.4),
        "menuSeparatorFg": mix(bg2, muted, 0.3), "scrollBarBg": f"{fg}55", "scrollBarBgOver": f"{fg}88",
        "scrollBg": f"{fg}11", "scrollBgOver": f"{fg}22", "smallCloseIconFg": muted, "smallCloseIconFgOver": fg,
        "radialFg": accent, "radialBg": f"{bg}88", "placeholderFg": muted, "placeholderFgActive": mix(muted, bg, 0.3),
        "inputBorderFg": mix(bg2, muted, 0.5), "filterInputBorderFg": accent, "filterInputInactiveBg": bg2,
        "filterInputActiveBg": bg, "checkboxFg": muted, "sliderBgInactive": mix(bg2, muted, 0.4),
        "sliderBgActive": accent,
        "tooltipBg": bg2, "tooltipFg": fg, "tooltipBorderFg": mix(bg2, muted, 0.3),
        "titleBg": bg2, "titleBgActive": bg2, "titleFg": muted, "titleFgActive": fg,
        "titleButtonFg": muted, "titleButtonFgOver": fg, "titleButtonBgOver": over,
        "trayCounterBg": accent, "trayCounterFg": bg, "layerBg": "#000000aa", "cancelIconFg": muted,
        "boxBg": bg2, "boxTextFg": fg, "boxTextFgGood": colors["good"], "boxTextFgError": colors["crit"],
        "boxTitleFg": fg, "boxSearchBg": bg2, "boxTitleAdditionalFg": muted, "boxTitleCloseFg": muted,
        "dialogsBg": bg, "dialogsNameFg": fg, "dialogsChatIconFg": fg, "dialogsDateFg": muted,
        "dialogsTextFg": muted, "dialogsTextFgService": accent2, "dialogsDraftFg": colors["crit"],
        "dialogsVerifiedIconBg": accent, "dialogsVerifiedIconFg": bg, "dialogsSendingIconFg": muted,
        "dialogsSentIconFg": accent, "dialogsUnreadBg": accent, "dialogsUnreadBgMuted": muted, "dialogsUnreadFg": bg,
        "dialogsBgOver": over, "dialogsBgActive": active, "dialogsNameFgActive": fg, "dialogsTextFgActive": fg,
        "dialogsDateFgActive": fg, "dialogsUnreadBgActive": fg, "dialogsUnreadFgActive": active,
        "dialogsRippleBg": mix(bg, accent, 0.2), "dialogsRippleBgActive": mix(active, fg, 0.15),
        "dialogsForwardBg": active, "dialogsForwardFg": fg,
        "searchedBarBg": bg2, "searchedBarFg": muted, "topBarBg": bg2,
        "historyTextInFg": fg, "historyTextOutFg": fg, "historyCaptionInFg": fg, "historyCaptionOutFg": fg,
        "msgInBg": bg2, "msgInBgSelected": mix(bg2, accent, 0.25), "msgOutBg": out_bg,
        "msgOutBgSelected": mix(out_bg, accent, 0.25), "msgInShadow": "#00000033", "msgOutShadow": "#00000033",
        "msgInServiceFg": accent, "msgOutServiceFg": accent2, "msgInDateFg": muted, "msgOutDateFg": mix(muted, fg, 0.3),
        "msgFileInBg": accent, "msgFileOutBg": accent2, "msgInReplyBarColor": accent, "msgOutReplyBarColor": accent2,
        "historyLinkInFg": accent2, "historyLinkOutFg": accent2, "historyOutIconFg": accent,
        "msgServiceBg": f"{bg}aa", "msgServiceFg": fg, "historyComposeAreaBg": bg2, "historyComposeAreaFg": fg,
        "historyComposeIconFg": muted, "historyComposeIconFgOver": fg, "historySendIconFg": accent,
        "historySendIconFgOver": accent2, "historyPinnedBg": bg2, "historyReplyBg": bg2, "historyReplyIconFg": accent,
        "historyToDownBg": bg2, "historyToDownFg": muted, "historyUnreadBarBg": bg2, "historyUnreadBarFg": accent,
        "sideBarBg": mix(bg, "#000000", 0.2), "sideBarBgActive": mix(bg, accent, 0.25), "sideBarTextFg": muted,
        "sideBarTextFgActive": fg, "sideBarIconFg": muted, "sideBarIconFgActive": accent, "sideBarBadgeBg": accent,
        "sideBarBadgeFg": bg, "emojiPanBg": bg2, "emojiPanCategories": bg2, "emojiIconFg": muted,
        "emojiIconFgActive": accent, "stickerPanDeleteBg": "#000000cc", "mainMenuBg": bg, "mainMenuCoverBg": bg2,
        "mainMenuCoverFg": fg, "notificationBg": bg2, "callBg": bg2, "callNameFg": fg, "callFingerprintBg": bg,
    }


def build(themes):
    THEMES_DIR.mkdir(parents=True, exist_ok=True)
    for theme in themes:
        body = "".join(f"{key}: {value};\n" for key, value in colors_of(theme).items())
        background = chat_background(theme)
        with zipfile.ZipFile(THEMES_DIR / f"{theme.name}.tdesktop-theme", "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("colors.tdesktop-theme", f"// Hypr {theme.label}. {GENERATED}\n" + body)
            if background:
                archive.writestr("background.jpg", background)
    return THEMES_DIR


def chat_background(theme):
    """The theme's first wallpaper, blurred and darkened, as JPEG bytes; None without wallpapers."""
    if not theme.wallpapers:
        return None
    image = Image.open(wallpaper_still.still(theme.wallpapers[0])).convert("RGB")
    image.thumbnail((1920, 1080))
    image = ImageEnhance.Brightness(image.filter(ImageFilter.GaussianBlur(14))).enhance(0.45)
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=85)
    return buffer.getvalue()
