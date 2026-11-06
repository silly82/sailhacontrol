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

    // --- Instances (profiles, see src/credentials.h) ---------------------
    // The fields below always edit the active instance; switching first
    // saves what was typed for the current one.
    function switchProfile(id) {
        if (id === Credentials.activeProfileId) {
            return
        }
        saveCredentialsIfComplete()
        Credentials.setActiveProfile(id)
    }

    // Every setting stored under Credentials.settingsPrefix (grep for it in
    // qml/). Cleared when a profile is deleted -- profile ids are never
    // reused, so this is tidying up rather than a correctness requirement.
    readonly property var profileScopedSettings: [
        "connectionMode", "watchedEntities", "lastKnownStates", "webhookId",
        "favoriteEntities", "coverLightsOnCount", "coverLastLightId",
        "coverLastLightName", "coverTargetId", "coverTargetName", "coverTargetDomain",
        "coverTarget2Id", "coverTarget2Name", "coverTarget2Domain", "coverShowWeather",
        "coverWeatherText", "weatherEntity", "weatherEntityName", "reportLocation"
    ]
    function clearProfileSettings(id) {
        var prefix = Credentials.settingsPrefixFor(id)
        for (var i = 0; i < profileScopedSettings.length; i++) {
            var item = Qt.createQmlObject('import Nemo.Configuration 1.0\nConfigurationValue {}', page, "ProfileValue")
            item.key = prefix + profileScopedSettings[i]
            item.value = undefined // unsets the dconf key
            item.destroy()
        }
    }

    function deleteActiveProfile() {
        // Captured now: the remorse runs for a few seconds, and the ids must
        // not depend on what is active once it fires.
        var id = Credentials.activeProfileId
        //: Remorse popup while deleting a Home Assistant instance (profile)
        remorse.execute(qsTr("Deleting instance"), function () {
            if (Credentials.removeProfile(id)) {
                clearProfileSettings(id)
            }
        })
    }

    RemorsePopup {
        id: remorse
    }

    Component {
        id: nameDialogComponent
        Dialog {
            id: nameDialog
            property string profileName
            property string dialogTitle
            canAccept: nameField.text.trim().length > 0
            onAccepted: profileName = nameField.text.trim()

            Column {
                width: parent.width
                DialogHeader {
                    title: nameDialog.dialogTitle
                }
                TextField {
                    id: nameField
                    width: parent.width
                    focus: true
                    label: qsTr("Name")
                    //: Placeholder for the name of a Home Assistant instance
                    placeholderText: qsTr("e.g. Home, Camper")
                    text: nameDialog.profileName
                    EnterKey.enabled: text.trim().length > 0
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: nameDialog.accept()
                }
            }
        }
    }

    Component {
        id: profilePickerComponent
        Page {
            id: pickerPage
            allowedOrientations: Orientation.All
            SilicaListView {
                anchors.fill: parent
                model: Credentials.profiles
                header: PageHeader {
                    title: qsTr("Instance")
                }
                delegate: BackgroundItem {
                    highlighted: down || modelData.id === Credentials.activeProfileId
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        truncationMode: TruncationMode.Fade
                        text: modelData.name
                        color: highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    onClicked: {
                        page.switchProfile(modelData.id)
                        pageStack.pop()
                    }
                }
                VerticalScrollDecorator {}
            }
        }
    }

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
    ConfigurationValue {
        id: webhookIdSetting
        key: Credentials.settingsPrefix + "webhookId"
        defaultValue: ""
    }
    // Same key as in harbour-hacontrol.qml (opt-in location reporting).
    // Same keys as SensorsView's weather card -- dconf notifies the other
    // instance, so the card switches as soon as a new entity is picked here.
    ConfigurationValue {
        id: weatherEntitySetting
        key: Credentials.settingsPrefix + "weatherEntity"
        defaultValue: ""
    }
    ConfigurationValue {
        id: weatherEntityNameSetting
        key: Credentials.settingsPrefix + "weatherEntityName"
        defaultValue: ""
    }
    function openWeatherPicker() {
        var picker = pageStack.push(Qt.resolvedUrl("EntityPickerPage.qml"), {
            headerTitle: qsTr("Weather"),
            description: qsTr("Shown at the top of the sensor overview and on the app cover."),
            domains: ["weather"],
            defaultLabel: qsTr("Automatic"),
            defaultDescription: qsTr("The first weather entity Home Assistant reports"),
            currentId: weatherEntitySetting.value,
            searchPlaceholder: qsTr("Search weather entities"),
            noMatchesHint: qsTr("No weather entity matches the search."),
            nothingHint: qsTr("Home Assistant has no weather entities.")
        })
        picker.picked.connect(function (entityId, name) {
            weatherEntitySetting.value = entityId
            weatherEntityNameSetting.value = entityId.length > 0 ? name : ""
        })
    }

    ConfigurationValue {
        id: reportLocationSetting
        key: Credentials.settingsPrefix + "reportLocation"
        defaultValue: false
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Delete instance")
                enabled: Credentials.profiles.length > 1 && !Credentials.saveBusy
                onClicked: page.deleteActiveProfile()
            }
            MenuItem {
                text: qsTr("Rename instance")
                onClicked: {
                    var dialog = pageStack.push(nameDialogComponent, {
                        dialogTitle: qsTr("Rename instance"), profileName: Credentials.activeProfileName
                    })
                    var id = Credentials.activeProfileId
                    dialog.accepted.connect(function () {
                        Credentials.renameProfile(id, dialog.profileName)
                    })
                }
            }
            MenuItem {
                text: qsTr("Add instance")
                onClicked: {
                    var dialog = pageStack.push(nameDialogComponent, { dialogTitle: qsTr("Add instance"), profileName: "" })
                    dialog.accepted.connect(function () {
                        page.switchProfile(Credentials.addProfile(dialog.profileName))
                    })
                }
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Settings")
            }

            // Which Home Assistant instance the fields below (and the whole
            // app) work with.
            ValueButton {
                width: parent.width
                //: Settings: selector for the active Home Assistant instance (profile)
                label: qsTr("Instance")
                value: Credentials.activeProfileName
                onClicked: pageStack.push(profilePickerComponent)
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                visible: Credentials.profiles.length > 1
                text: qsTr("Notifications for watched devices only come from the selected instance.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
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

            TextSwitch {
                text: qsTr("Report location to Home Assistant")
                description: qsTr("Sends this phone's position to this instance as its device tracker -- only at app start, on refresh and every 10 minutes in the background, never continuously. Off by default; turning it off stops reporting but doesn't delete positions already stored in Home Assistant.")
                checked: reportLocationSetting.value === true
                onClicked: reportLocationSetting.value = checked
            }

            SectionHeader {
                text: qsTr("Weather")
            }

            ValueButton {
                label: qsTr("Weather")
                value: weatherEntitySetting.value.length === 0
                    ? qsTr("Automatic")
                    : (weatherEntityNameSetting.value.length > 0 ? weatherEntityNameSetting.value : weatherEntitySetting.value)
                description: qsTr("Shown at the top of the sensor overview and on the app cover.")
                onClicked: openWeatherPicker()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Cover action")
                onClicked: pageStack.push(Qt.resolvedUrl("CoverSettingsPage.qml"))
            }
        }
    }
}
