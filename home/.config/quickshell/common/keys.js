.pragma library

// A key's name by where it sits on the keyboard, not by the letter the layout puts there: on the
// Russian layout the H key sends "р" (e.key is Qt.Key_Cyrillic_ER), so panels compare names from
// here instead of Qt.Key_H or e.text. The names are Hyprland's (US positions), so the settings panel
// writes them straight into binds. nativeScanCode is the XKB keycode (evdev code + 8).
const byScanCode = {
    10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0",
    20: "minus", 21: "equal", 24: "Q", 25: "W", 26: "E", 27: "R", 28: "T", 29: "Y", 30: "U",
    31: "I", 32: "O", 33: "P", 34: "bracketleft", 35: "bracketright", 38: "A", 39: "S", 40: "D",
    41: "F", 42: "G", 43: "H", 44: "J", 45: "K", 46: "L", 47: "semicolon", 48: "apostrophe",
    49: "grave", 51: "backslash", 52: "Z", 53: "X", 54: "C", 55: "V", 56: "B", 57: "N", 58: "M",
    59: "comma", 60: "period", 61: "slash"
};

// "" for keys outside the letter and digit rows (arrows, F-keys, Return...): compare e.key for those.
function of(event) {
    return byScanCode[event.nativeScanCode] || "";
}
