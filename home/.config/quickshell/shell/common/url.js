.pragma library

// A file:// URL for an absolute path. Each path segment is percent-encoded, so a name with
// "#", "%" or "?" (which "file://" + path would read as a fragment, an escape or a query) still
// points at the file. "" for an empty path, so `source: Url.fromPath(x)` shows nothing.
function fromPath(path) {
    if (!path) {
        return "";
    }
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
}
