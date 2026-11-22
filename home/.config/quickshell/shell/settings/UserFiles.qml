import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// What the user brings in from files for a theme: cursors (themes and osu! skins), wallpapers taken from a moment
// of a GIF or a video, and video wallpapers from Wallpaper Engine's Steam Workshop subscriptions. themegen.py does
// the work; `message` says what the last step did, or why it did not.
Scope {
    id: userFiles

    required property ThemeEditStore themeEdit
    property string message: ""
    property bool failed: false
    property string pickFor: ""      // "cursor", "frames" or "engine": what the message is about
    property bool picking: false     // a file dialog is open: the window steps aside
    readonly property bool working: runner.running
    // The frame picker: the file, what is read of it (a GIF made into an mp4), its length, the moment shown and
    // its preview.
    property string frameSource: ""
    property string frameInput: ""
    property var frameLength: null   // {kind: gif, frames} or {kind: video, seconds}
    property real frameAt: 0
    property string framePreview: ""
    property int previewNumber: 0    // a new file name per preview: the same name would stay cached
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    // Wallpaper Engine's picker.
    property bool engineOpen: false
    property var engine: null        // {installed, items: [{id, title, type, preview, addable}]}
    property var engineAdded: []     // ids added while the picker is open

    // themegen.py with args; on success then(lines) gets its output, on failure the message says why.
    function run(args, then) {
        runner.start(args, (lines, status) => {
            if (status !== 0) {
                failed = true;
                message = lines.join(" ") || "не вышло";
                return;
            }
            then(lines);
        });
    }
    function say(text) {
        failed = false;
        message = text;
    }
    function pick(kind) {
        pickFor = kind;
        message = "";
        picking = true;
        fileDialog.command = kind === "cursor"
            ? ["zenity", "--file-selection", "--title=Курсор",
               "--file-filter=Курсоры и скины osu! | *.tar.gz *.tgz *.tar.xz *.txz *.tar.bz2 *.zip *.osk"]
            : ["zenity", "--file-selection", "--title=GIF или видео",
               "--file-filter=GIF и видео | *.gif *.mp4 *.webm *.mkv *.mov *.avi *.m4v"];
        fileDialog.running = true;
    }
    function picked(path) {
        if (!path) {
            return;
        }
        if (pickFor === "cursor") {
            addCursor(path);
        } else {
            openFrames(path);
        }
    }

    // ---- cursors
    function addCursor(path) {
        say("Ставлю курсор…");
        run(["cursor-add", path], lines => {
            say("Добавлено: " + JSON.parse(lines[lines.length - 1]).join(", "));
            themeEdit.readCursorThemes();
        });
    }
    function removeCursor(name) {
        run(["cursor-remove", name], lines => {
            if (themeEdit.edit.cursor === name) {
                themeEdit.change("cursor", "");
            }
            say("Курсор \"" + name + "\" удалён");
            themeEdit.readCursorThemes();
        });
    }

    // ---- wallpapers from Wallpaper Engine (video ones are added)
    function openEngine() {
        engineOpen = true;
        engine = null;
        engineAdded = [];
        pickFor = "engine";
        say("Ищу подписки Wallpaper Engine…");
        run(["wallpaper-engine"], lines => {
            engine = JSON.parse(lines[lines.length - 1]);
            say("");
        });
    }
    function addEngine(item) {
        say("Перевожу \"" + item.title + "\" в mp4…");
        run(["wallpaper-engine-add", item.id, themeEdit.ownWallpaperDir()], lines => {
            themeEdit.addWallpaper(lines[lines.length - 1]);
            engineAdded = engineAdded.concat([item.id]);
            say("Добавлено \"" + item.title + "\": сохрани тему, чтобы обои остались");
        });
    }

    // ---- a wallpaper from a moment of a GIF or a video
    function openFrames(path) {
        if (!/\.gif$/i.test(path)) {
            themeEdit.offerAnimated(path);  // a video's frames take ffmpeg
        }
        frameSource = path;
        frameInput = "";
        frameLength = null;
        framePreview = "";
        say(path.toLowerCase().endsWith(".gif") ? "Перевожу GIF в видео для быстрой перемотки…" : "Открываю…");
        run(["frame-prepare", path], lines => {
            const prepared = JSON.parse(lines[lines.length - 1]);
            frameInput = prepared.source;
            frameLength = prepared;
            say("");
            showFrame(0);
        });
    }
    // Closes the picker: its preview and a GIF's mp4 go.
    function closeFrames() {
        forgetPreview();
        if (frameInput && frameInput !== frameSource) {
            Quickshell.execDetached(["python3", Files.themegen, "frame-forget", frameInput]);
        }
        frameInput = "";
        frameSource = "";
    }
    function frameEnd() {
        const length = frameLength;
        return !length ? 0 : length.kind === "gif" ? Math.max(0, length.frames - 1) : Math.max(0, length.seconds - 0.05);
    }
    function frameLabel() {
        const length = frameLength;
        if (!length) {
            return "";
        }
        return length.kind === "gif" ? "кадр " + (Math.round(frameAt) + 1) + " из " + length.frames
                                     : frameAt.toFixed(1) + " с из " + length.seconds.toFixed(1) + " с";
    }
    function showFrame(at) {
        frameAt = at;
        framePreviewTimer.restart();
    }
    function preview() {
        if (runner.running) {
            framePreviewTimer.restart();
            return;
        }
        previewNumber += 1;
        const out = runtime + "/frame-preview-" + previewNumber + ".png";
        run(["frame", frameInput, String(frameAt), out, "960"], lines => {
            forgetPreview();
            framePreview = out;
        });
    }
    function forgetPreview() {
        if (framePreview) {
            Quickshell.execDetached(["rm", "-f", framePreview]);
        }
        framePreview = "";
    }
    function takeFrame() {
        const name = frameSource.split("/").pop().replace(/\.[^.]*$/, "");
        const out = themeEdit.ownWallpaperDir() + "/" + name + "-" + String(frameAt.toFixed(1)).replace(".", "_") + ".png";
        say("Сохраняю кадр…");
        run(["frame", frameInput, String(frameAt), out], lines => {
            themeEdit.addWallpaper(out);
            closeFrames();
            say("Кадр добавлен в обои: сохрани тему, чтобы он остался");
        });
    }

    ScriptRunner { id: runner; script: Files.themegen }
    Process {
        id: fileDialog
        stdout: StdioCollector { onStreamFinished: userFiles.picked(this.text.trim()) }
        onExited: userFiles.picking = false
    }
    // The preview follows the slider once it rests for a moment, not on every step of a drag.
    Timer { id: framePreviewTimer; interval: 180; onTriggered: userFiles.preview() }
}
