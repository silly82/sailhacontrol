import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

// Saugroboter (vacuum), geöffnet per Tap in RoomsView.qml. Zeigt Zustand
// und Akku, die Tasten, die der Roboter laut supported_features kann, und
// die Saugstufe aus fan_speed_list.
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
        serviceData.entity_id = entityId
        caller.call("vacuum", service, serviceData)
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
                description: vacuumStateLabel(entityState)
                busy: caller.busy
            }

            DetailStatusBlock {
                domain: "vacuum"
                iconColor: entityState === "error" ? Theme.errorColor
                    : (entityState === "cleaning" || entityState === "returning" ? Theme.highlightColor : Theme.secondaryColor)
                value: hasBattery ? Math.round(attributes.battery_level) + " %" : vacuumStateLabel(entityState)
                detail: hasBattery ? qsTr("Battery") : ""
            }

            // Fehlermeldung des Roboters selbst (manche Integrationen melden
            // sie als Attribut "error" bzw. "status") -- an derselben Stelle
            // wie Fehler beim Aufruf.
            DetailErrorLabel {
                text: entityState === "error" && (attributes.error !== undefined || attributes.status !== undefined)
                    ? String(attributes.error !== undefined ? attributes.error : (attributes.status || "")) : ""
            }

            DetailErrorLabel {
                text: caller.errorText
            }

            ActionButtonGrid {
                actions: [
                    { text: qsTr("Start", "vacuum action"), visible: supportsStart,
                      action: function () { callVacuum("start", {}) } },
                    { text: qsTr("Pause", "vacuum action"), visible: supportsPause,
                      action: function () { callVacuum("pause", {}) } },
                    { text: qsTr("Stop"), visible: supportsStop,
                      action: function () { callVacuum("stop", {}) } },
                    { text: qsTr("Return to dock"), visible: supportsReturnHome,
                      action: function () { callVacuum("return_to_base", {}) } },
                    { text: qsTr("Locate"), visible: supportsLocate,
                      action: function () { callVacuum("locate", {}) } }
                ]
            }

            SectionHeader {
                visible: supportsFanSpeed
                text: qsTr("Controls")
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
