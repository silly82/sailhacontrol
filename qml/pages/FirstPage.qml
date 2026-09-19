import QtQuick 2.0
import Sailfish.Silica 1.0
import "../views"

// Drei Sub-Views (RoomsView, SensorsView, UpdatesView), per horizontalem
// Swipe gewechselt statt über einen Pull-down-Menüpunkt -- Settings bleibt
// in allen Sub-Views per Pull-down erreichbar.
Page {
    id: page

    allowedOrientations: Orientation.All

    // Ein "Refresh" im Pull-down-Menü nur der gerade sichtbaren Seite liesse
    // die anderen mit veralteten Daten zurück -- darum bittet jede Sub-View
    // hier um einen Refresh, und der geht an alle, die ihre Daten schon
    // einmal geladen haben. Zusätzlich wird die App-Ebene gebeten, den
    // Geräte-Status an HA zu melden (der 10-Minuten-BackgroundJob feuert
    // nicht, solange die App im Vordergrund ist -- so gibt es wenigstens
    // einen manuellen Weg).
    signal deviceStatusRefreshRequested()

    function refreshAll() {
        roomsView.refreshIfLoaded()
        sensorsView.refreshIfLoaded()
        updatesView.refreshIfLoaded()
        deviceStatusRefreshRequested()
    }

    // Welche Seite gerade vorne ist. Jede Sub-View lädt ihre Daten erst,
    // wenn sie das erste Mal sichtbar wird: beim Start alle drei gleichzeitig
    // zu laden hiess dreimal parallel die komplette Entity-Liste holen, parsen
    // und ein Model aufbauen (bei der realen Instanz ~1500 Entities) -- auf
    // einem Gerät unter Last war das der Grund, warum der Start zäh war.
    //
    // Wird bewusst erst beim Einrasten gesetzt, nicht laufend aus contentX
    // abgeleitet: ein kräftiger Flick gleitet kurz über die Zielseite hinaus,
    // bevor der Snap zurückholt -- daran hing die übernächste Seite ihr
    // Laden auf und holte die Entity-Liste unnötig ein zweites Mal
    // (gemessen: ein Wisch auf die Sensor-Seite lud auch die Update-Seite).
    property int currentPage: 0

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
                viewActive: page.currentPage === 0
                onRefreshRequested: page.refreshAll()
            }
            SensorsView {
                id: sensorsView
                width: page.width
                height: swipeContainer.height
                viewActive: page.currentPage === 1
                onRefreshRequested: page.refreshAll()
            }
            UpdatesView {
                id: updatesView
                width: page.width
                height: swipeContainer.height
                viewActive: page.currentPage === 2
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
            page.currentPage = targetPage
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
