import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

Page {
    id: page

    allowedOrientations: Orientation.All

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
    ConfigurationValue {
        id: deviceNameSetting
        key: "/apps/harbour-hacontrol/deviceName"
        defaultValue: qsTr("SailfishOS Phone")
    }
    // Cleared here to trigger harbour-hacontrol.qml's ensureMobileAppRegistered()
    // to re-run (it watches this value, see there) -- kept empty until a
    // registration actually succeeds.
    ConfigurationValue {
        id: webhookIdSetting
        key: "/apps/harbour-hacontrol/webhookId"
        defaultValue: ""
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Settings")
            }

            TextField {
                id: baseUrlField
                width: parent.width
                label: qsTr("Home Assistant URL")
                placeholderText: qsTr("http://homeassistant.local:8123")
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                text: baseUrlSetting.value
                onTextChanged: baseUrlSetting.value = text
            }

            TextField {
                id: tokenField
                width: parent.width
                label: qsTr("Long-Lived Access Token")
                placeholderText: qsTr("erstellt in HA: Profil → Sicherheit")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                text: tokenSetting.value
                onTextChanged: tokenSetting.value = text
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Nur lokales Netz (Ausbaustufe 1). URL und Token werden über Nemo.Configuration gespeichert -- für Klartext-Speicherung ausreichend für einen lokalen Prototyp, aber kein Ersatz für Sailfish Secrets, falls das Gerät geteilt wird.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            SectionHeader {
                text: qsTr("Home-Assistant-Geräteregistrierung")
            }

            TextField {
                id: deviceNameField
                width: parent.width
                label: qsTr("Gerätename")
                placeholderText: qsTr("SailfishOS Phone")
                text: deviceNameSetting.value
                onTextChanged: deviceNameSetting.value = text
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: webhookIdSetting.value.length > 0
                    ? qsTr("Registriert -- erscheint in HA als eigenes Gerät (notify.mobile_app_...) mit Akkustand-/Verbindungs-Sensoren.")
                    : qsTr("Noch nicht registriert -- wird automatisch versucht, sobald URL und Token gültig sind.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Gerät neu registrieren")
                onClicked: webhookIdSetting.value = ""
            }
        }
    }
}
