import QtQuick 2.0
import Sailfish.Silica 1.0
import "../views"

// Drei Sub-Views (RoomsView, SensorsView, UpdatesView), per horizontalem
// Swipe gewechselt statt über einen Pull-down-Menüpunkt -- Settings bleibt
// in allen Sub-Views per Pull-down erreichbar.
Page {
    id: page

    allowedOrientations: Orientation.All

    // Alle drei Sub-Views liegen gleichzeitig nebeneinander in der Row, jede
    // lädt ihre Daten selbst -- ein "Refresh" im Pull-down-Menü nur der gerade
    // sichtbaren Seite liesse die beiden anderen mit veralteten Daten zurück.
    // Darum bittet jede Sub-View hier um einen Refresh, und der geht an alle.
    // Zusätzlich wird die App-Ebene gebeten, den Geräte-Status an HA zu melden
    // (der 10-Minuten-BackgroundJob feuert nicht, solange die App im
    // Vordergrund ist -- so gibt es wenigstens einen manuellen Weg).
    signal deviceStatusRefreshRequested()

    function refreshAll() {
        roomsView.refresh()
        sensorsView.refresh()
        updatesView.refresh()
        deviceStatusRefreshRequested()
    }

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
                id: roomsView
                width: page.width
                height: swipeContainer.height
                onRefreshRequested: page.refreshAll()
            }
            SensorsView {
                id: sensorsView
                width: page.width
                height: swipeContainer.height
                onRefreshRequested: page.refreshAll()
            }
            UpdatesView {
                id: updatesView
                width: page.width
                height: swipeContainer.height
                onRefreshRequested: page.refreshAll()
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
