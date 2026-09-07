import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../lib/HaApi.js" as HaApi

// Submenü für Media Player, geöffnet per Tap auf den Namen in
// RoomsView.qml. Zeigt Titel/Interpret (falls vorhanden), Play/Pause und
// einen Lautstärke-Regler (falls volume_level unterstützt wird).
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    property string entityState: ""
    property var attributes: ({})

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

    function stateLabel(state) {
        switch (state) {
        case "playing": return qsTr("Spielt")
        case "paused": return qsTr("Pausiert")
        case "idle": return qsTr("Bereit")
        case "off": return qsTr("Aus")
        case "on": return qsTr("Ein")
        case "buffering": return qsTr("Lädt")
        case "standby": return qsTr("Standby")
        default: return state
        }
    }

    function callMediaPlayer(service, serviceData) {
        errorText = ""
        serviceData.entity_id = entityId
        HaApi.callService(baseUrlSetting.value, tokenSetting.value, "media_player", service, serviceData,
            function () {},
            function (error) { errorText = error.hint || qsTr("Unbekannter Fehler") })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        VerticalScrollDecorator {}

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: entityName
            }

            Label {
                visible: errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: errorText
                color: Theme.errorColor
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: stateLabel(entityState)
                color: Theme.secondaryHighlightColor
            }

            Label {
                visible: attributes.media_title !== undefined
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: attributes.media_artist !== undefined
                    ? attributes.media_artist + " – " + attributes.media_title
                    : (attributes.media_title || "")
            }

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingLarge

                IconButton {
                    icon.source: "image://theme/icon-m-previous"
                    onClicked: callMediaPlayer("media_previous_track", {})
                }
                IconButton {
                    icon.source: entityState === "playing"
                        ? "image://theme/icon-m-pause"
                        : "image://theme/icon-m-play"
                    onClicked: callMediaPlayer("media_play_pause", {})
                }
                IconButton {
                    icon.source: "image://theme/icon-m-next"
                    onClicked: callMediaPlayer("media_next_track", {})
                }
            }

            Slider {
                visible: attributes.volume_level !== undefined
                width: parent.width
                label: qsTr("Lautstärke")
                minimumValue: 0
                maximumValue: 1
                stepSize: 0.05
                value: attributes.volume_level !== undefined ? attributes.volume_level : 0.5
                valueText: Math.round(value * 100) + " %"
                onReleased: callMediaPlayer("volume_set", { volume_level: value })
            }
        }
    }
}
