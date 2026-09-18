import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import Nemo.KeepAlive 1.2
import Nemo.Notifications 1.0
import Nemo.DBus 2.0
import "pages"
import "components"
import "lib/HaApi.js" as HaApi

ApplicationWindow {
    id: appWindow

    initialPage: Component {
        FirstPage {
            // Pull-down-"Refresh" meldet zusätzlich den Geräte-Status an HA --
            // sonst käme der nur über den 10-Minuten-BackgroundJob, der im
            // Vordergrund nicht feuert (s. FirstPage.qml). Explizit über die
            // App-Id, damit die Auflösung nicht von der QML-Scope-Regel
            // "Funktionen des Wurzelobjekts derselben Datei" abhängt.
            onDeviceStatusRefreshRequested: appWindow.updateDeviceSensors()
        }
    }
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

    // HA-URL und Token liegen seit v0.51 nicht mehr hier (Klartext via
    // ConfigurationValue/dconf), sondern in Sailfish Secrets -- gekapselt in
    // src/credentials.{h,cpp} und per Context-Property als "Credentials" in
    // QML sichtbar (die QML-Singleton-Variante konnte nicht funktionieren, s.
    // Kopfkommentar in src/credentials.h). Die beiden folgenden
    // ConfigurationValues sind nur noch Migrationshilfe für
    // Bestandsinstallationen und werden danach geleert.
    ConfigurationValue {
        id: legacyBaseUrlSetting
        key: "/apps/harbour-hacontrol/baseUrl"
        defaultValue: ""
    }
    ConfigurationValue {
        id: legacyTokenSetting
        key: "/apps/harbour-hacontrol/token"
        defaultValue: ""
    }

    // Einmalig beim Start: vorhandene Klartextwerte nach Secrets übernehmen,
    // damit niemand sie neu eintippen muss. Läuft nur, solange in Secrets noch
    // nichts liegt -- und losgelöst vom Löschen der Klartext-Kopien (s.u.).
    function migrateLegacyCredentials() {
        if (!Credentials.loaded || Credentials.saveBusy) {
            return
        }
        if (Credentials.baseUrl.length > 0 || Credentials.token.length > 0) {
            return
        }
        var url = legacyBaseUrlSetting.value
        var token = legacyTokenSetting.value
        if (url.length === 0 || token.length === 0) {
            return
        }
        Credentials.save(url, token)
    }

    // Klartext in dconf erst löschen, wenn die verschlüsselte Kopie nachweislich
    // gespeichert ist: ein fehlgeschlagener Store würde die Zugangsdaten sonst
    // vernichten (genau das passierte beim ersten Versuch, bevor der
    // Speicher-Weg funktionierte).
    function clearLegacyCredentials() {
        if (legacyBaseUrlSetting.value.length > 0) {
            legacyBaseUrlSetting.value = ""
        }
        if (legacyTokenSetting.value.length > 0) {
            legacyTokenSetting.value = ""
        }
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

    // Ausbaustufe 3, Teil 2: echte mobile_app-Integration (Registrierung +
    // Push per WebSocket + Device-Status-Sensoren), s. KONZEPT.md. deviceId
    // wird einmalig generiert und bleibt stabil, solange die App nicht neu
    // installiert wird -- reicht für HA als Identität, keine Kryptoqualität
    // nötig.
    ConfigurationValue {
        id: deviceIdSetting
        key: "/apps/harbour-hacontrol/deviceId"
        defaultValue: ""
    }
    ConfigurationValue {
        id: deviceNameSetting
        key: "/apps/harbour-hacontrol/deviceName"
        defaultValue: qsTr("SailfishOS Phone")
    }
    ConfigurationValue {
        id: webhookIdSetting
        key: "/apps/harbour-hacontrol/webhookId"
        defaultValue: ""
    }

    DeviceStatusProbe {
        id: deviceStatusProbe
    }

    function randomDeviceId() {
        var chars = "0123456789abcdef"
        var id = ""
        for (var i = 0; i < 32; i++) {
            id += chars.charAt(Math.floor(Math.random() * chars.length))
        }
        return id
    }

    // Registriert dieses Gerät bei HA, falls URL+Token gültig sind und noch
    // keine webhookId gespeichert ist (erster Start, oder nach "Gerät neu
    // registrieren" in den Settings, das webhookIdSetting.value leert).
    function ensureMobileAppRegistered() {
        var baseUrl = Credentials.baseUrl
        var token = Credentials.token
        if (baseUrl.length === 0 || token.length === 0 || webhookIdSetting.value.length > 0) {
            return
        }
        if (deviceIdSetting.value.length === 0) {
            deviceIdSetting.value = randomDeviceId()
        }
        HaApi.registerMobileApp(baseUrl, token, deviceIdSetting.value, deviceNameSetting.value,
            function (result) {
                webhookIdSetting.value = result.webhook_id
                registerDeviceSensors()
            },
            function (error) {})
    }

    // register_sensor ist laut HA-Doku idempotent (zweiter Aufruf für die
    // gleiche unique_id aktualisiert nur den Zustand) -- kann darum bei
    // jeder Neuregistrierung ohne Sonderfall erneut aufgerufen werden.
    function registerDeviceSensors() {
        var baseUrl = Credentials.baseUrl
        var webhookId = webhookIdSetting.value
        if (baseUrl.length === 0 || webhookId.length === 0) {
            return
        }
        HaApi.callWebhook(baseUrl, webhookId, "register_sensor", {
            type: "sensor", unique_id: "battery_level", name: qsTr("Akkustand"),
            device_class: "battery", unit_of_measurement: "%", state_class: "measurement",
            icon: "mdi:battery", state: null
        }, function () {}, function () {})
        HaApi.callWebhook(baseUrl, webhookId, "register_sensor", {
            type: "binary_sensor", unique_id: "battery_charging", name: qsTr("Lädt"),
            device_class: "battery_charging", icon: "mdi:power-plug", state: false
        }, function () {}, function () {})
        HaApi.callWebhook(baseUrl, webhookId, "register_sensor", {
            type: "sensor", unique_id: "connection_type", name: qsTr("Verbindungsart"),
            icon: "mdi:wifi", state: "offline"
        }, function () {}, function () {})

        updateDeviceSensors()
    }

    function updateDeviceSensors() {
        var baseUrl = Credentials.baseUrl
        var webhookId = webhookIdSetting.value
        if (baseUrl.length === 0 || webhookId.length === 0) {
            console.log("DeviceSensors: übersprungen (URL " + baseUrl.length + " Zeichen, webhookId " + webhookId.length + " Zeichen)")
            return
        }
        deviceStatusProbe.query(function (status) {
            var sensors = [
                { type: "binary_sensor", unique_id: "battery_charging", state: status.charging },
                { type: "sensor", unique_id: "connection_type", state: status.connectionType }
            ]
            // -1 (unknown, z.B. auf dem SDK-Emulator ohne echten Akku) nicht
            // senden -- HA erwartet für device_class battery eine Zahl.
            if (status.batteryLevel >= 0) {
                sensors.push({ type: "sensor", unique_id: "battery_level", state: status.batteryLevel })
            }
            HaApi.callWebhook(baseUrl, webhookId, "update_sensor_states", sensors,
                function () { console.log("DeviceSensors: " + sensors.length + " Sensoren an HA gemeldet") },
                function (error) { console.log("DeviceSensors: Meldung fehlgeschlagen -- " + (error.hint || "unbekannt")) })
        })
    }

    Connections {
        target: Credentials
        onBaseUrlChanged: ensureMobileAppRegistered()
        onTokenChanged: ensureMobileAppRegistered()
        onLoadedChanged: {
            migrateLegacyCredentials()
            // Bei jedem App-Start einmal die Geräte-Sensoren melden: der
            // 10-Minuten-BackgroundJob feuert nicht, solange die App im
            // Vordergrund ist, sonst stünden die Sensoren in HA still.
            if (Credentials.loaded) {
                updateDeviceSensors()
            }
        }
        onLastSaveOkChanged: if (Credentials.lastSaveOk) clearLegacyCredentials()
    }
    Connections {
        target: webhookIdSetting
        onValueChanged: ensureMobileAppRegistered()
    }
    Component.onCompleted: ensureMobileAppRegistered()

    // D-Bus-Endpunkt für den "Umschalten"-Button auf der Benachrichtigung
    // (s. notifyStateChange() unten) -- rein in QML über Nemo.DBus'
    // DBusAdaptor, kein C++ nötig. service/path/iface ergeben sich aus dem
    // in .desktop/[X-Sailjail] konfigurierten OrganizationName+ApplicationName
    // (org.example.hacontrol), das Sailjail dem Prozess ohnehin schon als
    // eigenen D-Bus-Namen zuteilt. Gleiche Restriktion wie der Background-
    // Poll: funktioniert nur, während dieser App-Prozess resident ist -- bei
    // vollständig beendeter App läuft der Aufruf ins Leere (kein D-Bus-
    // Activation-.service-File vorhanden).
    DBusAdaptor {
        service: "org.example.hacontrol"
        path: "/org/example/hacontrol"
        iface: "org.example.hacontrol"

        function toggleEntity(entityId) {
            var domain = entityId.split(".")[0]
            HaApi.callService(Credentials.baseUrl, Credentials.token, domain, "toggle", { entity_id: entityId },
                function () {},
                function (error) {})
        }
    }

    function notifyStateChange(entityId, friendlyName, isOn) {
        var component = 'import QtQuick 2.0\nimport Nemo.Notifications 1.0\nNotification { appName: "HA Control"; category: "x-nemo.example" }'
        var notification = Qt.createQmlObject(component, appWindow, "HaControlNotification")
        notification.summary = friendlyName
        notification.body = isOn ? qsTr("eingeschaltet") : qsTr("ausgeschaltet")
        notification.remoteActions = [
            notification.remoteAction("toggle", qsTr("Umschalten"),
                "org.example.hacontrol", "/org/example/hacontrol", "org.example.hacontrol",
                "toggleEntity", [entityId])
        ]
        notification.publish()
    }

    BackgroundJob {
        id: pollActivity
        frequency: BackgroundJob.TenMinutes
        enabled: true

        onTriggered: {
            var baseUrl = Credentials.baseUrl
            var token = Credentials.token
            var watched = watchedSetting.value.split(",").map(function (s) { return s.trim() }).filter(function (s) { return s.length > 0 })

            // Huckepack auf dem ohnehin laufenden 10-Minuten-Intervall -- kein
            // eigener Timer für die Device-Status-Sensoren nötig.
            updateDeviceSensors()

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
                            notifyStateChange(s.entity_id, s.attributes.friendly_name || s.entity_id, s.state === "on")
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
