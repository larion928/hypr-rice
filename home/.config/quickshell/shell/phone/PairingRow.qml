import QtQuick
import qs.common
import qs.services

// Pairing a phone in reach that is not paired: asking it, the phone's own request to accept or turn down, or
// waiting for the phone to answer. Both sides show the same key, so the user can check it is this phone.
Column {
    id: pairing

    property var device

    spacing: 8

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: !pairing.device ? ""
              : pairing.device.requestedByPeer ? "Телефон просит сопряжения. Ключ " + pairing.device.key
                                                 + ", такой же должен быть на телефоне."
              : pairing.device.requested ? "Подтверди на телефоне. Ключ " + pairing.device.key
                                           + ", такой же должен быть на телефоне."
              : "Телефон не сопряжён: без сопряжения с ним ничего нельзя сделать."
        font.family: Theme.bodyFont; font.pixelSize: 13
        color: Theme.fg
    }

    Row {
        spacing: 8
        Chip {
            visible: !!pairing.device && pairing.device.requestedByPeer
            text: "Принять"; primary: true
            onClicked: Phones.act("accept", pairing.device)
        }
        Chip {
            visible: !!pairing.device && pairing.device.requestedByPeer
            text: "Отклонить"
            onClicked: Phones.act("reject", pairing.device)
        }
        Chip {
            visible: !!pairing.device && pairing.device.requested
            text: "Отменить"
            onClicked: Phones.act("reject", pairing.device)
        }
        Chip {
            visible: !!pairing.device && !pairing.device.requested && !pairing.device.requestedByPeer
            text: "Сопрячь"; primary: true
            onClicked: Phones.act("pair", pairing.device)
        }
    }
}
