.pragma library

// A key's name by where it sits on the keyboard, not by the letter the layout puts there: on the
// Russian layout the H key sends "р" (e.key is Qt.Key_Cyrillic_ER), so menus compare names from
// here instead of Qt.Key_H or e.text. The names are Hyprland's (US positions), so the settings window
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

// How far a key moves the selection in a grid `columns` wide: arrows, Tab and Shift+Tab, and vim's H J K L.
// 0 for any other key. The menu wraps or clamps the result itself.
function step(event, columns) {
    const name = of(event);
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || name === "H") {
        return -1;
    }
    if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab || name === "L") {
        return 1;
    }
    if (event.key === Qt.Key_Up || name === "K") {
        return -columns;
    }
    if (event.key === Qt.Key_Down || name === "J") {
        return columns;
    }
    return 0;
}

// How far a key moves the selection in a list under a text field: Down/Tab/Ctrl+J and Up/Shift+Tab/Ctrl+K.
// Plain letters, and Left/Right, belong to the text, so they give 0.
function listStep(event) {
    const name = of(event);
    const control = event.modifiers & Qt.ControlModifier;
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (control && name === "J")) {
        return 1;
    }
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (control && name === "K")) {
        return -1;
    }
    return 0;
}

function isEnter(event) {
    return event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
}
