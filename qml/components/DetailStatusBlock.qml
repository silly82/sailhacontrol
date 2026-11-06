import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/EntityIcons.js" as EntityIcons

// Top block of every entity detail page: large domain icon on the left, the
// main value (brightness, temperature, position, alarm state, title,
// battery ...) in a large font, and an optional secondary line below it.
Item {
    id: block

    // HA domain (+ entity_id/unit for sensors), see EntityIcons.js.
    property string domain
    property string entityId
    property string unit
    // Tint of the icon: highlightColor while "active" (on/playing/armed),
    // secondaryColor otherwise -- pages decide.
    property color iconColor: Theme.highlightColor
    property string value
    property color valueColor: Theme.highlightColor
    property string detail
    property color detailColor: Theme.secondaryHighlightColor

    x: Theme.horizontalPageMargin
    width: (parent ? parent.width : Screen.width) - 2 * Theme.horizontalPageMargin
    height: Math.max(icon.height, texts.height)

    Icon {
        id: icon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.iconSizeLarge
        height: width
        sourceSize.width: width
        sourceSize.height: height
        source: "image://theme/" + EntityIcons.iconFor(block.domain, block.entityId, block.unit) + "?" + block.iconColor
    }

    Column {
        id: texts
        anchors.left: icon.right
        anchors.leftMargin: Theme.paddingLarge
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Label {
            width: parent.width
            text: block.value
            color: block.valueColor
            font.pixelSize: Theme.fontSizeExtraLarge
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Label {
            visible: text.length > 0
            width: parent.width
            text: block.detail
            color: block.detailColor
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.Wrap
        }
    }
}
