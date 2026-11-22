// Settings window (Alt+F2, waybar gear, launcher); the argument picks the page:
//   monitors  Мониторы: layout by dragging, resolution, refresh rate, scale, on/off; applied live with a 15 s
//             "keep?" countdown; kept settings go to ~/.config/hypr/monitors.lua (MonitorsModel).
//   keys      Клавиши: the editable binds, the main modifier, programs' shortcuts, own binds; saved to
//             ~/.config/hypr/binds-user.lua (KeysModel).
//   theme     Тема: the theme list; theme:<name>[:<section>] opens one theme's settings (ThemeEditStore):
//             fonts, colours, wallpapers, panel, icons, cursor, windows, kept in ~/.config/hypr-rice/theme-edits.json.
//   features  Функции: the rice's features switched on and off by features.py, which keeps them in
//             ~/.config/hypr-rice/features.json (FeaturesModel); missing packages are installed first.
//   words     Словарь: the user's own words for the layout fixer's dictionaries (OwnWordsModel, own_words.py);
//             there only while a feature that reads them is on (another page is shown when it goes off).
// Quick switching is the theme picker's (Alt+Shift+T).
import QtQuick
import qs.common
import qs.services

OverlayPanel {
    id: menu

    readonly property var startAt: (argument || "monitors").split(":")
    property string page: startAt[0]
    readonly property bool wordsShown: Features.on("layout-typo") || Features.on("layout-auto")
    onWordsShownChanged: leaveHiddenPage()
    readonly property alias mon: mon
    readonly property alias keys: keys
    readonly property alias themeEdit: themeEdit
    readonly property alias ownThemes: ownThemes
    readonly property alias userFiles: userFiles
    readonly property alias features: features
    readonly property alias ownWords: ownWords

    // Esc: out of a picker, a dialog, the icon picker, a theme's settings; then the window closes. While a combo
    // is being recorded it only stops the recording.
    function back() {
        if (keys.capturing !== "") {
            keys.stopCapture();
        } else if (userFiles.engineOpen) {
            userFiles.engineOpen = false;
        } else if (userFiles.frameSource) {
            userFiles.closeFrames();
        } else if (ownThemes.dialog) {
            if (!ownThemes.busy) {
                ownThemes.dialog = "";
            }
        } else if (themeEdit.install.item) {
            themeEdit.install.dismiss();
        } else if (features.install.item) {
            features.install.dismiss();
        } else if (features.cautioning) {
            features.cautioning = null;
        } else if (features.asking && !features.granting) {
            features.asking = null;
        } else if (themeEdit.iconFor) {
            themeEdit.iconFor = "";
        } else if (themeEdit.editing) {
            themeEdit.editing = null;
        } else {
            close();
        }
    }

    namespace: "settings-panel"
    // A file dialog is open: the window steps aside, the dialog gets the keyboard.
    visible: !(themeEdit.picking || ownThemes.picking || userFiles.picking)
    fadeInMs: 200

    onClosingChanged: {
        if (keys.capturing !== "") {
            keys.stopCapture();
        }
        if (mon.pending) {
            mon.revert();
        }
    }
    onKeyPressed: event => {
        if (keys.capturing !== "") {
            keys.onKey(event);
        }
        event.accepted = true;
    }
    // theme:<name>[:<section>]: that theme's settings, once, as soon as the theme list has it.
    property bool askedOpened: false
    function openAsked() {
        const asked = ThemeList.themes.find(t => t.name === startAt[1]);
        if (!asked || askedOpened) {
            return;
        }
        askedOpened = true;
        themeEdit.open(asked);
        if (startAt[2]) {
            themeEdit.section = startAt[2];
        }
    }

    Component.onCompleted: {
        ThemeList.refresh();
        openAsked();
        leaveHiddenPage();
    }
    function leaveHiddenPage() {
        if (page === "words" && !wordsShown) {
            page = "features";
        }
    }
    Connections {
        target: ThemeList
        function onRefreshed() { menu.openAsked(); }
    }

    MonitorsModel { id: mon }
    KeysModel { id: keys; onCaptureStarted: menu.focusScene() }
    ThemeEditStore { id: themeEdit }
    OwnThemes { id: ownThemes; themeEdit: menu.themeEdit }
    UserFiles { id: userFiles; themeEdit: menu.themeEdit }
    FeaturesModel { id: features }
    OwnWordsModel { id: ownWords }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1280)
        height: Math.min(parent.height - 80, 860)
        radius: Theme.radius(22)
        color: Theme.alpha(Theme.bg, 0.96)
        border.width: Theme.border
        border.color: Theme.alpha(Theme.accent, 0.5)
        MouseArea { anchors.fill: parent; onClicked: menu.focusScene() }

        Row {
            id: header
            x: 32; y: 24
            spacing: 14
            HeaderTitle {
                anchors.verticalCenter: parent.verticalCenter
                icon: "\u{f0493}"
                text: "Настройки"
                size: 30
                markSize: 26
            }
            Item { width: 24; height: 1 }
            Repeater {
                model: [["monitors", "Мониторы"], ["keys", "Клавиши"], ["theme", "Тема"], ["features", "Функции"]]
                       .concat(menu.wordsShown ? [["words", "Словарь"]] : [])
                TabButton {
                    required property var modelData
                    text: modelData[1]
                    active: menu.page === modelData[0]
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: menu.page = modelData[0]
                }
            }
        }
        Text {
            anchors { right: parent.right; rightMargin: 32; verticalCenter: header.verticalCenter }
            text: "Esc закрыть"
            font.family: Theme.bodyFont; font.pixelSize: 14
            color: Theme.muted
        }

        Item {
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; margins: 28; topMargin: 22 }
            MonitorsPage { anchors.fill: parent; visible: menu.page === "monitors"; mon: menu.mon }
            KeysPage { anchors.fill: parent; visible: menu.page === "keys"; keys: menu.keys }
            ThemesPage {
                anchors.fill: parent
                visible: menu.page === "theme"
                themeEdit: menu.themeEdit
                ownThemes: menu.ownThemes
                userFiles: menu.userFiles
                onSwitched: menu.close()
            }
            FeaturesPage { anchors.fill: parent; visible: menu.page === "features"; features: menu.features }
            OwnWordsPage { anchors.fill: parent; visible: menu.page === "words"; ownWords: menu.ownWords }
        }

        // While a combo is being recorded, the wheel and the side buttons of the mouse count as keys.
        MouseArea {
            anchors.fill: parent
            z: 50
            enabled: keys.capturing !== ""
            acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton
            onPressed: mouse => keys.onMouse(mouse.button, mouse.modifiers)
        }

        // Shown while a combo is being recorded.
        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 70 }
            visible: keys.capturing !== ""
            width: captureText.implicitWidth + 48; height: 52
            radius: 26
            color: Theme.bg2
            border.width: 2
            border.color: Theme.accent
            Text {
                id: captureText
                anchors.centerIn: parent
                text: "Нажми сочетание или кнопку мыши (колёсико, боковые) · Esc отмена"
                font.family: Theme.bodyFont; font.pixelSize: 16
                color: Theme.fg
            }
        }
    }
}
