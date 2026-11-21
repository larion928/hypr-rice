import QtQuick
import qs.common

// Мониторы: the layout to drag screens around in on the left, the selected screen's mode, rate and scale on the
// right, and the "keep these settings?" countdown over both.
Item {
    id: page

    required property MonitorsModel mon

    Rectangle {
        id: layoutBox
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: parent.width * 0.56
        radius: Theme.radius(16)
        color: Theme.alpha(Theme.bg2, 0.8)
        border.color: Theme.alpha(Theme.muted, 0.25)

        readonly property var on: page.mon.edit.filter(m => !m.disabled)
        readonly property real bw: Math.max(1, Math.max(...on.map(m => m.x + page.mon.lw(m)), 1))
        readonly property real bh: Math.max(1, Math.max(...on.map(m => m.y + page.mon.lh(m)), 1))
        readonly property real fit: Math.min((width - 80) / bw, (height - 110) / bh) * 0.8
        readonly property real ox: (width - bw * fit) / 2
        readonly property real oy: (height - 40 - bh * fit) / 2

        Text {
            x: 18; y: 14
            text: "Расположение — перетащи экран мышкой"
            font.family: Theme.bodyFont; font.pixelSize: 14
            color: Theme.muted
        }

        Repeater {
            model: page.mon.edit
            Rectangle {
                id: screenRect
                required property var modelData
                required property int index
                visible: !modelData.disabled
                x: layoutBox.ox + modelData.x * layoutBox.fit
                y: layoutBox.oy + modelData.y * layoutBox.fit + 20
                width: page.mon.lw(modelData) * layoutBox.fit
                height: page.mon.lh(modelData) * layoutBox.fit
                radius: 8
                color: Theme.alpha(Theme.accent, page.mon.sel === index ? 0.3 : 0.12)
                border.width: page.mon.sel === index ? 2 : 1
                border.color: Theme.accent
                Column {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: screenRect.modelData.name
                        font.family: Theme.titleFont; font.pixelSize: 18; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: screenRect.modelData.w + "×" + screenRect.modelData.h + " · "
                              + Math.round(screenRect.modelData.rate) + " Гц · ×" + screenRect.modelData.scale
                        font.family: Theme.bodyFont; font.pixelSize: 13
                        color: Theme.muted
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    drag.target: parent
                    cursorShape: Qt.SizeAllCursor
                    onPressed: page.mon.sel = screenRect.index
                    onReleased: page.mon.drop(screenRect.index, (screenRect.x - layoutBox.ox) / layoutBox.fit,
                                              (screenRect.y - 20 - layoutBox.oy) / layoutBox.fit)
                }
            }
        }
    }

    // Details of the selected screen.
    Flickable {
        anchors { left: layoutBox.right; leftMargin: 24; right: parent.right; top: parent.top; bottom: buttons.top; bottomMargin: 12 }
        contentHeight: details.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: details
            width: parent.width
            spacing: 14
            readonly property var m: page.mon.edit[page.mon.sel] || null

            Row {
                spacing: 8
                Repeater {
                    model: page.mon.edit
                    TabButton {
                        required property var modelData
                        required property int index
                        text: modelData.name
                        active: page.mon.sel === index
                        onClicked: page.mon.sel = index
                    }
                }
            }
            Text {
                visible: !!details.m
                width: parent.width
                text: details.m ? details.m.desc : ""
                wrapMode: Text.Wrap
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.muted
            }

            SectionTitle { text: "Экран" }
            Row {
                spacing: 8
                Chip { text: "Включён"; active: !!details.m && !details.m.disabled; onClicked: page.mon.setField(page.mon.sel, "disabled", false) }
                Chip { text: "Выключен"; active: !!details.m && details.m.disabled; onClicked: page.mon.setField(page.mon.sel, "disabled", true) }
            }

            SectionTitle { text: "Разрешение" }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: details.m ? [...new Set(details.m.modes.map(x => x.w + "x" + x.h))]
                                         .sort((p, q) => q.split("x")[0] * q.split("x")[1] - p.split("x")[0] * p.split("x")[1]) : []
                    Chip {
                        required property string modelData
                        text: modelData.replace("x", "×")
                        active: !!details.m && modelData === details.m.w + "x" + details.m.h
                        onClicked: page.mon.setField(page.mon.sel, "res", modelData)
                    }
                }
            }

            SectionTitle { text: "Частота" }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: details.m ? details.m.modes.filter(x => x.w === details.m.w && x.h === details.m.h)
                                         .map(x => x.rate).filter((v, i, s) => s.indexOf(v) === i).sort((p, q) => q - p) : []
                    Chip {
                        required property real modelData
                        text: (Math.round(modelData * 100) / 100) + " Гц"
                        active: !!details.m && Math.abs(modelData - details.m.rate) < 0.01
                        onClicked: page.mon.setField(page.mon.sel, "rate", modelData)
                    }
                }
            }

            SectionTitle { text: "Масштаб" }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: [1, 1.25, 1.5, 1.75, 2]
                    Chip {
                        required property real modelData
                        text: "×" + modelData
                        active: !!details.m && Math.abs(modelData - details.m.scale) < 0.01
                        onClicked: page.mon.setField(page.mon.sel, "scale", modelData)
                    }
                }
            }
        }
    }

    Row {
        id: buttons
        anchors { right: parent.right; bottom: parent.bottom }
        spacing: 10
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: page.mon.status
            font.family: Theme.bodyFont; font.pixelSize: 14
            color: Theme.accent2
        }
        Chip { text: "Сбросить"; enabled: page.mon.changed(); onClicked: page.mon.resetEdit() }
        Chip { text: "Применить"; primary: true; enabled: page.mon.changed(); onClicked: page.mon.apply() }
    }

    // "Keep these settings?" with a countdown.
    Rectangle {
        anchors.centerIn: parent
        visible: page.mon.pending
        width: 520; height: 190
        radius: Theme.radius(16)
        color: Theme.bg2
        border.width: 2
        border.color: Theme.accent
        Column {
            anchors.centerIn: parent
            spacing: 18
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Оставить эти настройки?"
                font.family: Theme.titleFont; font.pixelSize: 24
                color: Theme.fg
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Вернётся как было через " + page.mon.countdown + " с"
                font.family: Theme.bodyFont; font.pixelSize: 15
                color: Theme.muted
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Chip { text: "Вернуть"; onClicked: page.mon.revert() }
                Chip { text: "Оставить"; primary: true; onClicked: page.mon.keep() }
            }
        }
    }
}
