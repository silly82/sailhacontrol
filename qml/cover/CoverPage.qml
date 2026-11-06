import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../lib/HaApi.js" as HaApi

// Zeigt Live-Infos (Anzahl eingeschalteter Lichter) und bietet eine
// CoverAction zum Umschalten des zuletzt bedienten Lichts -- beides von
// RoomsView.qml über ConfigurationValues nachgeführt (gleiches Muster wie
// webhookIdSetting: separate ConfigurationValue-Instanzen auf denselben
// dconf-Keys), damit der Cover selbst keine eigene HA-Abfrage braucht,
// während die App im Hintergrund ist.
// Since CoverSettingsPage.qml the action can instead target a fixed scene,
// script, light or switch (coverTarget* values); "last used light" stays the
// default when nothing is configured.
CoverBackground {
    id: cover

    ConfigurationValue {
        id: lightsOnCountSetting
        key: Credentials.settingsPrefix + "coverLightsOnCount"
        defaultValue: 0
    }
    ConfigurationValue {
        id: lastLightIdSetting
        key: Credentials.settingsPrefix + "coverLastLightId"
        defaultValue: ""
    }
    ConfigurationValue {
        id: lastLightNameSetting
        key: Credentials.settingsPrefix + "coverLastLightName"
        defaultValue: ""
    }
    // Configured in CoverSettingsPage.qml. Empty id == "last used light"
    // (the lastLight* values above); otherwise the stored entity is triggered
    // directly. Name/domain are stored with it so nothing has to be fetched.
    ConfigurationValue {
        id: targetIdSetting
        key: Credentials.settingsPrefix + "coverTargetId"
        defaultValue: ""
    }
    ConfigurationValue {
        id: targetNameSetting
        key: Credentials.settingsPrefix + "coverTargetName"
        defaultValue: ""
    }
    ConfigurationValue {
        id: targetDomainSetting
        key: Credentials.settingsPrefix + "coverTargetDomain"
        defaultValue: ""
    }

    readonly property bool useLastLight: targetIdSetting.value.length === 0
    readonly property string actionEntityId: useLastLight ? lastLightIdSetting.value : targetIdSetting.value
    readonly property string actionName: useLastLight ? lastLightNameSetting.value : targetNameSetting.value
    readonly property string actionDomain: useLastLight
        ? actionEntityId.split(".")[0]
        : (targetDomainSetting.value || actionEntityId.split(".")[0])
    readonly property bool runsOnce: actionDomain === "scene" || actionDomain === "script"

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("HA Control")
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.primaryColor
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
            text: {
                var count = lightsOnCountSetting.value
                if (count === 0) {
                    return qsTr("All lights off")
                }
                //: Cover text, %n = number of lights that are on
                return qsTr("%n light(s) on", "", count)
            }
        }
        Label {
            // Name of whatever the cover button triggers, so it is clear
            // what tapping it will do.
            visible: cover.actionEntityId.length > 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            truncationMode: TruncationMode.Elide
            maximumLineCount: 2
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.highlightColor
            text: cover.actionName || cover.actionEntityId
        }
    }

    CoverActionList {
        // Kein Bulb-/Power-Icon im Stock-Theme verfügbar (nur icon-cover-
        // {alarm,answer,backup,camera,cancel,dialer,favorite,hangup,
        // location,message,mute,new,next(-song),pause,people,play,
        // previous(-song),record,refresh,reject,search,shuffle,subview,
        // sync,timer,transfers,unmute} -- per sfdk tools exec geprüft,
        // s. sailfishos-sdk-workflow-Memory). icon-cover-favorite passt
        // semantisch am ehesten ("dein zuletzt benutztes Licht") und bleibt
        // für alles, was umgeschaltet wird (light/switch); Szenen und
        // Skripte werden "abgespielt" -> icon-cover-play.
        enabled: cover.actionEntityId.length > 0

        CoverAction {
            iconSource: cover.runsOnce ? "image://theme/icon-cover-play"
                                       : "image://theme/icon-cover-favorite"
            onTriggered: {
                var entityId = cover.actionEntityId
                var domain = cover.actionDomain
                HaApi.callService(Credentials.baseUrl, Credentials.token,
                    domain, cover.runsOnce ? "turn_on" : "toggle",
                    { entity_id: entityId },
                    function () {}, function () {})
            }
        }
    }
}
