import QtQuick 2.0
import Sailfish.Silica 1.0

// PageHeader for the entity detail pages: title = entity name, description =
// current state in words, plus a small BusyIndicator left of the title while
// a request is in flight (the one place every detail page shows "busy").
PageHeader {
    id: header

    property bool busy: false

    BusyIndicator {
        parent: header.extraContent
        anchors.left: parent ? parent.left : undefined
        // extraContent spans the full header height; line up with the title.
        y: header.topMargin + (header.titleHeight - height) / 2
        size: BusyIndicatorSize.Small
        running: header.busy
    }
}
