import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
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

    ConfigurationValue {
        id: baseUrlSetting
        key: "/apps/harbour-hacontrol/baseUrl"
        defaultValue: ""
    }
    ConfigurationValue {
        id: tokenSetting
        key: "/apps/harbour-hacontrol/token"
        defaultValue: ""
    }

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
                inProgress: s.attributes.in_progress === true
            })
        }
        matches.sort(function (a, b) { return a.friendlyName.localeCompare(b.friendlyName) })

        entriesModel.clear()
        for (var m = 0; m < matches.length; m++) {
            entriesModel.append(matches[m])
        }
    }

    function refresh() {
        if (baseUrlSetting.value.length === 0 || tokenSetting.value.length === 0) {
            errorText = qsTr("Noch nicht konfiguriert -- unter Settings die Home-Assistant-URL und einen Long-Lived Access Token eintragen.")
            return
        }
        errorText = ""
        busyIndicator.running = true
        HaApi.getStates(baseUrlSetting.value, tokenSetting.value,
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

    function installUpdate(index) {
        var entry = entriesModel.get(index)
        if (!entry.canInstall || entry.inProgress) {
            return
        }
        errorText = ""
        HaApi.callService(baseUrlSetting.value, tokenSetting.value,
            "update", "install", { entity_id: entry.entityId },
            function () { postInstallRefreshTimer.restart() },
            function (error) { errorText = error.hint || qsTr("Unbekannter Fehler") })
    }

    Component.onCompleted: refresh()

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
                    onClicked: refresh()
                }
            }

            PageHeader {
                title: entriesModel.count > 0 ? qsTr("Updates (%1)").arg(entriesModel.count) : qsTr("Updates")
            }

            Label {
                visible: errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: errorText
                color: errorText.indexOf(qsTr("Noch nicht konfiguriert")) === 0 ? Theme.secondaryHighlightColor : Theme.errorColor
            }

            Label {
                visible: errorText.length === 0 && entriesModel.count === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Alle Geräte sind aktuell.")
                color: Theme.secondaryHighlightColor
            }
        }

        delegate: ListItem {
            id: delegateItem
            width: listView.width
            contentHeight: Theme.itemSizeMedium

            onClicked: installUpdate(index)

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
                    width: parent.width
                    text: model.installedVersion + " → " + model.latestVersion
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryHighlightColor
                    truncationMode: TruncationMode.Fade
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
