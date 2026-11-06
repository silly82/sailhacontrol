import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/HaApi.js" as HaApi

// Submenu für Rollos/Markisen mit Positionsangabe (cover-Domain), geöffnet
// per Tap auf den Namen in RoomsView.qml -- nur für Covers, die
// SET_POSITION unterstützen oder current_position melden (s.
// coverHasPosition() dort). Zeigt einen Positions-Slider und die
// Auf/Stopp/Zu-Tasten, die das Cover laut supported_features kann.
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

    property string errorText: ""

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
        errorText = ""
        serviceData.entity_id = entityId
        HaApi.callService(Credentials.baseUrl, Credentials.token, "cover", service, serviceData,
            function () {},
            function (error) { errorText = error.hint || qsTr("Unknown error") })
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
                description: coverStateLabel(entityState)
            }

            Label {
                visible: errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: errorText
                color: Theme.errorColor
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

            // Meldet das Cover eine Position, kann sie aber nicht gezielt
            // anfahren: nur anzeigen.
            Label {
                visible: !supportsSetPosition && hasPosition
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Position: %1 %").arg(Math.round(coverPosition))
                color: Theme.secondaryHighlightColor
            }

            Row {
                id: buttonRow
                readonly property int buttonCount: (supportsOpen ? 1 : 0) + (supportsStop ? 1 : 0) + (supportsClose ? 1 : 0)
                readonly property real buttonWidth: buttonCount > 0
                    ? (parent.width - 2 * Theme.horizontalPageMargin - (buttonCount - 1) * Theme.paddingMedium) / buttonCount : 0
                visible: buttonCount > 0
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Button {
                    visible: supportsOpen
                    width: buttonRow.buttonWidth
                    text: qsTr("Open", "cover action")
                    onClicked: callCover("open_cover", {})
                }
                Button {
                    visible: supportsStop
                    width: buttonRow.buttonWidth
                    text: qsTr("Stop")
                    onClicked: callCover("stop_cover", {})
                }
                Button {
                    visible: supportsClose
                    width: buttonRow.buttonWidth
                    text: qsTr("Close")
                    onClicked: callCover("close_cover", {})
                }
            }
        }
    }
}
