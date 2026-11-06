import QtQuick 2.6
import Nemo.Configuration 1.0
import Nemo.Notifications 1.0
import "../lib/HaApi.js" as HaApi

// Push notifications from Home Assistant (notify.mobile_app_<device>, arriving
// over the WebSocket push channel in RoomsView.qml) and what happens when the
// user taps one of their buttons.
//
// Supported from the HA companion-app payload:
//   message, title
//   data.actions: [{ action: "KEY", title: "Text" }, { action: "URI", title: "Text", uri: "https://..." }]
//                 -- at most 3 buttons; uri actions only for http(s), others are dropped
//   data.tag:     a later notification with the same tag replaces this one
//   message "clear_notification" + data.tag: closes the tagged notification
//
// Each button is a Nemo.Notifications remote action calling back into the app
// over D-Bus (org.example.hacontrol, the DBusAdaptor in harbour-hacontrol.qml).
// Everything the callback needs travels in the action's arguments, which
// lipstick keeps with the notification: the profile (instance) id, the action
// key, the tag and a per-notification nonce. Nothing secret -- the webhookId is
// looked up from dconf when the action fires. Because of that the action also
// works after the app was closed (D-Bus activation via ExecDBus in the .desktop
// file starts it) and after a switch to another instance: it is fired at the
// instance the notification came from, with that profile's webhookId and URL.
Item {
    id: root
    visible: false

    readonly property string dbusService: "org.example.hacontrol"
    readonly property string dbusPath: "/org/example/hacontrol"
    readonly property string dbusIface: "org.example.hacontrol"
    readonly property int maxActions: 3

    // Nonces of actions already executed. lipstick normally removes a
    // notification once one of its actions was invoked, but a double tap or a
    // repeated D-Bus delivery must not open the gate twice. Persisted, so a
    // restart in between doesn't forget them; capped to the most recent ones.
    ConfigurationValue {
        id: handledNoncesSetting
        key: "/apps/harbour-hacontrol/handledNotificationActions"
        defaultValue: "[]"
    }

    // Only used for its notifications() method (lists this app's notifications
    // still shown, with their remote actions -- that is how a tag is found).
    Notification {
        id: lister
    }

    // Work waiting for Credentials to finish loading (D-Bus activation: the
    // call arrives before the Secrets daemon has answered).
    property var pendingWork: []
    // readProfileUrls() requests in flight: requestId -> { webhookId, data, what }
    property var pendingUrlReads: ({})
    property int nextUrlRequestId: 1

    function randomNonce() {
        var chars = "0123456789abcdef"
        var s = ""
        for (var i = 0; i < 16; i++) {
            s += chars.charAt(Math.floor(Math.random() * chars.length))
        }
        return s
    }

    function isHttpUrl(uri) {
        return typeof uri === "string" && /^https?:\/\/[^\s]+$/i.test(uri)
    }

    // ---- incoming push -------------------------------------------------

    function show(event, profileId) {
        if (!event) {
            return
        }
        var data = (event.data && typeof event.data === "object") ? event.data : {}
        var tag = (data.tag !== undefined && data.tag !== null) ? String(data.tag) : ""
        var pid = String(profileId)

        if (event.message === "clear_notification") {
            if (tag.length > 0) {
                closeTagged(pid, tag)
            }
            return
        }

        var nonce = randomNonce()
        var component = 'import QtQuick 2.0\nimport Nemo.Notifications 1.0\nNotification { appName: "HA Control"; category: "x-nemo.example" }'
        var notification = Qt.createQmlObject(component, root, "HaControlPushNotification")
        notification.summary = event.title || qsTr("Home Assistant")
        notification.body = event.message || ""
        if (tag.length > 0) {
            var existing = findTagged(pid, tag)
            if (existing > 0) {
                notification.replacesId = existing
            }
        }

        // "default" = tapping the notification itself: opens the app. It also
        // carries profile + tag, which findTagged() reads back later.
        var actions = [
            notification.remoteAction("default", "",
                dbusService, dbusPath, dbusIface, "openNotification", [pid, tag, nonce])
        ]
        var list = Array.isArray(data.actions) ? data.actions : []
        var buttons = 0
        for (var i = 0; i < list.length && buttons < maxActions; i++) {
            var a = list[i]
            if (!a || typeof a !== "object") {
                continue
            }
            var title = String(a.title || a.action || "")
            if (a.uri !== undefined && a.uri !== null && String(a.uri).length > 0) {
                // Only web links; anything else (app schemes, intents,
                // "entityId:..." deep links of the Android app) is ignored.
                if (!isHttpUrl(String(a.uri)) || title.length === 0) {
                    continue
                }
                actions.push(notification.remoteAction("action" + i, title,
                    dbusService, dbusPath, dbusIface, "openNotificationUri", [String(a.uri), nonce]))
                buttons++
            } else if (a.action !== undefined && a.action !== null && String(a.action).length > 0) {
                actions.push(notification.remoteAction("action" + i, title,
                    dbusService, dbusPath, dbusIface, "notificationAction", [pid, String(a.action), tag, nonce]))
                buttons++
            }
        }
        notification.remoteActions = actions
        notification.publish()
        notification.destroy()
    }

    // replacesId of the shown notification with this profile + tag, or 0.
    function findTagged(pid, tag) {
        var found = 0
        var shown = lister.notifications()
        for (var i = 0; i < shown.length; i++) {
            var n = shown[i]
            if (found === 0) {
                var actions = n.remoteActions || []
                for (var j = 0; j < actions.length; j++) {
                    var act = actions[j]
                    var args = act.arguments || []
                    if (act.name === "default" && act.method === "openNotification"
                            && args.length >= 2 && String(args[0]) === pid && String(args[1]) === tag) {
                        found = n.replacesId
                        break
                    }
                }
            }
            n.destroy()
        }
        return found
    }

    function closeTagged(pid, tag) {
        var id = findTagged(pid, tag)
        if (id <= 0) {
            return
        }
        var component = 'import QtQuick 2.0\nimport Nemo.Notifications 1.0\nNotification {}'
        var notification = Qt.createQmlObject(component, root, "HaControlCloseNotification")
        notification.replacesId = id
        notification.close()
        notification.destroy()
    }

    // ---- D-Bus callbacks (called by the DBusAdaptor) --------------------

    // true the first time a nonce is seen, false for repeats.
    function claimNonce(nonce) {
        if (!nonce || String(nonce).length === 0) {
            return true
        }
        var handled = []
        try {
            handled = JSON.parse(handledNoncesSetting.value)
        } catch (e) {
            handled = []
        }
        if (!Array.isArray(handled)) {
            handled = []
        }
        if (handled.indexOf(String(nonce)) >= 0) {
            console.log("PushNotifications: action already handled, ignored")
            return false
        }
        handled.push(String(nonce))
        if (handled.length > 50) {
            handled = handled.slice(handled.length - 50)
        }
        handledNoncesSetting.value = JSON.stringify(handled)
        return true
    }

    // Runs fn once Credentials has loaded the active profile.
    function whenLoaded(fn) {
        if (Credentials.loaded) {
            fn()
            return
        }
        var queue = pendingWork
        queue.push(fn)
        pendingWork = queue
    }

    Connections {
        target: Credentials
        onLoadedChanged: {
            if (!Credentials.loaded || root.pendingWork.length === 0) {
                return
            }
            var queue = root.pendingWork
            root.pendingWork = []
            for (var i = 0; i < queue.length; i++) {
                queue[i]()
            }
        }
        onProfileUrlsRead: root.onUrlsRead(requestId, profileId, internalUrl, externalUrl)
    }

    function readProfileValue(profileId, name) {
        var item = Qt.createQmlObject('import Nemo.Configuration 1.0\nConfigurationValue { defaultValue: "" }', root, "ProfileValueRead")
        item.key = Credentials.settingsPrefixFor(profileId) + name
        var value = item.value
        item.destroy()
        return value === undefined || value === null ? "" : String(value)
    }

    function profileExists(profileId) {
        var profiles = Credentials.profiles
        for (var i = 0; i < profiles.length; i++) {
            if (profiles[i].id === profileId) {
                return true
            }
        }
        return false
    }

    function handleAction(pidString, actionKey, tag, nonce) {
        if (!claimNonce(nonce)) {
            return
        }
        var profileId = parseInt(pidString, 10)
        if (isNaN(profileId) || !profileExists(profileId)) {
            console.log("PushNotifications: action for a removed instance, dropped")
            return
        }
        var eventData = { action: String(actionKey) }
        if (tag && String(tag).length > 0) {
            eventData.tag = String(tag)
        }
        fireEvent(profileId, {
            event_type: "mobile_app_notification_action",
            event_data: eventData
        })
    }

    // fire_event through the profile's mobile_app webhook. For the active
    // profile via the effective URL Credentials already picked (internal or
    // external); for another profile its stored URLs are read from Secrets
    // (only the URL -- a webhook needs no token), internal first, external if
    // the internal host can't be reached.
    function fireEvent(profileId, data) {
        if (profileId === Credentials.activeProfileId) {
            whenLoaded(function () {
                // Switched instances while waiting: go the other-profile way.
                if (profileId !== Credentials.activeProfileId) {
                    fireEvent(profileId, data)
                    return
                }
                var webhookId = readProfileValue(profileId, "webhookId")
                var baseUrl = Credentials.baseUrl
                if (baseUrl.length === 0 || webhookId.length === 0) {
                    console.log("PushNotifications: instance not configured/registered, action dropped")
                    return
                }
                HaApi.callWebhook(baseUrl, webhookId, "fire_event", data,
                    function () { console.log("PushNotifications: action event sent") },
                    function (error) { console.log("PushNotifications: action event failed -- " + (error.hint || "unknown")) })
            })
            return
        }
        var webhookId = readProfileValue(profileId, "webhookId")
        if (webhookId.length === 0) {
            console.log("PushNotifications: instance not registered, action dropped")
            return
        }
        var requestId = nextUrlRequestId
        nextUrlRequestId += 1
        var reads = pendingUrlReads
        reads[requestId] = { webhookId: webhookId, data: data }
        pendingUrlReads = reads
        Credentials.readProfileUrls(profileId, requestId)
    }

    function onUrlsRead(requestId, profileId, internalUrl, externalUrl) {
        var job = pendingUrlReads[requestId]
        if (!job) {
            return
        }
        var reads = pendingUrlReads
        delete reads[requestId]
        pendingUrlReads = reads

        var urls = []
        if (internalUrl.length > 0) {
            urls.push(internalUrl)
        }
        if (externalUrl.length > 0) {
            urls.push(externalUrl)
        }
        if (urls.length === 0) {
            console.log("PushNotifications: no URL stored for that instance, action dropped")
            return
        }
        sendWithFallback(urls, 0, job.webhookId, job.data)
    }

    // Tries the next URL only if the previous one never answered (HTTP 0 --
    // host unreachable); any HTTP answer means HA got the request, and trying
    // again elsewhere could fire the event twice.
    function sendWithFallback(urls, index, webhookId, data) {
        HaApi.callWebhook(urls[index], webhookId, "fire_event", data,
            function () { console.log("PushNotifications: action event sent (other instance)") },
            function (error) {
                if (error.hint === "HTTP 0" && index + 1 < urls.length) {
                    sendWithFallback(urls, index + 1, webhookId, data)
                    return
                }
                console.log("PushNotifications: action event failed -- " + (error.hint || "unknown"))
            })
    }

    function handleUri(uri, nonce) {
        if (!claimNonce(nonce)) {
            return
        }
        // Arguments come over D-Bus: check again rather than trust them.
        if (isHttpUrl(String(uri))) {
            Qt.openUrlExternally(String(uri))
        }
    }
}
