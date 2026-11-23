pragma Singleton

// The animated wallpaper's player (mpvpaper, started by ~/.local/bin/wallpaper) driven through mpv's control
// socket: its sound and its pause. While the shell runs nothing else changes either (wallpaper-hidden pauses
// the player itself only when the shell does not answer).
// The sound plays while the feature wallpaper-sound is on, the clip has a sound track and nothing asks for
// quiet: fullscreen windows hiding the wallpaper (wallpaper-hidden), the lock screen (rice-lock), another MPRIS
// player playing. It fades in and out over fadeMs; faded out, the track is switched off (aid=no), so no audio
// stream stays open. The player starts silent, so a new one (a theme change) gets the sound from here.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

Singleton {
    id: wallpaper

    readonly property int fadeMs: 1000
    // Shorter: ~/.local/bin/wallpaper waits for it before it stops the player (a theme change).
    readonly property int leaveMs: 500
    readonly property int volumeStep: 10
    // "signal" of custom/wallpaper in waybar/config.base.json.
    readonly property int barSignal: 13

    // Told over IPC: by wallpaper-hidden (Hyprland's fullscreen events) and rice-lock.
    property bool hidden: false
    property bool locked: false
    // The player is about to be stopped (silence()); a new one is heard again.
    property bool leaving: false

    readonly property bool connected: player.connected
    readonly property bool soundOn: Features.on("wallpaper-sound")
    readonly property bool otherPlaying: Players.all.some(other => other.isPlaying)
    readonly property bool audible: connected && hasSound && soundOn && !hidden && !locked && !otherPlaying && !leaving
    readonly property bool paused: hidden && Features.on("wallpaper-pause")
    readonly property int volume: settings.volume
    readonly property string status: !soundOn ? "звук выключен"
                                     : hidden ? "тихо, пока обои закрыты окном"
                                     : locked ? "тихо, пока экран заблокирован"
                                     : otherPlaying ? "тихо, пока играет другой плеер"
                                     : "звук включён, громкость " + volume + "%"
    readonly property string barJson: barState()

    // What the player says about its clip.
    property string path: ""  // the file as mpvpaper was given it
    property bool hasSound: false
    property real duration: 0
    property real position: 0
    // Whatever follows the position counts itself here while it does: the wallpaper card while it is open,
    // ClipColour while the theme's own clip plays.
    property int positionWatchers: 0

    // The share of volume mpv plays at; fader moves it.
    property real level: 0

    onAudibleChanged: {
        if (audible) {
            send(["set_property", "aid", "auto"]);
        }
        fadeTo(audible ? 1 : 0, fadeMs);
    }
    onPausedChanged: applyPause()
    onLevelChanged: {
        sendVolume();
        if (level === 0) {
            if (!audible) {
                send(["set_property", "aid", "no"]);
            }
            applyPause();
        }
    }
    onVolumeChanged: sendVolume()
    onBarJsonChanged: waybarModule.refresh()

    // Shown only while the wallpaper has a sound to switch.
    function barState() {
        if (!connected || !hasSound) {
            return JSON.stringify({ text: "", tooltip: "", class: "none" });
        }
        return JSON.stringify({
            text: !soundOn ? "\u{f0581}" : audible ? "\u{f057e}" : "\u{f057f}",
            tooltip: "Обои: " + status + "\nклик: карточка, правый клик: звук, колесо: громкость",
            class: !soundOn ? "off" : audible ? "on" : "quiet"
        });
    }

    function connect() {
        if (!player.connected) {
            retries.left = retries.attempts;
            player.connected = true;
        }
    }

    function switchSound() {
        switchProcess.command = ["python3", Features.script, soundOn ? "off" : "on", "wallpaper-sound"];
        switchProcess.running = true;
    }

    function setVolume(value) {
        settings.volume = Math.max(0, Math.min(100, value));
    }

    function fadeTo(target, fullMs) {
        fader.stop();
        fader.to = target;
        fader.duration = Math.abs(target - level) * fullMs;
        fader.start();
    }

    // The milliseconds until it is silent.
    function silence() {
        const left = Math.round(level * leaveMs);
        leaving = true;
        fadeTo(0, leaveMs);
        leavingTimeout.restart();
        return left;
    }

    // Paused only once the sound has faded out; resumed at once, before it fades in.
    function applyPause() {
        if (!paused) {
            send(["set_property", "pause", false]);
        } else if (level === 0) {
            send(["set_property", "pause", true]);
        }
    }

    function sendVolume() {
        send(["set_property", "volume", Math.round(level * volume)]);
    }

    function send(command, requestId) {
        if (!player.connected) {
            return;
        }
        player.write(JSON.stringify({ command: command, request_id: requestId ?? 0 }) + "\n");
        player.flush();
    }

    // The player's properties asked here; an answer comes back with the request_id it was asked with (index + 1:
    // mpv answers commands sent without one with 0).
    readonly property var asked: ["track-list", "duration", "time-pos", "path"]

    function ask(name) {
        send(["get_property", name], asked.indexOf(name) + 1);
    }

    function receive(line) {
        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            return;
        }
        const name = asked[message.request_id - 1];
        if (name && message.error === "success") {
            take(name, message.data);
        }
    }

    function take(name, data) {
        if (name === "track-list") {
            hasSound = (data || []).some(track => track.type === "audio");
        } else if (name === "duration") {
            duration = data || 0;
        } else if (name === "path") {
            path = data || "";
        } else {
            position = data || 0;
        }
    }

    // A new player knows nothing of the state: it starts silent, unpaused, with its sound track off.
    function greet() {
        ask("track-list");
        ask("duration");
        ask("path");
        applyPause();
    }

    function forget() {
        fader.stop();
        leaving = false;
        level = 0;
        path = "";
        hasSound = false;
        duration = 0;
        position = 0;
    }

    NumberAnimation {
        id: fader
        target: wallpaper
        property: "level"
    }

    Socket {
        id: player
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hypr-rice-wallpaper.sock"
        parser: SplitParser {
            onRead: line => wallpaper.receive(line)
        }
        onConnectedChanged: connected ? wallpaper.greet() : wallpaper.forget()
    }

    // A player that has just opened its layer may not have its socket yet: a few more tries, a second apart.
    Timer {
        id: retries
        readonly property int attempts: 5
        property int left: 0
        interval: 1000
        repeat: true
        running: left > 0 && !player.connected
        onTriggered: {
            left -= 1;
            player.connected = true;
        }
    }

    Timer {
        interval: 500
        repeat: true
        running: player.connected && wallpaper.positionWatchers > 0
        onTriggered: wallpaper.ask("time-pos")
    }

    Process {
        id: switchProcess
    }

    // The player silenced for a stop that did not come (the wallpaper script failed) is heard again.
    Timer {
        id: leavingTimeout
        interval: 10000
        onTriggered: wallpaper.leaving = false
    }

    BarSignal {
        id: waybarModule
        number: wallpaper.barSignal
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/hypr-rice/wallpaper-sound.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: settings
            property int volume: 50
        }
    }

    Component.onCompleted: connect()

    IpcHandler {
        target: "wallpaper"

        // "ok" tells wallpaper-hidden the shell took it (quickshell's own exit status says nothing).
        function hidden(yes: bool): string {
            wallpaper.hidden = yes;
            wallpaper.connect();
            return "ok";
        }
        function locked(yes: bool): string {
            wallpaper.locked = yes;
            return "ok";
        }
        function switchSound(): void {
            wallpaper.switchSound();
        }
        function louder(): void {
            wallpaper.setVolume(wallpaper.volume + wallpaper.volumeStep);
        }
        function quieter(): void {
            wallpaper.setVolume(wallpaper.volume - wallpaper.volumeStep);
        }
        function bar(): string {
            return wallpaper.barJson;
        }
        function silence(): int {
            return wallpaper.silence();
        }
    }
}
