import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

Page {
    id: page

    allowedOrientations: Orientation.All

    // Geschrieben wird erst, wenn beide Felder vollständig sind und sich
    // gegenüber dem gespeicherten Stand geändert haben -- der
    // Secrets-Daemon-Anfrage zuliebe (jeder Tastendruck wäre ein Request) und
    // damit ein halb ausgefülltes Feld den gültigen Satz nicht überschreibt.
    // Ausgelöst beim Fokusverlust und beim Verlassen der Seite.
    function saveCredentialsIfComplete() {
        if (baseUrlField.text.length === 0 || tokenField.text.length === 0) {
            return
        }
        if (baseUrlField.text === Credentials.baseUrl && tokenField.text === Credentials.token) {
            return
        }
        Credentials.save(baseUrlField.text, tokenField.text)
    }

    onStatusChanged: if (status === PageStatus.Deactivating) saveCredentialsIfComplete()

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
                text: Credentials.baseUrl
                onActiveFocusChanged: if (!activeFocus) page.saveCredentialsIfComplete()
            }

            TextField {
                id: tokenField
                width: parent.width
                label: qsTr("Long-Lived Access Token")
                placeholderText: qsTr("erstellt in HA: Profil → Sicherheit")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                text: Credentials.token
                onActiveFocusChanged: if (!activeFocus) page.saveCredentialsIfComplete()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                visible: Credentials.lastError.length > 0
                text: qsTr("Speichern fehlgeschlagen: ") + Credentials.lastError
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("URL und Token werden über Sailfish Secrets verschlüsselt gespeichert und sind an die Gerätesperre gebunden. Gespeichert wird, sobald beide Felder ausgefüllt sind und den Fokus verlassen.")
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
