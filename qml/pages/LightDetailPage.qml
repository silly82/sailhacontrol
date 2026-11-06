import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

// Submenu für Lichter, geöffnet per Tap auf den Namen in RoomsView.qml.
// Zeigt nur die Regler, die die jeweilige Entity laut
// attributes.supported_color_modes tatsächlich unterstützt -- ein reiner
// On/Off-Schalter (Zwischenstecker o.ä.) zeigt hier entsprechend nur den
// Ein/Aus-Knopf an.
//
// Aufbau wie alle Detailseiten: DetailPageHeader (Name, Zustand, busy) ->
// DetailStatusBlock -> DetailErrorLabel -> ActionButtonGrid -> Regler
// unter SectionHeader "Controls".
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    property bool entityIsOn: false
    property var attributes: ({})
    // RoomsView.qml (liveStateReceived), wie bei CoverDetailPage.qml. Darf
    // null sein (dann ohne Live-Update).
    property var stateSource: null

    readonly property var supportedModes: attributes.supported_color_modes || []
    readonly property bool supportsBrightness: supportedModes.some(function (m) { return m !== "onoff" })
    readonly property bool supportsColorTemp: supportedModes.indexOf("color_temp") >= 0
    readonly property bool supportsColor: ["hs", "rgb", "xy", "rgbw", "rgbww"].some(function (m) { return supportedModes.indexOf(m) >= 0 })
    readonly property bool hasControls: supportsBrightness || supportsColorTemp || supportsColor

    readonly property real brightness: attributes.brightness || 128
    readonly property real colorTemp: attributes.color_temp_kelvin
        || Math.round(((attributes.min_color_temp_kelvin || 2000) + (attributes.max_color_temp_kelvin || 6500)) / 2)

    property color currentColor: attributes.rgb_color
        ? Qt.rgba(attributes.rgb_color[0] / 255, attributes.rgb_color[1] / 255, attributes.rgb_color[2] / 255, 1)
        : "white"

    function callLight(serviceData) {
        serviceData.entity_id = entityId
        caller.call("light", "turn_on", serviceData, function () { entityIsOn = true })
    }

    function toggleLight() {
        var turnOn = !entityIsOn
        caller.call("light", turnOn ? "turn_on" : "turn_off", { entity_id: entityId },
            function () { entityIsOn = turnOn })
    }

    // Slider-Werte nur nachziehen, solange der Nutzer sie nicht gerade
    // festhält (wie CoverDetailPage.qml) -- die value-Bindung bricht beim
    // ersten Ziehen ohnehin weg.
    onBrightnessChanged: if (!brightnessSlider.down) brightnessSlider.value = brightness
    onColorTempChanged: if (!colorTempSlider.down) colorTempSlider.value = colorTemp

    Connections {
        target: stateSource
        onLiveStateReceived: {
            if (changedEntityId !== page.entityId || !newState) {
                return
            }
            page.entityIsOn = newState.state === "on"
            page.attributes = newState.attributes || {}
        }
    }

    ServiceCaller {
        id: caller
    }

    Component {
        id: colorPickerPageComponent
        ColorPickerPage {
            color: currentColor
            onColorClicked: {
                currentColor = color
                callLight({ rgb_color: [Math.round(color.r * 255), Math.round(color.g * 255), Math.round(color.b * 255)] })
                pageStack.pop()
            }
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

            DetailPageHeader {
                title: entityName
                description: entityIsOn ? qsTr("On") : qsTr("Off")
                busy: caller.busy
            }

            DetailStatusBlock {
                domain: "light"
                iconColor: entityIsOn ? Theme.highlightColor : Theme.secondaryColor
                valueColor: entityIsOn ? Theme.highlightColor : Theme.secondaryHighlightColor
                // brightness ist null, solange das Licht aus ist.
                value: entityIsOn && supportsBrightness && attributes.brightness
                    ? Math.round(100 * attributes.brightness / 255) + " %"
                    : (entityIsOn ? qsTr("On") : qsTr("Off"))
                detail: entityIsOn && attributes.color_temp_kelvin
                    ? Math.round(attributes.color_temp_kelvin) + " K" : ""
            }

            DetailErrorLabel {
                text: caller.errorText
            }

            ActionButtonGrid {
                actions: [
                    { text: entityIsOn ? qsTr("Turn off") : qsTr("Turn on"), action: toggleLight }
                ]
            }

            SectionHeader {
                text: qsTr("Controls")
            }

            Label {
                visible: !hasControls
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("This light only supports on/off.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
            }

            Label {
                // HA meldet brightness/color_temp_kelvin/rgb_color als null,
                // solange das Licht aus ist -- keine Einschränkung unserer
                // App, sondern von HAs Datenmodell. Regler zeigen dann einen
                // Startwert, keinen gespeicherten Zustand.
                visible: !entityIsOn && hasControls
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Light is off -- the sliders show a starting value, not a stored setting (HA only reports brightness/color once the light is on). Moving a slider also switches the light on.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Slider {
                id: brightnessSlider
                visible: supportsBrightness
                width: parent.width
                label: qsTr("Brightness")
                minimumValue: 1
                maximumValue: 255
                stepSize: 1
                value: brightness
                valueText: Math.round(100 * value / 255) + " %"
                onReleased: callLight({ brightness: Math.round(value) })
            }

            Slider {
                id: colorTempSlider
                visible: supportsColorTemp
                width: parent.width
                label: qsTr("Color temperature")
                minimumValue: attributes.min_color_temp_kelvin || 2000
                maximumValue: attributes.max_color_temp_kelvin || 6500
                stepSize: 50
                value: colorTemp
                valueText: Math.round(value) + " K"
                onReleased: callLight({ color_temp_kelvin: Math.round(value) })
            }

            BackgroundItem {
                visible: supportsColor
                width: parent.width
                height: Theme.itemSizeMedium
                onClicked: pageStack.push(colorPickerPageComponent)

                Rectangle {
                    x: Theme.horizontalPageMargin
                    width: Theme.itemSizeSmall
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: currentColor
                    border.width: 1
                    border.color: Theme.primaryColor
                }
                Label {
                    x: 2 * Theme.horizontalPageMargin + Theme.itemSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Choose color")
                }
            }
        }
    }
}
