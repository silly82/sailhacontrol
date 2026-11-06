import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

// Submenu für Rollos/Markisen mit Positionsangabe (cover-Domain), geöffnet
// per Tap auf den Namen in RoomsView.qml -- nur für Covers, die
// SET_POSITION unterstützen oder current_position melden (s.
// coverHasPosition() dort). Zeigt einen Positions-Slider und die
// Auf/Stopp/Zu-Tasten, die das Cover laut supported_features kann.
//
// Aufbau wie alle Detailseiten, s. LightDetailPage.qml.
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    // HAs "state" (open/closed/opening/closing) -- wie bei den anderen
    // Detailseiten separat von attributes übergeben.
    property string entityState: ""
    property var attributes: ({})
    // RoomsView.qml: reicht jedes WebSocket-state_changed per Signal
    // liveStateReceived weiter, damit Position/Zustand eines fahrenden
    // Rollos hier live mitlaufen. Darf null sein (dann ohne Live-Update).
    property var stateSource: null

    // CoverEntityFeature: OPEN = 1, CLOSE = 2, SET_POSITION = 4, STOP = 8.
    // Fehlt supported_features ganz, wenigstens Auf/Zu anbieten.
    readonly property bool hasFeatureInfo: attributes.supported_features !== undefined && attributes.supported_features !== null
    readonly property int coverFeatures: hasFeatureInfo ? attributes.supported_features : 3
    readonly property bool supportsOpen: (coverFeatures & 1) !== 0
    readonly property bool supportsClose: (coverFeatures & 2) !== 0
    readonly property bool supportsSetPosition: (coverFeatures & 4) !== 0
    readonly property bool supportsStop: (coverFeatures & 8) !== 0
    readonly property bool hasPosition: attributes.current_position !== undefined && attributes.current_position !== null
    readonly property real coverPosition: hasPosition ? attributes.current_position : 0

    function coverStateLabel(state) {
        switch (state) {
        case "open": return qsTr("Open", "cover state")
        case "closed": return qsTr("Closed")
        case "opening": return qsTr("Opening", "cover state")
        case "closing": return qsTr("Closing")
        case "unavailable": return qsTr("Unavailable")
        default: return state
        }
    }

    function callCover(service, serviceData) {
        serviceData.entity_id = entityId
        caller.call("cover", service, serviceData)
    }

    // Slider-Wert nur nachziehen, solange der Nutzer ihn nicht gerade
    // festhält -- sonst springt er beim Ziehen auf die alte Position zurück.
    // (Die initiale value-Bindung bricht beim ersten Ziehen ohnehin weg.)
    onCoverPositionChanged: {
        if (!positionSlider.down) {
            positionSlider.value = coverPosition
        }
    }

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
                description: coverStateLabel(entityState)
                busy: caller.busy
            }

            DetailStatusBlock {
                domain: "cover"
                iconColor: entityState === "closed" || entityState === "unavailable" ? Theme.secondaryColor : Theme.highlightColor
                // HA: 0 = zu, 100 = offen.
                value: hasPosition ? Math.round(coverPosition) + " %" : coverStateLabel(entityState)
                detail: hasPosition ? qsTr("Position") : ""
            }

            DetailErrorLabel {
                text: caller.errorText
            }

            ActionButtonGrid {
                maxColumns: 3
                actions: [
                    { text: qsTr("Open", "cover action"), visible: supportsOpen,
                      action: function () { callCover("open_cover", {}) } },
                    { text: qsTr("Stop"), visible: supportsStop,
                      action: function () { callCover("stop_cover", {}) } },
                    { text: qsTr("Close"), visible: supportsClose,
                      action: function () { callCover("close_cover", {}) } }
                ]
            }

            SectionHeader {
                visible: supportsSetPosition
                text: qsTr("Controls")
            }

            Slider {
                id: positionSlider
                visible: supportsSetPosition
                width: parent.width
                label: qsTr("Position")
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                value: coverPosition
                valueText: Math.round(value) + " %"
                onReleased: callCover("set_cover_position", { position: Math.round(value) })
            }
        }
    }
}
