"""The games of the Steam library: the installed ones from its appmanifest files, and its pictures of a game."""
import re

from apptheme import steam

# Steam lists its own tools among the games.
STEAM_TOOLS = re.compile(r"^(Proton|Steam Linux Runtime|Steamworks Common|Steam Runtime)")
# Steam's own pictures of a game, the tall shelf one first. Newer Steam keeps each in a subfolder
# named by its hash, under another name.
STEAM_COVERS = ("library_600x900.jpg", "*/library_capsule.jpg", "header.jpg", "*/library_header.jpg")


def manifest_fields(manifest):
    text = manifest.read_text(errors="replace")
    return dict(re.findall(r'^\s*"(appid|name)"\s*"(.*)"\s*$', text, re.M))


def installed():
    found = {}
    for library in steam.libraries():
        for manifest in sorted((library / "steamapps").glob("appmanifest_*.acf")):
            fields = manifest_fields(manifest)
            if "appid" in fields and "name" in fields and not STEAM_TOOLS.match(fields["name"]):
                found[fields["appid"]] = {"appid": fields["appid"], "name": fields["name"],
                                          "cover": cover(fields["appid"])}
    return sorted(found.values(), key=lambda entry: entry["name"].lower())


def library_of(appid):
    for library in steam.libraries():
        if (library / f"steamapps/appmanifest_{appid}.acf").exists():
            return library
    return None


def cover(appid):
    folder = steam.STEAM / "appcache/librarycache" / str(appid)
    for pattern in STEAM_COVERS:
        found = sorted(folder.glob(pattern))
        if found:
            return str(found[0])
    return ""
