import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/HaApi.js" as HaApi

// Saugroboter (vacuum), geöffnet per Tap in RoomsView.qml. Zeigt Zustand
// und Akku, die Tasten, die der Roboter laut supported_features kann, und
// die Saugstufe aus fan_speed_list.
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

    // VacuumEntityFeature (StateVacuumEntity): PAUSE = 4, STOP = 8,
    // RETURN_HOME = 16, FAN_SPEED = 32, BATTERY = 64, LOCATE = 512,
    // START = 8192. Fehlt supported_features ganz: Start/Pause/Stop/Zur
    // Station als die üblichen Tasten.
    readonly property bool hasFeatureInfo: attributes.supported_features !== undefined && attributes.supported_features !== null
    readonly property int vacuumFeatures: hasFeatureInfo ? attributes.supported_features : (8192 | 4 | 8 | 16)
    readonly property bool supportsStart: (vacuumFeatures & 8192) !== 0
    readonly property bool supportsPause: (vacuumFeatures & 4) !== 0
    readonly property bool supportsStop: (vacuumFeatures & 8) !== 0
    readonly property bool supportsReturnHome: (vacuumFeatures & 16) !== 0
    readonly property bool supportsLocate: (vacuumFeatures & 512) !== 0
    readonly property var fanSpeeds: attributes.fan_speed_list || []
    readonly property bool supportsFanSpeed: fanSpeeds.length > 0 && (!hasFeatureInfo || (vacuumFeatures & 32) !== 0)
    readonly property bool hasBattery: attributes.battery_level !== undefined && attributes.battery_level !== null

    property string errorText: ""

    function vacuumStateLabel(state) {
        switch (state) {
        case "cleaning": return qsTr("Cleaning")
        case "docked": return qsTr("Docked")
        case "returning": return qsTr("Returning")
        case "paused": return qsTr("Paused")
        case "idle": return qsTr("Idle")
        case "error": return qsTr("Error")
        case "unavailable": return qsTr("Unavailable")
        default: return state
        }
    }

    function callVacuum(service, serviceData) {
        errorText = ""
        serviceData.entity_id = entityId
        HaApi.callService(Credentials.baseUrl, Credentials.token, "vacuum", service, serviceData,
            function () {},
            function (error) { errorText = error.hint || qsTr("Unknown error") })
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
        contentHeight: column.height + Theme.paddingLarge

        VerticalScrollDecorator {}

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: entityName
                description: hasBattery
                    ? qsTr("%1 · Battery %2 %").arg(vacuumStateLabel(entityState)).arg(Math.round(attributes.battery_level))
                    : vacuumStateLabel(entityState)
            }

            Label {
                visible: errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: errorText
                color: Theme.errorColor
            }

            // Fehlermeldung des Roboters selbst (manche Integrationen melden
            // sie als Attribut "error" bzw. "status").
            Label {
                visible: entityState === "error" && (attributes.error !== undefined || attributes.status !== undefined)
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: String(attributes.error !== undefined ? attributes.error : (attributes.status || ""))
                color: Theme.errorColor
            }

            Flow {
                id: buttonFlow
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium
                readonly property real buttonWidth: (width - spacing) / 2

                Button {
                    visible: supportsStart
                    width: buttonFlow.buttonWidth
                    text: qsTr("Start", "vacuum action")
                    onClicked: callVacuum("start", {})
                }
                Button {
                    visible: supportsPause
                    width: buttonFlow.buttonWidth
                    text: qsTr("Pause", "vacuum action")
                    onClicked: callVacuum("pause", {})
                }
                Button {
                    visible: supportsStop
                    width: buttonFlow.buttonWidth
                    text: qsTr("Stop")
                    onClicked: callVacuum("stop", {})
                }
                Button {
                    visible: supportsReturnHome
                    width: buttonFlow.buttonWidth
                    text: qsTr("Return to dock")
                    onClicked: callVacuum("return_to_base", {})
                }
                Button {
                    visible: supportsLocate
                    width: buttonFlow.buttonWidth
                    text: qsTr("Locate")
                    onClicked: callVacuum("locate", {})
                }
            }

            ComboBox {
                visible: supportsFanSpeed
                width: parent.width
                label: qsTr("Fan speed")
                value: attributes.fan_speed !== undefined && attributes.fan_speed !== null ? String(attributes.fan_speed) : ""
                menu: ContextMenu {
                    Repeater {
                        model: fanSpeeds
                        MenuItem {
                            text: String(modelData)
                            onClicked: callVacuum("set_fan_speed", { fan_speed: modelData })
                        }
                    }
                }
            }
        }
    }
}
