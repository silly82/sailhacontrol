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
                placeholderText: qsTr("create one in HA: Profile → Security")
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
                text: qsTr("Saving failed: %1").arg(Credentials.lastError)
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("URL and token are stored encrypted via Sailfish Secrets and bound to the device lock. They are saved as soon as both fields are filled in and lose focus.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            SectionHeader {
                text: qsTr("Home Assistant device registration")
            }

            TextField {
                id: deviceNameField
                width: parent.width
                label: qsTr("Device name")
                placeholderText: qsTr("SailfishOS Phone")
                text: deviceNameSetting.value
                onTextChanged: deviceNameSetting.value = text
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: webhookIdSetting.value.length > 0
                    ? qsTr("Registered -- appears in HA as its own device (notify.mobile_app_...) with battery and connection sensors.")
                    : qsTr("Not registered yet -- will be tried automatically as soon as URL and token are valid.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Re-register device")
                onClicked: webhookIdSetting.value = ""
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Cover action")
                onClicked: pageStack.push(Qt.resolvedUrl("CoverSettingsPage.qml"))
            }
        }
    }
}
