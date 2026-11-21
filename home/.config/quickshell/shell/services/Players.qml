pragma Singleton

// The MPRIS players and the active one, which the player card, the media keys and waybar's custom/player all
// control: the player that started playing last, or the one picked in the card, until another starts. Media
// keys reach it over IPC (`call player togglePlaying`); waybar's module asks bar() and is signalled to ask again
// when the track or its state changes.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: players

    readonly property string musicGlyph: "\u{f0388}"
    readonly property string pauseGlyph: "\u{f03e4}"
    // "signal" of custom/player in waybar/config.base.json.
    readonly property int barSignal: 11

    // playerctld (started by any `playerctl` call) is no player of its own: it mirrors the last active one and
    // would show up twice and take over as the latest.
    readonly property var all: Mpris.players.values.filter(player => !isProxy(player))
    // The player that started playing last or was picked last; QML clears it when that player quits.
    property MprisPlayer latest: null
    readonly property MprisPlayer active: latest ?? all.find(player => player.isPlaying) ?? all[0] ?? null
    readonly property string barJson: barState(active)

    function isProxy(player) {
        return player.dbusName === "org.mpris.MediaPlayer2.playerctld";
    }

    function pick(player) {
        latest = player;
    }

    function barState(player) {
        if (!player || !player.trackTitle) {
            return JSON.stringify({ text: musicGlyph, tooltip: "Плеер: ничего не играет", class: "none" });
        }
        const track = player.trackArtist ? player.trackArtist + " — " + player.trackTitle : player.trackTitle;
        return JSON.stringify({
            text: (player.isPlaying ? musicGlyph : pauseGlyph) + " " + markup(player.trackTitle),
            tooltip: markup(track) + "\n" + markup(player.identity),
            class: player.isPlaying ? "playing" : "paused"
        });
    }

    // Waybar reads the text as Pango markup.
    function markup(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    onBarJsonChanged: barRefresh.restart()

    // A track change sends several property changes at once: one signal for all of them.
    Timer {
        id: barRefresh
        interval: 150
        onTriggered: barSignalProcess.running = true
    }

    Process {
        id: barSignalProcess
        command: ["pkill", "-RTMIN+" + players.barSignal, "-x", "waybar"]
    }

    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property MprisPlayer modelData
            target: modelData
            function onIsPlayingChanged() {
                if (modelData.isPlaying && !players.isProxy(modelData)) {
                    players.latest = modelData;
                }
            }
        }
    }

    IpcHandler {
        target: "player"

        function togglePlaying(): void {
            if (players.active?.canTogglePlaying) {
                players.active.togglePlaying();
            }
        }
        function next(): void {
            if (players.active?.canGoNext) {
                players.active.next();
            }
        }
        function previous(): void {
            if (players.active?.canGoPrevious) {
                players.active.previous();
            }
        }
        function bar(): string {
            return players.barJson;
        }
    }
}
