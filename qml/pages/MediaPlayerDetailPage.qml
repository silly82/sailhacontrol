import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

// Submenü für Media Player, geöffnet per Tap auf den Namen in
// RoomsView.qml. Zeigt Cover-Bild und Titel/Interpret (falls vorhanden),
// Play/Pause, Ein/Aus, Quelle, Stummschalten und einen Lautstärke-Regler
// (falls volume_level unterstützt wird).
//
// Aufbau wie alle Detailseiten, s. LightDetailPage.qml.
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    property string entityState: ""
    property var attributes: ({})
    // RoomsView.qml (liveStateReceived), wie bei CoverDetailPage.qml. Darf
    // null sein (dann ohne Live-Update).
    property var stateSource: null

    // MediaPlayerEntityFeature: VOLUME_MUTE = 8, TURN_ON = 128,
    // TURN_OFF = 256, SELECT_SOURCE = 2048. Fehlt supported_features ganz:
    // anbieten, wofür die Attribute sprechen (is_volume_muted, source_list).
    readonly property bool hasFeatureInfo: attributes.supported_features !== undefined && attributes.supported_features !== null
    readonly property int mediaFeatures: hasFeatureInfo ? attributes.supported_features : 0
    readonly property bool supportsMute: hasFeatureInfo ? (mediaFeatures & 8) !== 0 : attributes.is_volume_muted !== undefined
    readonly property bool supportsTurnOn: (mediaFeatures & 128) !== 0
    readonly property bool supportsTurnOff: (mediaFeatures & 256) !== 0
    readonly property var sourceList: attributes.source_list || []
    readonly property bool supportsSelectSource: sourceList.length > 0 && (!hasFeatureInfo || (mediaFeatures & 2048) !== 0)
    readonly property bool isOff: entityState === "off" || entityState === "standby" || entityState === "unavailable"

    // entity_picture ist meist relativ (/api/media_player_proxy/...?token=
    // ...), manche Integrationen liefern eine absolute https-URL. Das
    // token= wird von main() in Logausgaben geschwärzt.
    readonly property string artworkUrl: {
        var pic = attributes.entity_picture
        if (!pic || isOff) {
            return ""
        }
        pic = String(pic)
        if (/^https?:\/\//.test(pic)) {
            return pic
        }
        return Credentials.baseUrl.replace(/\/+$/, "") + (pic.charAt(0) === "/" ? "" : "/") + pic
    }

    function stateLabel(state) {
        switch (state) {
        case "playing": return qsTr("Playing")
        case "paused": return qsTr("Paused")
        case "idle": return qsTr("Idle")
        case "off": return qsTr("Off")
        case "on": return qsTr("On")
        case "buffering": return qsTr("Buffering")
        case "standby": return qsTr("Standby")
        default: return state
        }
    }

    readonly property bool hasTitle: attributes.media_title !== undefined && attributes.media_title !== null
        && String(attributes.media_title).length > 0
    readonly property bool hasVolume: attributes.volume_level !== undefined && attributes.volume_level !== null
    readonly property real volume: hasVolume ? attributes.volume_level : 0.5

    function callMediaPlayer(service, serviceData) {
        serviceData.entity_id = entityId
        caller.call("media_player", service, serviceData)
    }

    // Slider nur nachziehen, solange er nicht festgehalten wird (wie
    // CoverDetailPage.qml).
    onVolumeChanged: if (!volumeSlider.down) volumeSlider.value = volume

    Connections {
        target: stateSource
        onLiveStateReceived: {
            if (changedEntityId !== page.entityId || !newState) {
                return
            }
            page.entityState = newState.state || ""
            page.attributes = newState.attributes || {}
        }
    }

    ServiceCaller {
        id: caller
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        VerticalScrollDecorator {}

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            DetailPageHeader {
                title: entityName
                description: stateLabel(entityState)
                busy: caller.busy
            }

            DetailStatusBlock {
                domain: "media_player"
                iconColor: entityState === "playing" ? Theme.highlightColor : Theme.secondaryColor
                value: hasTitle ? String(attributes.media_title) : stateLabel(entityState)
                detail: hasTitle && attributes.media_artist !== undefined && attributes.media_artist !== null
                    ? String(attributes.media_artist) : ""
            }

            DetailErrorLabel {
                text: caller.errorText
            }

            Image {
                id: artwork
                visible: artworkUrl.length > 0 && status === Image.Ready
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 2 * Theme.horizontalPageMargin, Theme.itemSizeHuge * 2)
                height: width
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: width
                sourceSize.height: height
                source: artworkUrl
            }

            // Transporttasten: Medien-üblich als IconButtons, zentriert.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
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

            ActionButtonGrid {
                actions: [
                    { text: isOff ? qsTr("Turn on") : qsTr("Turn off"),
                      visible: isOff ? supportsTurnOn : supportsTurnOff,
                      action: function () { callMediaPlayer(isOff ? "turn_on" : "turn_off", {}) } }
                ]
            }

            SectionHeader {
                visible: hasVolume || supportsMute || supportsSelectSource
                text: qsTr("Controls")
            }

            Slider {
                id: volumeSlider
                visible: hasVolume
                width: parent.width
                label: qsTr("Volume")
                minimumValue: 0
                maximumValue: 1
                stepSize: 0.05
                value: volume
                valueText: Math.round(value * 100) + " %"
                onReleased: callMediaPlayer("volume_set", { volume_level: value })
            }

            TextSwitch {
                visible: supportsMute
                text: qsTr("Muted")
                checked: attributes.is_volume_muted === true
                // automaticCheck aus: der Schalter folgt dem von HA
                // gemeldeten Zustand (Live-Update), nicht dem Tap.
                automaticCheck: false
                onClicked: callMediaPlayer("volume_mute", { is_volume_muted: attributes.is_volume_muted !== true })
            }

            ComboBox {
                visible: supportsSelectSource
                width: parent.width
                label: qsTr("Source")
                value: attributes.source !== undefined && attributes.source !== null ? String(attributes.source) : ""
                menu: ContextMenu {
                    Repeater {
                        model: sourceList
                        MenuItem {
                            text: String(modelData)
                            onClicked: callMediaPlayer("select_source", { source: modelData })
                        }
                    }
                }
            }
        }
    }
}
