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
// default when nothing is configured. An optional second button
// (coverTarget2*) and a weather line (coverWeatherText, written by
// SensorsView.qml) follow the same no-polling pattern.
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

    // Optional second button (CoverSettingsPage.qml). Empty id == none.
    ConfigurationValue {
        id: target2IdSetting
        key: Credentials.settingsPrefix + "coverTarget2Id"
        defaultValue: ""
    }
    ConfigurationValue {
        id: target2NameSetting
        key: Credentials.settingsPrefix + "coverTarget2Name"
        defaultValue: ""
    }
    ConfigurationValue {
        id: target2DomainSetting
        key: Credentials.settingsPrefix + "coverTarget2Domain"
        defaultValue: ""
    }
    // Weather line: SensorsView.qml writes the already translated text
    // ("12.5 °C, Partly cloudy") whenever it refreshes; empty == no weather
    // entity. coverShowWeather is the switch in CoverSettingsPage.qml.
    ConfigurationValue {
        id: weatherTextSetting
        key: Credentials.settingsPrefix + "coverWeatherText"
        defaultValue: ""
    }
    ConfigurationValue {
        id: showWeatherSetting
        key: Credentials.settingsPrefix + "coverShowWeather"
        defaultValue: true
    }

    readonly property bool useLastLight: targetIdSetting.value.length === 0
    readonly property string actionEntityId: useLastLight ? lastLightIdSetting.value : targetIdSetting.value
    readonly property string actionName: useLastLight ? lastLightNameSetting.value : targetNameSetting.value
    readonly property string actionDomain: useLastLight
        ? actionEntityId.split(".")[0]
        : (targetDomainSetting.value || actionEntityId.split(".")[0])
    readonly property bool runsOnce: actionDomain === "scene" || actionDomain === "script"

    readonly property string action2EntityId: target2IdSetting.value
    readonly property string action2Name: target2NameSetting.value
    readonly property string action2Domain: target2DomainSetting.value || action2EntityId.split(".")[0]
    readonly property bool runs2Once: action2Domain === "scene" || action2Domain === "script"

    readonly property bool hasAction1: actionEntityId.length > 0
    readonly property bool hasAction2: action2EntityId.length > 0
    readonly property bool hasBoth: hasAction1 && hasAction2
    readonly property string weatherText: showWeatherSetting.value === true ? weatherTextSetting.value : ""

    // Kein Bulb-/Power-Icon im Stock-Theme verfügbar (nur icon-cover-
    // {alarm,answer,backup,camera,cancel,dialer,favorite,hangup,
    // location,message,mute,new,next(-song),pause,people,play,
    // previous(-song),record,refresh,reject,search,shuffle,subview,
    // sync,timer,transfers,unmute} -- per sfdk tools exec geprüft,
    // s. sailfishos-sdk-workflow-Memory). icon-cover-favorite passt
    // semantisch am ehesten ("dein zuletzt benutztes Licht") und bleibt
    // für alles, was umgeschaltet wird (light/switch); Szenen und
    // Skripte werden "abgespielt" -> icon-cover-play.
    function iconFor(once) {
        return once ? "image://theme/icon-cover-play" : "image://theme/icon-cover-favorite"
    }

    function trigger(entityId, domain, once) {
        HaApi.callService(Credentials.baseUrl, Credentials.token,
            domain, once ? "turn_on" : "toggle",
            { entity_id: entityId },
            function () {}, function () {})
    }

    // Text area above the action bar, so up to five short lines never run
    // under the buttons.
    Item {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: (cover.hasAction1 || cover.hasAction2) ? Theme.itemSizeSmall : 0
        }

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
                truncationMode: TruncationMode.Fade
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                truncationMode: TruncationMode.Elide
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
                visible: cover.weatherText.length > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                truncationMode: TruncationMode.Elide
                maximumLineCount: 1
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: cover.weatherText
            }
            // Names of whatever the cover buttons trigger, so it is clear
            // what tapping them will do. With two buttons each name gets one
            // line (first = left button, second = right button).
            Label {
                visible: cover.hasAction1
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                truncationMode: TruncationMode.Elide
                maximumLineCount: cover.hasBoth ? 1 : 2
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.highlightColor
                text: cover.actionName || cover.actionEntityId
            }
            Label {
                visible: cover.hasAction2
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                truncationMode: TruncationMode.Elide
                maximumLineCount: cover.hasBoth ? 1 : 2
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.highlightColor
                text: cover.action2Name || cover.action2EntityId
            }
        }
    }

    // CoverAction has no visible/enabled property, and only one
    // CoverActionList may be enabled at a time -- so there is one list per
    // combination of configured buttons. Order inside a list = left to right.
    CoverActionList {
        enabled: cover.hasAction1 && !cover.hasAction2

        CoverAction {
            iconSource: cover.iconFor(cover.runsOnce)
            onTriggered: cover.trigger(cover.actionEntityId, cover.actionDomain, cover.runsOnce)
        }
    }
    CoverActionList {
        enabled: cover.hasAction2 && !cover.hasAction1

        CoverAction {
            iconSource: cover.iconFor(cover.runs2Once)
            onTriggered: cover.trigger(cover.action2EntityId, cover.action2Domain, cover.runs2Once)
        }
    }
    CoverActionList {
        enabled: cover.hasBoth

        CoverAction {
            iconSource: cover.iconFor(cover.runsOnce)
            onTriggered: cover.trigger(cover.actionEntityId, cover.actionDomain, cover.runsOnce)
        }
        CoverAction {
            iconSource: cover.iconFor(cover.runs2Once)
            onTriggered: cover.trigger(cover.action2EntityId, cover.action2Domain, cover.runs2Once)
        }
    }
}
