import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../lib/HaApi.js" as HaApi

// Submenu für Lichter, geöffnet per Tap auf den Namen in RoomsView.qml.
// Zeigt nur die Regler, die die jeweilige Entity laut
// attributes.supported_color_modes tatsächlich unterstützt -- ein reiner
// On/Off-Schalter (Zwischenstecker o.ä.) zeigt hier entsprechend nichts an.
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    property bool entityIsOn: false
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

    readonly property var supportedModes: attributes.supported_color_modes || []
    readonly property bool supportsBrightness: supportedModes.some(function (m) { return m !== "onoff" })
    readonly property bool supportsColorTemp: supportedModes.indexOf("color_temp") >= 0
    readonly property bool supportsColor: ["hs", "rgb", "xy", "rgbw", "rgbww"].some(function (m) { return supportedModes.indexOf(m) >= 0 })

    property string errorText: ""
    property color currentColor: attributes.rgb_color
        ? Qt.rgba(attributes.rgb_color[0] / 255, attributes.rgb_color[1] / 255, attributes.rgb_color[2] / 255, 1)
        : "white"

    function callLight(serviceData) {
        errorText = ""
        serviceData.entity_id = entityId
        HaApi.callService(baseUrlSetting.value, tokenSetting.value, "light", "turn_on", serviceData,
            function () {},
            function (error) { errorText = error.hint || qsTr("Unbekannter Fehler") })
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
                // HA meldet brightness/color_temp_kelvin/rgb_color als null,
                // solange das Licht aus ist -- keine Einschränkung unserer
                // App, sondern von HAs Datenmodell. Regler zeigen dann einen
                // Startwert, keinen gespeicherten Zustand.
                visible: !entityIsOn && (supportsBrightness || supportsColorTemp || supportsColor)
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Licht ist aus -- Regler zeigen einen Startwert, keine gespeicherte Einstellung (HA liefert Helligkeit/Farbe erst nach dem Einschalten). Verstellen schaltet das Licht mit ein.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Label {
                visible: !supportsBrightness && !supportsColorTemp && !supportsColor
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Dieses Licht unterstützt nur Ein/Aus.")
                color: Theme.secondaryHighlightColor
            }

            Slider {
                visible: supportsBrightness
                width: parent.width
                label: qsTr("Helligkeit")
                minimumValue: 1
                maximumValue: 255
                stepSize: 1
                value: attributes.brightness || 128
                valueText: Math.round(100 * value / 255) + " %"
                onReleased: callLight({ brightness: Math.round(value) })
            }

            Slider {
                visible: supportsColorTemp
                width: parent.width
                label: qsTr("Farbtemperatur")
                minimumValue: attributes.min_color_temp_kelvin || 2000
                maximumValue: attributes.max_color_temp_kelvin || 6500
                stepSize: 50
                value: attributes.color_temp_kelvin || Math.round((minimumValue + maximumValue) / 2)
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
                    text: qsTr("Farbe wählen")
                }
            }
        }
    }
}
