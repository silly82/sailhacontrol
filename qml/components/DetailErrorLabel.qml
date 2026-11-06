import QtQuick 2.0
import Sailfish.Silica 1.0

// Inline error line of the entity detail pages -- always directly below the
// status block. Hidden while text is empty.
Label {
    visible: text.length > 0
    x: Theme.horizontalPageMargin
    width: (parent ? parent.width : Screen.width) - 2 * Theme.horizontalPageMargin
    wrapMode: Text.Wrap
    color: Theme.errorColor
    font.pixelSize: Theme.fontSizeSmall
}
