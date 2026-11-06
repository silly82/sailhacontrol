import QtQuick 2.0
import Sailfish.Silica 1.0

// Primary actions of the entity detail pages: equal-width Buttons, at most
// maxColumns per row, Theme.paddingMedium apart, centred. A lone button
// gets half the width instead of stretching across the page.
//
// actions: [{ text, action: function () {}, visible (default true),
//             enabled (default true) }]
// Given as data instead of child Buttons so the grid can count the shown
// actions without depending on its own visibility.
Item {
    id: grid

    property var actions: []
    property int maxColumns: 2

    readonly property var shownActions: (actions || []).filter(function (a) { return a && a.visible !== false })
    readonly property int columns: Math.max(1, Math.min(maxColumns, shownActions.length))
    readonly property int slotCount: Math.max(columns, Math.min(2, maxColumns))
    readonly property real buttonWidth: (width - (slotCount - 1) * Theme.paddingMedium) / slotCount

    visible: shownActions.length > 0
    x: Theme.horizontalPageMargin
    width: (parent ? parent.width : Screen.width) - 2 * Theme.horizontalPageMargin
    height: layout.height

    Grid {
        id: layout
        anchors.horizontalCenter: parent.horizontalCenter
        columns: grid.columns
        spacing: Theme.paddingMedium

        // Model is the count, not the array: Qt 5.6 converts an array model
        // to QVariants and would drop the action functions.
        Repeater {
            model: grid.shownActions.length
            Button {
                readonly property var entry: grid.shownActions[index] || ({})
                width: grid.buttonWidth
                text: entry.text || ""
                enabled: entry.enabled !== false
                onClicked: if (entry.action) entry.action()
            }
        }
    }
}
