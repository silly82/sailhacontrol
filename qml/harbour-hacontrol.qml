import QtQuick 2.6
import Sailfish.Silica 1.0
import org.nemomobile.configuration 1.0
import Nemo.KeepAlive 1.1
import org.nemomobile.notifications 1.0
import "pages"
import "lib/HaApi.js" as HaApi

ApplicationWindow {
    id: appWindow

    initialPage: Component { FirstPage {} }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    // Ausbaustufe 3, Variante B (s. KONZEPT.md): periodischer Background-Poll
    // statt echtem Push. Store-kompatibel (keine Sailjail-Sandbox-Ausnahme
    // nötig), im Gegensatz zu einem MQTT-Relay mit dauerhaft offenem Socket.
    // Wichtige Einschränkung, noch nicht auf Hardware verifiziert: das
    // funktioniert nur, solange dieser App-Prozess resident ist (im
    // Vordergrund oder kürzlich in den Hintergrund geschickt) -- ein vom
    // System vollständig beendeter Prozess wird dadurch NICHT wieder
    // gestartet. Außerdem ist unklar, ob der async XMLHttpRequest in
    // HaApi.getStates() zuverlässig innerhalb des IPHB-Wachfensters
    // abschließt, bevor die CPU wieder in Suspend geht.
    //
    // API-Korrektur (Emulator-Test 2026-08-28): die früher übliche
    // BackgroundActivity mit run()/wait() existiert in dieser
    // libkeepalive-Version nicht mehr -- registriert ist stattdessen
    // BackgroundJob mit enabled/frequency/onTriggered/finished().

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
        id: watchedSetting
        key: "/apps/harbour-hacontrol/watchedEntities"
        defaultValue: ""
    }
    // JSON-Map entityId -> letzter bekannter state-String, um Benachrichtigungen
    // nur bei tatsächlicher Änderung zu feuern (und nicht bei jedem Poll).
    ConfigurationValue {
        id: lastKnownStatesSetting
        key: "/apps/harbour-hacontrol/lastKnownStates"
        defaultValue: "{}"
    }

    function notifyStateChange(friendlyName, isOn) {
        var component = 'import QtQuick 2.0\nimport org.nemomobile.notifications 1.0\nNotification { appName: "HA Control"; category: "x-nemo.example" }'
        var notification = Qt.createQmlObject(component, appWindow, "HaControlNotification")
        notification.summary = friendlyName
        notification.body = isOn ? qsTr("eingeschaltet") : qsTr("ausgeschaltet")
        notification.publish()
    }

    BackgroundJob {
        id: pollActivity
        frequency: BackgroundJob.TenMinutes
        enabled: true

        onTriggered: {
            var baseUrl = baseUrlSetting.value
            var token = tokenSetting.value
            var watched = watchedSetting.value.split(",").map(function (s) { return s.trim() }).filter(function (s) { return s.length > 0 })

            if (baseUrl.length === 0 || token.length === 0 || watched.length === 0) {
                pollActivity.finished()
                return
            }

            HaApi.getStates(baseUrl, token,
                function (states) {
                    var lastKnown = {}
                    try {
                        lastKnown = JSON.parse(lastKnownStatesSetting.value)
                    } catch (e) {
                        lastKnown = {}
                    }

                    for (var i = 0; i < states.length; i++) {
                        var s = states[i]
                        if (watched.indexOf(s.entity_id) < 0) {
                            continue
                        }
                        var previous = lastKnown[s.entity_id]
                        if (previous !== undefined && previous !== s.state) {
                            notifyStateChange(s.attributes.friendly_name || s.entity_id, s.state === "on")
                        }
                        lastKnown[s.entity_id] = s.state
                    }

                    lastKnownStatesSetting.value = JSON.stringify(lastKnown)
                    pollActivity.finished()
                },
                function (error) {
                    // Stiller Fehlschlag -- kein UI sichtbar, das eine Fehlermeldung
                    // zeigen könnte, während der Poll im Hintergrund läuft.
                    pollActivity.finished()
                })
        }
    }
}
