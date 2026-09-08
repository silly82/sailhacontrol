import QtQuick 2.0
import Sailfish.Silica 1.0
import "../views"

// Drei Sub-Views (RoomsView, SensorsView, UpdatesView), per horizontalem
// Swipe gewechselt statt über einen Pull-down-Menüpunkt -- Settings bleibt
// in allen Sub-Views per Pull-down erreichbar.
Page {
    id: page

    allowedOrientations: Orientation.All

    SilicaFlickable {
        id: swipeContainer
        anchors.fill: parent
        contentWidth: viewRow.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        clip: true

        Row {
            id: viewRow
            height: swipeContainer.height

            RoomsView {
                width: page.width
                height: swipeContainer.height
            }
            SensorsView {
                width: page.width
                height: swipeContainer.height
            }
            UpdatesView {
                width: page.width
                height: swipeContainer.height
            }
        }

        // Auf die nächstliegende Seite einrasten -- verallgemeinert auf
        // beliebig viele Sub-Views statt fest auf zwei (0/page.width).
        onMovementEnded: {
            var target = Math.round(contentX / page.width) * page.width
            target = Math.max(0, Math.min(target, viewRow.width - page.width))
            if (Math.round(contentX) !== target) {
                snapAnimation.to = target
                snapAnimation.restart()
            }
        }

        NumberAnimation {
            id: snapAnimation
            target: swipeContainer
            property: "contentX"
            duration: 200
            easing.type: Easing.OutQuad
        }
    }

    HorizontalScrollDecorator {
        flickable: swipeContainer
    }
}
