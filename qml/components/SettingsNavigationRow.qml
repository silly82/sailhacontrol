import QtQuick 2.0
import Sailfish.Silica 1.0

// One navigation row of the Settings overview (SettingsPage.qml): icon,
// title, a one-line summary of the sub-page's current state and an arrow.
BackgroundItem {
    id: row

    property alias iconSource: rowIcon.source
    property alias title: titleLabel.text
    property alias summary: summaryLabel.text
    // Draws attention to a row that needs the user (first run).
    property bool attention: false

    readonly property bool _lit: highlighted || attention

    width: parent ? parent.width : Screen.width
    height: Math.max(Theme.itemSizeMedium, textColumn.height + 2 * Theme.paddingMedium)

    Icon {
        id: rowIcon
        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        highlighted: row._lit
    }

    Column {
        id: textColumn
        anchors {
            left: rowIcon.right
            leftMargin: Theme.paddingLarge
            right: arrow.left
            rightMargin: Theme.paddingMedium
            verticalCenter: parent.verticalCenter
        }

        Label {
            id: titleLabel
            width: parent.width
            truncationMode: TruncationMode.Fade
            color: row._lit ? Theme.highlightColor : Theme.primaryColor
        }

        Label {
            id: summaryLabel
            width: parent.width
            visible: text.length > 0
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: row._lit ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }

    Icon {
        id: arrow
        anchors {
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        source: "image://theme/icon-m-right"
        highlighted: row._lit
    }
}
