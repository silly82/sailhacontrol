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

        // Seite, auf der die Wischgeste begonnen hat -- nur auf die
        // nächstliegende Seite zu snappen reichte nicht: ein etwas
        // kräftigerer Flick liess die Flickable frei weitergleiten und
        // übersprang eine Seite (Räume -> direkt Updates). Ein Wisch
        // bewegt jetzt höchstens eine Seite weit.
        //
        // Beides MUSS an einer echten Fingergeste hängen (onDragStarted +
        // userGesture), nicht an onMovementStarted/onMovementEnded allein:
        // die Snap-Animation unten bewegt die Flickable selbst und löst
        // dieselben Movement-Signale aus. Wird dabei die Startseite neu
        // gesetzt, verschiebt sich das geclampte Ziel mitten in der
        // Animation, die nächste Animation startet, und das Ganze läuft
        // endlos weiter -- was den Render-Thread blockiert und die App
        // beim Start in ein ANR laufen lässt (genau so passiert).
        property int dragStartPage: 0
        property bool userGesture: false

        onDragStarted: {
            userGesture = true
            dragStartPage = pageIndexAt(contentX)
        }

        function pageIndexAt(x) {
            if (page.width <= 0) {
                return 0
            }
            return Math.round(x / page.width)
        }

        onMovementEnded: {
            if (!userGesture || page.width <= 0) {
                return
            }
            userGesture = false
            var lastPage = Math.max(0, Math.round((viewRow.width - page.width) / page.width))
            var targetPage = pageIndexAt(contentX)
            targetPage = Math.max(dragStartPage - 1, Math.min(dragStartPage + 1, targetPage))
            targetPage = Math.max(0, Math.min(targetPage, lastPage))
            var target = targetPage * page.width
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
