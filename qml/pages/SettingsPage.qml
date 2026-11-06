import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../components"

// Settings overview: the active instance (profiles in the pull-down menu)
// and one row per sub-page, each with a one-line summary of its state.
//   Connection        -> ConnectionSettingsPage.qml (URLs, mode, token)
//   Device & sensors  -> DeviceSettingsPage.qml (registration, location)
//   Cover & weather   -> CoverSettingsPage.qml (cover buttons, weather entity)
// Credentials are saved by ConnectionSettingsPage itself (on focus loss and
// when it is left), so nothing typed is pending while this page is shown.
Page {
    id: page

    allowedOrientations: Orientation.All

    readonly property bool configured: Credentials.baseUrl.length > 0 && Credentials.token.length > 0

    // First run: the views' placeholders send the user here to enter URL and
    // token, so go straight on to the Connection page -- once per visit, and
    // only after the secrets have loaded (before that every instance looks
    // unconfigured). Back returns here, with the Connection row highlighted.
    property bool _autoOpened: false
    onStatusChanged: {
        if (status === PageStatus.Active && !_autoOpened && Credentials.loaded && !configured) {
            _autoOpened = true
            pageStack.push(Qt.resolvedUrl("ConnectionSettingsPage.qml"))
        }
    }

    // --- Instances (profiles, see src/credentials.h) ---------------------
    // The sub-pages always edit the active instance. Nothing typed can be
    // pending here: ConnectionSettingsPage saves when it is left.
    function switchProfile(id) {
        if (id === Credentials.activeProfileId) {
            return
        }
        Credentials.setActiveProfile(id)
    }

    // Every setting stored under Credentials.settingsPrefix (grep for it in
    // qml/: the settings sub-pages, harbour-hacontrol.qml, the views and the
    // cover). Cleared when a profile is deleted -- profile ids are never
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
                // Text assigned in onCompleted, not bound: a TextField created
                // with a non-empty text logs a Silica-internal width binding
                // loop (see ConnectionSettingsPage.qml).
                TextField {
                    id: nameField
                    width: parent.width
                    focus: true
                    label: qsTr("Name")
                    //: Placeholder for the name of a Home Assistant instance
                    placeholderText: qsTr("e.g. Home, Camper")
                    Component.onCompleted: text = nameDialog.profileName
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

    // Read here only for the row summaries; the sub-pages own these.
    ConfigurationValue {
        id: deviceNameSetting
        key: "/apps/harbour-hacontrol/deviceName"
        defaultValue: qsTr("SailfishOS Phone")
    }
    ConfigurationValue {
        id: webhookIdSetting
        key: Credentials.settingsPrefix + "webhookId"
        defaultValue: ""
    }
    ConfigurationValue {
        id: coverTargetIdSetting
        key: Credentials.settingsPrefix + "coverTargetId"
        defaultValue: ""
    }
    ConfigurationValue {
        id: coverTargetNameSetting
        key: Credentials.settingsPrefix + "coverTargetName"
        defaultValue: ""
    }
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

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

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

            PageHeader {
                title: qsTr("Settings")
            }

            // Which Home Assistant instance the sub-pages (and the whole
            // app) work with.
            ValueButton {
                width: parent.width
                //: Settings: selector for the active Home Assistant instance (profile)
                label: qsTr("Instance")
                value: Credentials.activeProfileName
                description: Credentials.profiles.length > 1
                    ? qsTr("Notifications for watched devices only come from the selected instance.")
                    : ""
                onClicked: pageStack.push(profilePickerComponent)
            }

            Item { width: 1; height: Theme.paddingMedium }

            SettingsNavigationRow {
                iconSource: "image://theme/icon-m-link"
                //: Settings overview: row opening the URL/token page
                title: qsTr("Connection")
                attention: Credentials.loaded && !page.configured
                summary: !Credentials.loaded
                    ? ""
                    : (!page.configured
                       //: Settings overview: summary of the Connection row while URL or token is missing
                       ? qsTr("Not configured: enter URL and token")
                       : (Credentials.probing
                          ? qsTr("Checking whether the internal URL is reachable…")
                          : (Credentials.usingExternal
                             ? qsTr("Connected via: external URL")
                             : qsTr("Connected via: internal URL"))))
                onClicked: pageStack.push(Qt.resolvedUrl("ConnectionSettingsPage.qml"))
            }

            SettingsNavigationRow {
                iconSource: "image://theme/icon-m-phone"
                //: Settings overview: row opening the registration/location page
                title: qsTr("Device & sensors")
                summary: webhookIdSetting.value.length > 0
                    //: Settings overview: summary of the Device row, %1 = device name
                    ? qsTr("Registered as %1").arg(deviceNameSetting.value)
                    //: Settings overview: summary of the Device row
                    : qsTr("Not registered yet")
                onClicked: pageStack.push(Qt.resolvedUrl("DeviceSettingsPage.qml"))
            }

            SettingsNavigationRow {
                iconSource: "image://theme/icon-m-display"
                //: Settings overview: row opening the cover buttons/weather page
                title: qsTr("Cover & weather")
                //: Settings overview: summary of the Cover row, %1 = first cover button, %2 = weather entity
                summary: qsTr("%1 · Weather: %2")
                    .arg(coverTargetIdSetting.value.length === 0
                         ? qsTr("Last used light")
                         : (coverTargetNameSetting.value || coverTargetIdSetting.value))
                    .arg(weatherEntitySetting.value.length === 0
                         ? qsTr("Automatic")
                         : (weatherEntityNameSetting.value || weatherEntitySetting.value))
                onClicked: pageStack.push(Qt.resolvedUrl("CoverSettingsPage.qml"))
            }
        }

        VerticalScrollDecorator {}
    }
}
