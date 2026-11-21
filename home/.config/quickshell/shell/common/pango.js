.pragma library

// Text for waybar, which reads a module's text and tooltip as Pango markup: "&", "<" and ">" escaped.
function escape(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
