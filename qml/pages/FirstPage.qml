import QtQuick 2.0
import Sailfish.Silica 1.0
import "../views"

// Zwei Sub-Views (RoomsView, SensorsView), per horizontalem Swipe
// gewechselt statt über einen Pull-down-Menüpunkt -- Settings bleibt in
// beiden Sub-Views per Pull-down erreichbar.
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
        }

        onMovementEnded: {
            var target = contentX > page.width / 2 ? page.width : 0
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
