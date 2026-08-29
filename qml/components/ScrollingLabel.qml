import QtQuick 2.0
import Sailfish.Silica 1.0

// Label that, if its text is wider than the available space, scrolls once
// (pause - scroll to end - pause - scroll back) so the full text can be read,
// then settles back to its normal (clipped) resting position. Re-triggers
// each time a fresh instance appears -- e.g. when a SilicaListView delegate
// scrolls back into view, since delegates aren't reused in this SFOS/Qt
// version (no ListView.reuseItems).
Item {
    id: root

    property alias text: label.text
    property alias color: label.color
    property alias font: label.font
    readonly property real overflow: Math.max(0, label.implicitWidth - root.width)

    implicitHeight: label.implicitHeight
    height: implicitHeight
    clip: true

    Label {
        id: label
        x: 0
        width: implicitWidth
        anchors.verticalCenter: parent.verticalCenter
        truncationMode: TruncationMode.None
    }

    SequentialAnimation {
        running: root.overflow > 0
        loops: 1

        PauseAnimation { duration: 700 }
        NumberAnimation {
            target: label
            property: "x"
            from: 0
            to: -root.overflow
            duration: Math.min(4000, Math.max(900, root.overflow * 12))
            easing.type: Easing.InOutQuad
        }
        PauseAnimation { duration: 700 }
        NumberAnimation {
            target: label
            property: "x"
            from: -root.overflow
            to: 0
            duration: Math.min(4000, Math.max(900, root.overflow * 12))
            easing.type: Easing.InOutQuad
        }
    }
}
