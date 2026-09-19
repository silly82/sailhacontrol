import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/HaApi.js" as HaApi
import "../components"

// Dritte Sub-View von FirstPage.qml (neben RoomsView/SensorsView) -- flache,
// raumübergreifende Liste der update-Domain-Entities. Anders als bei den
// Sensoren keine Sections: "update" hat keine natürliche Unterkategorie.
// Gefiltert auf state === "on" ("Update verfügbar") -- die meisten
// update-Entities sind die meiste Zeit "off" (aktuell), eine ungefilterte
// Liste wäre grösstenteils Rauschen (107 Entities, typischerweise nur eine
// Handvoll mit anstehendem Update).
Item {
    id: root

    // Bittet die Seite (FirstPage.qml) um einen Refresh aller Sub-Views --
    // die drei Views liegen gleichzeitig nebeneinander, ein Refresh nur der
    // sichtbaren würde die anderen mit alten Daten stehen lassen.
    signal refreshRequested()

    // errorText steht nur noch für echte Fehler. "Noch nicht konfiguriert"
    // lief früher auch darüber und wurde per Textvergleich wieder
    // herausgefiltert -- das wäre spätestens beim Übersetzen gebrochen.
    property bool configured: Credentials.baseUrl.length > 0 && Credentials.token.length > 0
    property string errorText: ""

    ListModel {
        id: entriesModel
    }

    function buildEntries(states) {
        var matches = []
        for (var i = 0; i < states.length; i++) {
            var s = states[i]
            if (s.entity_id.split(".")[0] !== "update") {
                continue
            }
            if (s.state !== "on") {
                continue
            }
            // Bit 0 von supported_features == UpdateEntityFeature.INSTALL --
            // ohne dieses Bit bietet HA für die Entity keinen install-Service.
            var canInstall = ((s.attributes.supported_features || 0) & 1) !== 0
            matches.push({
                entityId: s.entity_id,
                friendlyName: s.attributes.title || s.attributes.friendly_name || s.entity_id,
                installedVersion: s.attributes.installed_version || "?",
                latestVersion: s.attributes.latest_version || "?",
                canInstall: canInstall,
                inProgress: s.attributes.in_progress === true,
                // -1 statt null/undefined als "kein Prozentwert bekannt" --
                // ListModel-Rollen sind typgebunden (erster Wert legt den Typ
                // fest), ein Number/null-Mix auf derselben Rolle würde die
                // gleiche Falle wie beim "value"-Feld in RoomsView.qml
                // reproduzieren (s. dortige Kommentare).
                updatePercentage: typeof s.attributes.update_percentage === "number" ? s.attributes.update_percentage : -1
            })
        }
        matches.sort(function (a, b) { return a.friendlyName.localeCompare(b.friendlyName) })

        entriesModel.clear()
        for (var m = 0; m < matches.length; m++) {
            entriesModel.append(matches[m])
        }
        anyInProgress = matches.some(function (e) { return e.inProgress })
    }

    // Treibt den Fortschrittsbalken während einer laufenden Installation --
    // läuft nur solange mindestens eine Zeile in_progress ist, stoppt sich
    // danach über den nächsten buildEntries()-Aufruf von selbst.
    property bool anyInProgress: false
    Timer {
        id: progressPollTimer
        interval: 3000
        repeat: true
        running: anyInProgress
        onTriggered: refresh()
    }

    function refresh() {
        if (!configured) {
            return
        }
        errorText = ""
        busyIndicator.running = true
        HaApi.getStates(Credentials.baseUrl, Credentials.token,
            function (states) {
                busyIndicator.running = false
                buildEntries(states)
            },
            function (error) {
                busyIndicator.running = false
                errorText = error.hint || qsTr("Unbekannter Fehler")
            })
    }

    // Wie bei toggle() in RoomsView.qml: der Service-Call bestätigt nur die
    // Annahme des Installationsauftrags, nicht dessen Abschluss -- kurz
    // warten, dann neu laden, damit in_progress/Versionsstand aktuell sind.
    Timer {
        id: postInstallRefreshTimer
        interval: 1500
        repeat: false
        onTriggered: refresh()
    }

    // Nimmt die entityId, nicht den Zeilenindex: zwischen Tap und
    // tatsächlichem Aufruf liegen fünf Sekunden Remorse-Frist, in denen ein
    // Refresh (Pull-down, progressPollTimer, WS-Update) die Liste neu
    // aufbauen kann -- ein gemerkter Index zeigte dann womöglich auf ein
    // anderes Gerät, und ein Firmware-Update landet nicht dort, wo getippt
    // wurde.
    function installUpdate(entityId) {
        errorText = ""
        HaApi.callService(Credentials.baseUrl, Credentials.token,
            "update", "install", { entity_id: entityId },
            function () { postInstallRefreshTimer.restart() },
            function (error) { errorText = error.hint || qsTr("Unbekannter Fehler") })
    }

    Component.onCompleted: refresh()
    // Component.onCompleted feuert oft, bevor Credentials' asynchroner
    // Secrets-Request fertig ist -- nichts holt den obigen refresh() dann
    // automatisch nach, bis man manuell pull-to-refresh gemacht hat
    // (s. RoomsView.qml).
    onConfiguredChanged: if (configured) refresh()

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: entriesModel

        header: Column {
            width: listView.width

            PullDownMenu {
                MenuItem {
                    text: qsTr("Settings")
                    onClicked: pageStack.push(Qt.resolvedUrl("../pages/SettingsPage.qml"))
                }
                MenuItem {
                    text: qsTr("Refresh")
                    onClicked: root.refreshRequested()
                }
            }

            PageHeader {
                title: entriesModel.count > 0 ? qsTr("Updates (%1)").arg(entriesModel.count) : qsTr("Updates")
            }
        }

        ViewPlaceholder {
            flickable: listView
            enabled: !configured
            text: qsTr("Noch nicht konfiguriert")
            hintText: qsTr("Im Pull-down-Menü unter Settings die Home-Assistant-URL und einen Long-Lived Access Token eintragen.")
        }
        ViewPlaceholder {
            flickable: listView
            enabled: configured && errorText.length > 0
            text: qsTr("Keine Verbindung")
            hintText: errorText
        }
        ViewPlaceholder {
            flickable: listView
            enabled: configured && errorText.length === 0 && entriesModel.count === 0 && !busyIndicator.running
            text: qsTr("Alles aktuell")
            hintText: qsTr("Kein Gerät hat ein anstehendes Update. Nach unten ziehen zum Aktualisieren.")
        }

        delegate: ListItem {
            id: delegateItem
            width: listView.width
            contentHeight: model.inProgress ? Theme.itemSizeMedium + Theme.paddingSmall : Theme.itemSizeMedium

            // Ein Firmware-Update auf echter Hardware lässt sich nicht
            // zurücknehmen -- ein Fehltipp wäre teuer. remorseAction() gibt
            // fünf Sekunden Zeit, den Auftrag per Tap wieder abzubrechen,
            // bevor update.install tatsächlich rausgeht.
            onClicked: {
                if (!model.canInstall || model.inProgress) {
                    return
                }
                var entityId = model.entityId
                remorseAction(qsTr("Wird installiert"), function () {
                    installUpdate(entityId)
                })
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.right: actionLabel.left
                anchors.rightMargin: Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingSmall / 2

                ScrollingLabel {
                    width: parent.width
                    text: model.friendlyName || ""
                }
                Label {
                    visible: !model.inProgress
                    width: parent.width
                    text: model.installedVersion + " → " + model.latestVersion
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryHighlightColor
                    truncationMode: TruncationMode.Fade
                }

                // Schmaler Fortschrittsbalken statt der Versions-Zeile,
                // solange die Installation läuft. Manche Integrationen
                // liefern update_percentage (dann füllt sich der Balken
                // passend), andere nicht -- dort läuft stattdessen ein
                // wanderndes Highlight (unbestimmter Fortschritt), damit
                // trotzdem sichtbar ist, dass etwas passiert.
                Item {
                    visible: model.inProgress
                    width: parent.width
                    height: Theme.paddingLarge

                    Rectangle {
                        id: progressTrack
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (model.updatePercentage >= 0 ? percentLabel.width + Theme.paddingSmall : 0)
                        height: Theme.paddingSmall
                        radius: height / 2
                        color: Theme.rgba(Theme.secondaryColor, Theme.opacityFaint)
                        clip: true

                        Rectangle {
                            id: progressFill
                            height: parent.height
                            radius: parent.radius
                            color: Theme.highlightColor
                            width: model.updatePercentage >= 0
                                ? parent.width * Math.max(0, Math.min(100, model.updatePercentage)) / 100
                                : parent.width * 0.35
                            Behavior on width { NumberAnimation { duration: 400 } }

                            SequentialAnimation on x {
                                running: model.inProgress && model.updatePercentage < 0
                                loops: Animation.Infinite
                                NumberAnimation { from: 0; to: Math.max(0, progressTrack.width - progressFill.width); duration: 900; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: Math.max(0, progressTrack.width - progressFill.width); to: 0; duration: 900; easing.type: Easing.InOutQuad }
                            }
                        }
                    }

                    Label {
                        id: percentLabel
                        visible: model.updatePercentage >= 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(model.updatePercentage) + "%"
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryHighlightColor
                    }
                }
            }

            Label {
                id: actionLabel
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: model.inProgress ? qsTr("Installiert…") : qsTr("Installieren")
                color: model.canInstall && !model.inProgress ? Theme.highlightColor : Theme.secondaryColor
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        id: busyIndicator
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: false
    }
}
