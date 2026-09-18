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
CoverBackground {
    id: cover

    ConfigurationValue {
        id: lightsOnCountSetting
        key: "/apps/harbour-hacontrol/coverLightsOnCount"
        defaultValue: 0
    }
    ConfigurationValue {
        id: lastLightIdSetting
        key: "/apps/harbour-hacontrol/coverLastLightId"
        defaultValue: ""
    }
    ConfigurationValue {
        id: lastLightNameSetting
        key: "/apps/harbour-hacontrol/coverLastLightName"
        defaultValue: ""
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
                    return qsTr("Alle Lichter aus")
                }
                if (count === 1) {
                    return qsTr("1 Licht an")
                }
                return qsTr("%1 Lichter an").arg(count)
            }
        }
    }

    CoverActionList {
        // Kein Bulb-/Power-Icon im Stock-Theme verfügbar (nur icon-cover-
        // {alarm,answer,backup,camera,cancel,dialer,favorite,hangup,
        // location,message,mute,new,next(-song),pause,people,play,
        // previous(-song),record,refresh,reject,search,shuffle,subview,
        // sync,timer,transfers,unmute} -- per sfdk tools exec geprüft,
        // s. sailfishos-sdk-workflow-Memory). icon-cover-favorite passt
        // semantisch am ehesten ("dein zuletzt benutztes Licht").
        enabled: lastLightIdSetting.value.length > 0

        CoverAction {
            iconSource: "image://theme/icon-cover-favorite"
            onTriggered: {
                var entityId = lastLightIdSetting.value
                var domain = entityId.split(".")[0]
                HaApi.callService(Credentials.baseUrl, Credentials.token,
                    domain, "toggle", { entity_id: entityId },
                    function () {}, function () {})
            }
        }
    }
}
