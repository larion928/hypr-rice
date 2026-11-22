"""qml_members.py SETTINGS_DIR — every member the settings window uses on its stores (themeEdit.save,
panelEditor.slots, ...) is defined in the store's file. QML only notices a missing one when that line runs,
e.g. on the first drag. A store is reached by one name in every file (the file's root id or the property
holding it)."""
import re
import sys
from pathlib import Path

STORES = {
    "PackageInstall": "install", "ThemeEditStore": "themeEdit", "KeysModel": "keys", "MonitorsModel": "mon", "OwnThemes": "ownThemes",
          "UserFiles": "userFiles", "PanelSection": "panelEditor", "OwnWordsModel": "ownWords"}
# What every QML object has.
BUILT_IN = {"running", "command", "text", "x", "y", "width", "height", "visible", "write"}

folder = Path(sys.argv[1])
files = {path: path.read_text() for path in folder.glob("*.qml")}
missing = False
for store, name in STORES.items():
    defined = set(re.findall(r"(?:property\s+\w+(?:<\w+>)?|signal|function)\s+(\w+)", files[folder / f"{store}.qml"]))
    defined |= BUILT_IN
    for path, text in files.items():
        # "/" or "." before: a path in an import, or a member of something else.
        for member in sorted(set(re.findall(rf"(?<![/\w.]){name}\.(\w+)", text)) - defined):
            print(f"{path.name}: {name}.{member} is used but {store}.qml does not define it")
            missing = True
sys.exit(1 if missing else 0)
