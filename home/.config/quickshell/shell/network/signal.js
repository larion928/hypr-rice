.pragma library

// The Wi-Fi icon for a signal strength in percent.
function glyph(signal) {
    const level = signal >= 75 ? 3 : signal >= 50 ? 2 : signal >= 25 ? 1 : 0;
    return ["\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"][level];
}
