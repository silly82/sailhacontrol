import QtQuick 2.0
import Sailfish.Silica 1.0

// Content of a room header row in the flat room/sensor lists
// (RoomsView.qml, SensorsView.qml). Look borrowed from Silica's
// ExpandingSection (faint highlight gradient, title in highlightColor,
// arrow icon), but as a plain row inside the existing single ListModel:
// ExpandingSection loads its content through a Loader per section, which
// would mean nested models and break the virtualization of the flat list.
//
// The user anchors/sizes it to the row (anchors.fill or a Loader); the
// ListItem itself handles taps and the press highlight.
Item {
    id: root

    property string title
    property int count
    property bool expanded
    // Favorites group: star instead of the arrow.
    property bool favorite
    // false while searching / for the always-open favorites group -- the
    // arrow is then dimmed, since tapping does nothing.
    property bool collapsible: true
    property bool highlighted

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.rgba(Theme.highlightBackgroundColor, 0.1) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Image {
        id: indicator
        x: Theme.horizontalPageMargin - Theme.paddingSmall
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.iconSizeSmallPlus
        height: Theme.iconSizeSmallPlus
        sourceSize.width: Theme.iconSizeSmallPlus
        sourceSize.height: Theme.iconSizeSmallPlus
        // icon-m-down points at the content below: rotated so it points
        // right while collapsed (ExpandingSection uses a right arrow too).
        source: (root.favorite ? "image://theme/icon-m-favorite-selected?" : "image://theme/icon-m-down?")
                + Theme.highlightColor
        rotation: (root.favorite || root.expanded) ? 0 : -90
        opacity: root.collapsible || root.favorite ? 1.0 : Theme.opacityHigh
    }

    Label {
        id: titleLabel
        anchors {
            left: indicator.right
            leftMargin: Theme.paddingMedium
            right: countLabel.left
            rightMargin: Theme.paddingMedium
            verticalCenter: parent.verticalCenter
        }
        text: root.title
        color: root.highlighted ? Theme.secondaryHighlightColor : Theme.highlightColor
        font.pixelSize: Theme.fontSizeMedium
        truncationMode: TruncationMode.Fade
    }

    Label {
        id: countLabel
        anchors {
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        text: root.count
        color: Theme.secondaryHighlightColor
        font.pixelSize: Theme.fontSizeSmall
    }

    Separator {
        anchors.bottom: parent.bottom
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        color: Theme.highlightColor
        horizontalAlignment: Qt.AlignLeft
    }
}
