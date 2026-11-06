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
        // The plaintext predecessor only ever knew one instance -- profile 0.
        if (Credentials.activeProfileId !== 0) {
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

    // Several Home Assistant instances (profiles, see src/credentials.h).
    // The list ({id, name}, JSON) and the active id are not secret: plain
    // dconf, handed to Credentials once at startup (restoreProfiles() in
    // Component.onCompleted, before the secrets load starts) and written back
    // whenever Credentials changes them. Both empty/0 on every install up to
    // v0.56, which Credentials reads as "profile 0 only" -- the very instance
    // stored under the old secret names and dconf keys.
    //
    // Instance-specific values (favorites, watched entities, last known
    // states, cover target/counters, connection mode, mobile_app webhookId)
    // are keyed per profile: `Credentials.settingsPrefix + "<name>"`, which is
    // the old key for profile 0 and /apps/harbour-hacontrol/profiles/<id>/
    // otherwise. deviceId/deviceName stay global: one phone, one identity,
    // registered separately with each instance (each gets its own webhookId).
    // The list of those names is kept in SettingsPage.qml
    // (profileScopedSettings), which clears them when a profile is deleted.
    ConfigurationValue {
        id: profileListSetting
        key: "/apps/harbour-hacontrol/profileList"
        defaultValue: ""
    }
    ConfigurationValue {
        id: activeProfileSetting
        key: "/apps/harbour-hacontrol/activeProfile"
        defaultValue: 0
    }
    Connections {
        target: Credentials
        onProfilesChanged: {
            if (profileListSetting.value !== Credentials.profilesConfig) {
                profileListSetting.value = Credentials.profilesConfig
            }
        }
        onActiveProfileIdChanged: {
            if (activeProfileSetting.value !== Credentials.activeProfileId) {
                activeProfileSetting.value = Credentials.activeProfileId
            }
        }
    }

    // Writes one instance-specific value of a profile that may no longer be
    // the active one (an async answer arriving after a switch).
    function setProfileValue(profileId, name, value) {
        var item = Qt.createQmlObject('import Nemo.Configuration 1.0\nConfigurationValue {}', appWindow, "ProfileValue")
        item.key = Credentials.settingsPrefixFor(profileId) + name
        item.value = value
        item.destroy()
    }

    // Internal/external URL selection (0 = automatic, 1 = internal only,
    // 2 = external only; Credentials.ConnectionMode in src/credentials.h).
    // Not a secret, so plain dconf; Credentials only holds it in memory.
    // Per profile; the key switches with the active profile and the Binding
    // pushes that profile's mode in.
    ConfigurationValue {
        id: connectionModeSetting
        key: Credentials.settingsPrefix + "connectionMode"
        defaultValue: 0
    }
    Binding {
        target: Credentials
        property: "connectionMode"
        value: connectionModeSetting.value
    }

    // Background poll and notifications cover the *active* profile only: the
    // poll below reads the active instance's watched entities and URL. A
    // second instance is not polled while it isn't selected.
    ConfigurationValue {
        id: watchedSetting
        key: Credentials.settingsPrefix + "watchedEntities"
        defaultValue: ""
    }
    // JSON-Map entityId -> letzter bekannter state-String, um Benachrichtigungen
    // nur bei tatsächlicher Änderung zu feuern (und nicht bei jedem Poll).
    ConfigurationValue {
        id: lastKnownStatesSetting
        key: Credentials.settingsPrefix + "lastKnownStates"
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
        key: Credentials.settingsPrefix + "webhookId"
        defaultValue: ""
    }

    DeviceStatusProbe {
        id: deviceStatusProbe
    }

    // Opt-in (Settings > "Report location to Home Assistant"), per instance.
    ConfigurationValue {
        id: reportLocationSetting
        key: Credentials.settingsPrefix + "reportLocation"
        defaultValue: false
    }
    LocationProbe {
        id: locationProbe
    }
    // webhookId for which this app session already sent register_sensor for
    // every sensor -- so installs registered before a sensor was added get
    // it too, without re-registering the device (register_sensor is safe to
    // repeat for an existing unique_id).
    property string sensorsRegisteredFor: ""

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
        // Each instance gets its own registration (webhookId is per profile).
        // If the user switched instances meanwhile, the answer still belongs
        // to the one it was sent to.
        var profileId = Credentials.activeProfileId
        HaApi.registerMobileApp(baseUrl, token, deviceIdSetting.value, deviceNameSetting.value,
            function (result) {
                if (profileId !== Credentials.activeProfileId) {
                    setProfileValue(profileId, "webhookId", result.webhook_id)
                    return
                }
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
            type: "sensor", unique_id: "battery_level", name: qsTr("Battery level"),
            device_class: "battery", unit_of_measurement: "%", state_class: "measurement",
            icon: "mdi:battery", state: null
        }, function () {}, function () {})
        HaApi.callWebhook(baseUrl, webhookId, "register_sensor", {
            type: "binary_sensor", unique_id: "battery_charging", name: qsTr("Charging"),
            device_class: "battery_charging", icon: "mdi:power-plug", state: false
        }, function () {}, function () {})
        HaApi.callWebhook(baseUrl, webhookId, "register_sensor", {
            type: "sensor", unique_id: "connection_type", name: qsTr("Connection type"),
            icon: "mdi:wifi", state: "offline"
        }, function () {}, function () {})
        registerExtraDeviceSensors(baseUrl, webhookId, function () {})

        updateDeviceSensors()
    }

    // Sensors added after the first three (v0.56). Also sent once per app
    // session for already registered installs (see updateDeviceSensors()),
    // calling onDone when all requests are answered, so the following
    // update_sensor_states doesn't race ahead of the registration.
    function registerExtraDeviceSensors(baseUrl, webhookId, onDone) {
        sensorsRegisteredFor = webhookId
        var sensors = [
            { type: "sensor", unique_id: "wifi_connection", name: qsTr("Wi-Fi connection"),
              icon: "mdi:wifi", state: null },
            { type: "sensor", unique_id: "wifi_signal_strength", name: qsTr("Wi-Fi signal strength"),
              icon: "mdi:wifi-strength-2", unit_of_measurement: "%", state_class: "measurement",
              entity_category: "diagnostic", state: null },
            { type: "sensor", unique_id: "storage", name: qsTr("Free storage"),
              icon: "mdi:harddisk", device_class: "data_size", unit_of_measurement: "GB",
              state_class: "measurement", entity_category: "diagnostic", state: null }
        ]
        var pending = sensors.length
        function answered() {
            pending -= 1
            if (pending === 0) {
                onDone()
            }
        }
        for (var i = 0; i < sensors.length; i++) {
            HaApi.callWebhook(baseUrl, webhookId, "register_sensor", sensors[i], answered, answered)
        }
    }

    function updateDeviceSensors() {
        var baseUrl = Credentials.baseUrl
        var webhookId = webhookIdSetting.value
        if (baseUrl.length === 0 || webhookId.length === 0) {
            console.log("DeviceSensors: übersprungen (URL " + baseUrl.length + " Zeichen, webhookId " + webhookId.length + " Zeichen)")
            return
        }
        if (sensorsRegisteredFor !== webhookId) {
            registerExtraDeviceSensors(baseUrl, webhookId, updateDeviceSensors)
            return
        }
        deviceStatusProbe.query(function (status) {
            var sensors = [
                { type: "binary_sensor", unique_id: "battery_charging", state: status.charging },
                { type: "sensor", unique_id: "connection_type", state: status.connectionType },
                { type: "sensor", unique_id: "wifi_connection",
                  state: status.wifiSsid.length > 0 ? status.wifiSsid : "Not connected" },
                { type: "sensor", unique_id: "wifi_signal_strength",
                  state: status.wifiStrength >= 0 ? status.wifiStrength : null }
            ]
            // -1 (unknown, z.B. auf dem SDK-Emulator ohne echten Akku) nicht
            // senden -- HA erwartet für device_class battery eine Zahl.
            if (status.batteryLevel >= 0) {
                sensors.push({ type: "sensor", unique_id: "battery_level", state: status.batteryLevel })
            }
            if (status.freeStorageGb >= 0) {
                sensors.push({ type: "sensor", unique_id: "storage", state: status.freeStorageGb })
            }
            HaApi.callWebhook(baseUrl, webhookId, "update_sensor_states", sensors,
                function () { console.log("DeviceSensors: " + sensors.length + " Sensoren an HA gemeldet") },
                function (error) { console.log("DeviceSensors: Meldung fehlgeschlagen -- " + (error.hint || "unbekannt")) })
        })
        // Opt-in only; the position source runs just until this one fix.
        // Coordinates are never logged.
        if (reportLocationSetting.value === true) {
            locationProbe.query(function (location) {
                if (!location) {
                    return
                }
                HaApi.callWebhook(baseUrl, webhookId, "update_location", location,
                    function () { console.log("DeviceSensors: Standort an HA gemeldet") },
                    function (error) { console.log("DeviceSensors: Standort-Meldung fehlgeschlagen -- " + (error.hint || "unbekannt")) })
            })
        }
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
    Component.onCompleted: {
        // Before anything else talks to Credentials: decides which profile's
        // secrets get loaded.
        Credentials.restoreProfiles(profileListSetting.value, activeProfileSetting.value)
        ensureMobileAppRegistered()
    }

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
            // Nur Domains, deren Benachrichtigung überhaupt einen Toggle-
            // Button trägt -- dieser D-Bus-Endpunkt ist für jeden Prozess
            // der Session erreichbar, eine Alarmanlage (alarm_control_panel)
            // oder ein Schloss darf darüber nie umgeschaltet werden.
            if (appWindow.toggleNotificationDomains.indexOf(domain) < 0) {
                return
            }
            HaApi.callService(Credentials.baseUrl, Credentials.token, domain, "toggle", { entity_id: entityId },
                function () {},
                function (error) {})
        }
    }

    // Domains, deren "Notify on change"-Benachrichtigung einen Toggle-Button
    // bekommt (alle mit <domain>.toggle-Service, die RoomsView.qml für
    // Notify zulässt). alarm_control_panel bewusst nicht: Benachrichtigung
    // ja, Umschalten per Benachrichtigung nie.
    readonly property var toggleNotificationDomains: ["light", "switch", "fan", "cover", "input_boolean", "climate", "media_player"]

    function alarmStateLabel(state) {
        switch (state) {
        case "disarmed": return qsTr("Disarmed")
        case "armed_home": return qsTr("Armed home")
        case "armed_away": return qsTr("Armed away")
        case "armed_night": return qsTr("Armed night")
        case "armed_vacation": return qsTr("Armed vacation")
        case "armed_custom_bypass": return qsTr("Armed custom bypass")
        case "arming": return qsTr("Arming")
        case "disarming": return qsTr("Disarming")
        case "pending": return qsTr("Pending")
        case "triggered": return qsTr("Triggered")
        case "unavailable": return qsTr("Unavailable")
        default: return state
        }
    }

    function notifyStateChange(entityId, friendlyName, isOn, newState) {
        var domain = entityId.split(".")[0]
        var component = 'import QtQuick 2.0\nimport Nemo.Notifications 1.0\nNotification { appName: "HA Control"; category: "x-nemo.example" }'
        var notification = Qt.createQmlObject(component, appWindow, "HaControlNotification")
        notification.summary = friendlyName
        if (domain === "alarm_control_panel") {
            notification.body = alarmStateLabel(newState)
            // "triggered" soll auffallen.
            if (newState === "triggered") {
                notification.urgency = Notification.Critical
            }
        } else {
            notification.body = isOn ? qsTr("switched on") : qsTr("switched off")
        }
        if (toggleNotificationDomains.indexOf(domain) >= 0) {
            notification.remoteActions = [
                notification.remoteAction("toggle", qsTr("Toggle"),
                    "org.example.hacontrol", "/org/example/hacontrol", "org.example.hacontrol",
                    "toggleEntity", [entityId])
            ]
        }
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

            var profileId = Credentials.activeProfileId
            HaApi.getStates(baseUrl, token,
                function (states) {
                    // Switched instances meanwhile: these states belong to
                    // the other one, and lastKnownStatesSetting already
                    // points at the new profile's key.
                    if (profileId !== Credentials.activeProfileId) {
                        pollActivity.finished()
                        return
                    }
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
                            notifyStateChange(s.entity_id, s.attributes.friendly_name || s.entity_id, s.state === "on", s.state)
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
