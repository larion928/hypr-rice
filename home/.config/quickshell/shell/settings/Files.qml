pragma Singleton

import QtQuick
import Quickshell

// Writing the settings window's files (monitors.lua, binds-user.lua, theme-edits.json).
Singleton {
    readonly property string home: Quickshell.env("HOME")
    readonly property string themegen: home + "/.config/hypr/scripts/themegen.py"

    // text as one word for sh -c.
    function quote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'";
    }

    // The file is written whole or not at all (a temporary beside it, renamed over it), and the command `after`
    // runs only when the write succeeded; all detached, in that order.
    function write(path, text, after) {
        Quickshell.execDetached(["sh", "-c",
                                 'tmp="$2.tmp.$$"; printf "%s" "$1" > "$tmp" && mv -f "$tmp" "$2" || { rm -f "$tmp"; exit 1; }\n'
                                 + '[ -z "$3" ] || sh -c "$3"',
                                 "sh", text, path, after || ""]);
    }
}
