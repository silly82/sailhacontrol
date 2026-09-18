import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/HaApi.js" as HaApi

// Submenu für Thermostate (climate-Domain), geöffnet per Tap auf den Namen
// in RoomsView.qml. Zeigt aktuelle Temperatur, einen Zieltemperatur-Regler
// (min_temp/max_temp/target_temp_step aus den Attributen) und, falls die
// Entity mehr als einen Modus unterstützt, eine Modus-Auswahl.
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    // HAs "state" (bei climate == aktueller hvac_mode) liegt NICHT in
    // attributes -- eigene Property, von RoomsView.qml separat befüllt.
    property string entityHvacMode: ""
    property var attributes: ({})

    readonly property var hvacModes: attributes.hvac_modes || []
    readonly property real minTemp: attributes.min_temp !== undefined ? attributes.min_temp : 10
    readonly property real maxTemp: attributes.max_temp !== undefined ? attributes.max_temp : 30
    readonly property real tempStep: attributes.target_temp_step || 0.5

    property string errorText: ""
    property string selectedMode: entityHvacMode

    function hvacModeLabel(mode) {
        switch (mode) {
        case "off": return qsTr("Aus")
        case "heat": return qsTr("Heizen")
        case "cool": return qsTr("Kühlen")
        case "heat_cool": return qsTr("Heizen/Kühlen")
        case "auto": return qsTr("Automatik")
        case "dry": return qsTr("Trocknen")
        case "fan_only": return qsTr("Nur Lüfter")
        default: return mode
        }
    }

    function callClimate(service, serviceData) {
        errorText = ""
        serviceData.entity_id = entityId
        HaApi.callService(Credentials.baseUrl, Credentials.token, "climate", service, serviceData,
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
                visible: attributes.current_temperature !== undefined
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Aktuell: %1 °C").arg(attributes.current_temperature)
                color: Theme.secondaryHighlightColor
            }

            ComboBox {
                visible: hvacModes.length > 1
                width: parent.width
                label: qsTr("Modus")
                value: hvacModeLabel(selectedMode)
                menu: ContextMenu {
                    Repeater {
                        model: hvacModes
                        MenuItem {
                            text: hvacModeLabel(modelData)
                            onClicked: {
                                selectedMode = modelData
                                callClimate("set_hvac_mode", { hvac_mode: modelData })
                            }
                        }
                    }
                }
            }

            Slider {
                visible: attributes.temperature !== undefined
                width: parent.width
                label: qsTr("Zieltemperatur")
                minimumValue: minTemp
                maximumValue: maxTemp
                stepSize: tempStep
                value: attributes.temperature !== undefined ? attributes.temperature : (minTemp + maxTemp) / 2
                valueText: value.toFixed(1) + " °C"
                onReleased: callClimate("set_temperature", { temperature: value })
            }
        }
    }
}
