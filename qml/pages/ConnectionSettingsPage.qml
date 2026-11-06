import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// Settings > Connection (opened from SettingsPage.qml): internal/external
// URL, connection mode and token of the active instance.
//
// The fields' text is assigned imperatively (Component.onCompleted plus the
// Credentials Connections below) instead of declaratively. Silica's
// TextField reads its TextInput's implicitWidth inside the width binding of
// its NoWrap state (TextField.qml:87); with a non-empty text while the field
// is being created that first read relayouts the TextInput and changes
// implicitWidth from within the binding -> "Binding loop detected for
// property width". Starting empty and filling the text once the field is
// complete updates implicitWidth through a normal notification instead.
// The Connections keep the old binding's behavior: the fields follow
// Credentials when the secrets (re)load.
Page {
    id: page

    allowedOrientations: Orientation.All

    // Geschrieben wird erst, wenn beide Felder vollständig sind und sich
    // gegenüber dem gespeicherten Stand geändert haben -- der
    // Secrets-Daemon-Anfrage zuliebe (jeder Tastendruck wäre ein Request) und
    // damit ein halb ausgefülltes Feld den gültigen Satz nicht überschreibt.
    // Ausgelöst beim Fokusverlust und beim Verlassen der Seite.
    function saveCredentialsIfComplete() {
        // While a profile switch loads the new instance's secrets the fields
        // are being refilled -- nothing of the user's to save yet.
        if (!Credentials.loaded) {
            return
        }
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

    Component.onCompleted: {
        baseUrlField.text = Credentials.internalUrl
        externalUrlField.text = Credentials.externalUrl
        tokenField.text = Credentials.token
    }

    Connections {
        target: Credentials
        onInternalUrlChanged: baseUrlField.text = Credentials.internalUrl
        onExternalUrlChanged: externalUrlField.text = Credentials.externalUrl
        onTokenChanged: tokenField.text = Credentials.token
    }

    // Same key as in harbour-hacontrol.qml, which pushes it into Credentials.
    ConfigurationValue {
        id: connectionModeSetting
        key: Credentials.settingsPrefix + "connectionMode"
        defaultValue: 0
    }
    // The key follows the active profile; a click on the box broke its
    // currentIndex binding, so re-sync explicitly when the value moves.
    Connections {
        target: connectionModeSetting
        onValueChanged: {
            if (connectionModeBox.currentIndex !== connectionModeSetting.value) {
                connectionModeBox.currentIndex = connectionModeSetting.value
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width

            PageHeader {
                //: Settings: page with URLs, connection mode and token
                title: qsTr("Connection")
            }

            SectionHeader {
                //: Settings > Connection: section with the two URLs
                text: qsTr("Server")
            }

            TextField {
                id: baseUrlField
                width: parent.width
                label: qsTr("Home Assistant URL")
                placeholderText: qsTr("http://homeassistant.local:8123")
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                onActiveFocusChanged: if (!activeFocus) page.saveCredentialsIfComplete()
            }

            TextField {
                id: externalUrlField
                width: parent.width
                label: qsTr("External URL (optional)")
                placeholderText: qsTr("https://example.ui.nabu.casa")
                description: qsTr("Used when the URL above can't be reached, e.g. Nabu Casa or Tailscale. Same token.")
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                onActiveFocusChanged: if (!activeFocus) page.saveCredentialsIfComplete()
            }

            ComboBox {
                id: connectionModeBox
                width: parent.width
                label: qsTr("Connection")
                enabled: Credentials.externalUrl.length > 0
                currentIndex: connectionModeSetting.value
                description: Credentials.externalUrl.length > 0 && Credentials.internalUrl.length > 0
                    ? (Credentials.probing
                       ? qsTr("Checking whether the internal URL is reachable…")
                       : (Credentials.usingExternal
                          ? qsTr("Connected via: external URL")
                          : qsTr("Connected via: internal URL")))
                    : ""
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

            SectionHeader {
                //: Settings > Connection: section with the access token
                text: qsTr("Access")
            }

            TextField {
                id: tokenField
                width: parent.width
                label: qsTr("Long-Lived Access Token")
                placeholderText: qsTr("create one in HA: Profile → Security")
                description: qsTr("Stored encrypted with Sailfish Secrets. Saved once URL and token are filled in.")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
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
        }

        VerticalScrollDecorator {}
    }
}
