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
        // Against internalUrl, not baseUrl: baseUrl is the *effective* URL
        // and may currently be the external one.
        if (baseUrlField.text === Credentials.internalUrl && tokenField.text === Credentials.token
                && externalUrlField.text.trim() === Credentials.externalUrl) {
            return
        }
        Credentials.save(baseUrlField.text, tokenField.text, externalUrlField.text.trim())
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
    // Same key as in harbour-hacontrol.qml, which pushes it into Credentials.
    ConfigurationValue {
        id: connectionModeSetting
        key: "/apps/harbour-hacontrol/connectionMode"
        defaultValue: 0
    }
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
                text: Credentials.internalUrl
                onActiveFocusChanged: if (!activeFocus) page.saveCredentialsIfComplete()
            }

            TextField {
                id: externalUrlField
                width: parent.width
                label: qsTr("External URL (optional)")
                placeholderText: qsTr("https://example.ui.nabu.casa")
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                text: Credentials.externalUrl
                onActiveFocusChanged: if (!activeFocus) page.saveCredentialsIfComplete()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Used when the URL above can't be reached, e.g. away from home: Nabu Casa, Tailscale or a reverse proxy. The same token is used for both.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            ComboBox {
                id: connectionModeBox
                width: parent.width
                label: qsTr("Connection")
                enabled: Credentials.externalUrl.length > 0
                currentIndex: connectionModeSetting.value
                menu: ContextMenu {
                    MenuItem { text: qsTr("Automatic") }
                    MenuItem { text: qsTr("Internal URL only") }
                    MenuItem { text: qsTr("External URL only") }
                }
                onCurrentIndexChanged: {
                    if (connectionModeSetting.value !== currentIndex) {
                        connectionModeSetting.value = currentIndex
                    }
                    // Also directly, so the switch doesn't wait for the dconf
                    // round trip to harbour-hacontrol.qml's Binding.
                    Credentials.connectionMode = currentIndex
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                visible: Credentials.externalUrl.length > 0 && Credentials.internalUrl.length > 0
                text: Credentials.probing
                    ? qsTr("Checking whether the internal URL is reachable…")
                    : (Credentials.usingExternal
                       ? qsTr("Connected via: external URL")
                       : qsTr("Connected via: internal URL"))
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
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
        }
    }
}
