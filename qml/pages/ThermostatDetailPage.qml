import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

// Submenu für Thermostate (climate-Domain), geöffnet per Tap auf den Namen
// in RoomsView.qml. Zeigt aktuelle Temperatur, einen Zieltemperatur-Regler
// (min_temp/max_temp/target_temp_step aus den Attributen) und, falls die
// Entity mehr als einen Modus unterstützt, eine Modus-Auswahl.
//
// Aufbau wie alle Detailseiten, s. LightDetailPage.qml.
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    // HAs "state" (bei climate == aktueller hvac_mode) liegt NICHT in
    // attributes -- eigene Property, von RoomsView.qml separat befüllt.
    property string entityHvacMode: ""
    property var attributes: ({})
    // RoomsView.qml (liveStateReceived), wie bei CoverDetailPage.qml. Darf
    // null sein (dann ohne Live-Update).
    property var stateSource: null

    readonly property var hvacModes: attributes.hvac_modes || []
    readonly property real minTemp: attributes.min_temp !== undefined ? attributes.min_temp : 10
    readonly property real maxTemp: attributes.max_temp !== undefined ? attributes.max_temp : 30
    readonly property real tempStep: attributes.target_temp_step || 0.5
    readonly property bool hasCurrent: attributes.current_temperature !== undefined && attributes.current_temperature !== null
    readonly property bool hasTarget: attributes.temperature !== undefined && attributes.temperature !== null
    readonly property real targetTemp: hasTarget ? attributes.temperature : (minTemp + maxTemp) / 2

    function hvacModeLabel(mode) {
        switch (mode) {
        case "off": return qsTr("Off")
        case "heat": return qsTr("Heat")
        case "cool": return qsTr("Cool")
        case "heat_cool": return qsTr("Heat/Cool")
        case "auto": return qsTr("Auto")
        case "dry": return qsTr("Dry")
        case "fan_only": return qsTr("Fan only")
        default: return mode
        }
    }

    function formatTemp(value) {
        return Number(value).toFixed(1) + " °C"
    }

    function callClimate(service, serviceData) {
        serviceData.entity_id = entityId
        caller.call("climate", service, serviceData)
    }

    // Slider nur nachziehen, solange er nicht festgehalten wird (wie
    // CoverDetailPage.qml).
    onTargetTempChanged: if (!targetSlider.down) targetSlider.value = targetTemp

    Connections {
        target: stateSource
        onLiveStateReceived: {
            if (changedEntityId !== page.entityId || !newState) {
                return
            }
            page.entityHvacMode = newState.state || ""
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
                description: hvacModeLabel(entityHvacMode)
                busy: caller.busy
            }

            DetailStatusBlock {
                domain: "climate"
                iconColor: entityHvacMode === "off" ? Theme.secondaryColor : Theme.highlightColor
                value: hasCurrent ? formatTemp(attributes.current_temperature)
                    : (hasTarget ? formatTemp(attributes.temperature) : hvacModeLabel(entityHvacMode))
                detail: hasCurrent && hasTarget ? qsTr("Target %1").arg(formatTemp(attributes.temperature)) : ""
            }

            DetailErrorLabel {
                text: caller.errorText
            }

            SectionHeader {
                visible: hvacModes.length > 1 || hasTarget
                text: qsTr("Controls")
            }

            ComboBox {
                visible: hvacModes.length > 1
                width: parent.width
                label: qsTr("Mode")
                value: hvacModeLabel(entityHvacMode)
                menu: ContextMenu {
                    Repeater {
                        model: hvacModes
                        MenuItem {
                            text: hvacModeLabel(modelData)
                            onClicked: {
                                // Sofort anzeigen; das Live-Update bestätigt
                                // bzw. korrigiert.
                                entityHvacMode = modelData
                                callClimate("set_hvac_mode", { hvac_mode: modelData })
                            }
                        }
                    }
                }
            }

            Slider {
                id: targetSlider
                visible: hasTarget
                width: parent.width
                label: qsTr("Target temperature")
                minimumValue: minTemp
                maximumValue: maxTemp
                stepSize: tempStep
                value: targetTemp
                valueText: value.toFixed(1) + " °C"
                onReleased: callClimate("set_temperature", { temperature: value })
            }
        }
    }
}
