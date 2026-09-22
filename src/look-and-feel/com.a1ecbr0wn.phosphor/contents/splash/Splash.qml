import QtQuick

// Phosphor splash: a flat #000A00 field, a monospace wordmark, a single
// blinking block cursor and progress shown as text stages. No images, no
// gradients, no glow — just the Plasma splash properties (`stage`, `done`).
Item {
    id: root

    property int stage
    signal done

    readonly property var stageLabels: [
        "starting",
        "loading session",
        "loading window manager",
        "loading desktop",
        "loading panels",
        "ready"
    ]
    readonly property string stageLabel:
        stageLabels[Math.min(stage, stageLabels.length - 1)]

    onStageChanged: if (stage >= 5) doneTimer.start()

    Timer {
        id: doneTimer
        interval: 150
        onTriggered: root.done()
    }

    Rectangle {
        anchors.fill: parent
        color: "#000A00"
    }

    Column {
        anchors.centerIn: parent
        spacing: 18

        Row {
            id: wordmarkRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Text {
                text: "PHOSPHOR"
                color: "#1AFF12"
                font.family: "DM Mono"
                font.pixelSize: 32
                font.letterSpacing: 6
            }

            Rectangle {
                id: cursor
                width: 16
                height: 32
                color: "#1AFF12"
                anchors.verticalCenter: parent.verticalCenter

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    PropertyAnimation { to: 0; duration: 500 }
                    PropertyAnimation { to: 1; duration: 500 }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.stageLabel
            color: "#A0A0A0"
            font.family: "DM Mono"
            font.pixelSize: 14
        }
    }
}
