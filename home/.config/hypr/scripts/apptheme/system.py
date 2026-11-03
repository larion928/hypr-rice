"""What needs root: folder icon colours and the SDDM login screen, through the sudo-allowed helper."""
import subprocess
from pathlib import Path

from .paths import HOME

ROOT_HELPER = "/usr/local/bin/hypr-theme-root"
CHROMIUM_POLICY_DIRS = ("/etc/chromium/policies/managed", "/etc/brave/policies/managed",
                        "/etc/opt/chrome/policies/managed")


def apply(theme, wallpaper):
    if not Path(ROOT_HELPER).exists():
        return
    folders = theme.ui.get("folders")
    stamp = HOME / ".cache/hypr-theme-folders"
    # papirus-folders takes a few seconds; skip it when the colour does not change. The stamp is
    # written only once the helper succeeded, hence the small script (values go in as arguments).
    if folders and (not stamp.exists() or stamp.read_text().strip() != folders):
        run_detached(["sh", "-c", 'sudo -n "$0" folders "$1" >/dev/null && printf "%s\\n" "$1" > "$2"',
                      ROOT_HELPER, folders, str(stamp)])
    if wallpaper:
        colors = theme.colors
        run_detached(["sudo", "-n", ROOT_HELPER, "sddm", wallpaper,
                      colors["accent"], colors["bg"], colors["fg"], theme.display])
    # Older rice versions themed Chromium through a colour policy, which locks out theme extensions.
    if any(Path(folder, "hypr-rice.json").exists() for folder in CHROMIUM_POLICY_DIRS):
        run_detached(["sudo", "-n", ROOT_HELPER, "browser-policy-off"])


def run_detached(argv):
    """Started in the background, so changetheme does not wait for the icon theme to be rewritten."""
    subprocess.Popen(argv, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

