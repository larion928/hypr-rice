.pragma library

// colour ("#RRGGBB") at the given opacity (0..1), in Qt's "#AARRGGBB" form; grey when a theme
// does not define the colour.
function withAlpha(colour, opacity) {
    return "#" + ("0" + Math.round(opacity * 255).toString(16)).slice(-2) + String(colour || "#888888").slice(1);
}
