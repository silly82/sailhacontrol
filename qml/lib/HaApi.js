.pragma library

// Thin wrapper around Home Assistant's REST API using QML's built-in
// XMLHttpRequest -- no native bridge needed for Ausbaustufe 1 (unlike
// sailtalerwallet's WalletCoreBridge), since HA's REST API is plain HTTP+JSON.
// Callback-style (not Promises): keeps this consistent with the rest of the
// SailfishOS QML environment where Promise support can't be relied on.

function request(method, baseUrl, token, path, body, onSuccess, onError) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) {
            return
        }
        if (xhr.status >= 200 && xhr.status < 300) {
            var result = null
            try {
                result = xhr.responseText ? JSON.parse(xhr.responseText) : null
            } catch (e) {
                onError({ hint: "invalid JSON from Home Assistant", detail: String(e) })
                return
            }
            if (onSuccess) {
                onSuccess(result)
            }
        } else if (onError) {
            onError({ hint: "HTTP " + xhr.status, detail: xhr.responseText })
        }
    }
    xhr.open(method, baseUrl.replace(/\/+$/, "") + path)
    xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.send(body ? JSON.stringify(body) : undefined)
}

// GET /api/states -- full entity list with current state + attributes.
function getStates(baseUrl, token, onSuccess, onError) {
    request("GET", baseUrl, token, "/api/states", null, onSuccess, onError)
}

// POST /api/services/<domain>/<service> -- e.g. callService(..., "light",
// "toggle", { entity_id: "light.kitchen" }, ...)
function callService(baseUrl, token, domain, service, serviceData, onSuccess, onError) {
    request("POST", baseUrl, token, "/api/services/" + domain + "/" + service, serviceData, onSuccess, onError)
}

// POST /api/mobile_app/registrations -- registers this device as a
// mobile_app entry, same REST auth as the calls above. app_data.push_websocket_channel
// (any truthy value, verified against home-assistant/core's mobile_app/util.py
// supports_push()) is enough for HA to offer a notify.mobile_app_<device_name>
// service that delivers over our already-open WebSocket connection -- no
// push_url/local HTTP server needed. Returns onSuccess({webhook_id, ...}).
//
// os_version is REQUIRED despite being documented/schema'd as optional --
// verified against the user's real instance (HA 2026.9.2): omitting it makes
// mobile_app's own async_setup_entry() crash internally (it subscripts
// registration[ATTR_OS_VERSION] directly, no .get() fallback) *before*
// webhook_register() runs. The HTTP call still returns 201 with a webhook_id
// that looks valid, but that id is never actually wired up -- every
// subsequent /api/webhook/<id> call (register_sensor, push, ...) then
// silently 200s with an empty body forever (HA's generic webhook dispatcher
// returns that for any unknown webhook_id, to avoid leaking which ids
// exist). Confirmed by curl against the real instance: identical payload
// minus os_version -> permanently dead webhook_id; with a hardcoded
// os_version -> works immediately (device_tracker + notify + sensors all
// appeared). No real device-version string is read natively here (would
// need C++); a static value is fine since HA only displays it.
function registerMobileApp(baseUrl, token, deviceId, deviceName, onSuccess, onError) {
    request("POST", baseUrl, token, "/api/mobile_app/registrations", {
        device_id: deviceId,
        app_id: "harbour-hacontrol",
        app_name: "HA Control",
        app_version: "0.12",
        device_name: deviceName,
        manufacturer: "SailfishOS",
        model: "Phone",
        os_name: "SailfishOS",
        os_version: "5.1",
        supports_encryption: false,
        app_data: { push_websocket_channel: true }
    }, onSuccess, onError)
}

// POST /api/webhook/<webhook_id> -- the webhook_id itself is the secret, no
// Authorization header (verified against mobile_app/webhook.py's handle_webhook,
// which looks the config entry up purely by the URL's webhook_id). Used for
// register_sensor/update_sensor_states; body is always {type, data}.
function callWebhook(baseUrl, webhookId, type, data, onSuccess, onError) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) {
            return
        }
        if (xhr.status >= 200 && xhr.status < 300) {
            var result = null
            try {
                result = xhr.responseText ? JSON.parse(xhr.responseText) : null
            } catch (e) {
                onError({ hint: "invalid JSON from Home Assistant", detail: String(e) })
                return
            }
            if (onSuccess) {
                onSuccess(result)
            }
        } else if (onError) {
            onError({ hint: "HTTP " + xhr.status, detail: xhr.responseText })
        }
    }
    xhr.open("POST", baseUrl.replace(/\/+$/, "") + "/api/webhook/" + webhookId)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.send(JSON.stringify({ type: type, data: data }))
}

// Area (Room) assignment per entity_id isn't exposed by /api/states -- only
// via the WebSocket API's registries, or (used here to stay REST-only for
// Ausbaustufe 1) HA's /api/template endpoint with the area_name() Jinja
// helper. Verified against a real instance: HA's sandboxed Jinja blocks
// dict.update() ("SecurityError: ... is unsafe"), so this builds a list of
// [entity_id, area] pairs via the namespace()+list-concat idiom instead of a
// dict -- list concatenation reassignment isn't flagged as unsafe.
// Returns onSuccess([[entityId, areaName], ...]) -- entities without an
// assigned area are omitted.
function getAreaMap(baseUrl, token, onSuccess, onError) {
    var template = "{% set ns = namespace(items=[]) %}" +
        "{%- for s in states -%}" +
        "{%- set area = area_name(s.entity_id) -%}" +
        "{%- if area -%}" +
        "{%- set ns.items = ns.items + [[s.entity_id, area]] -%}" +
        "{%- endif -%}" +
        "{%- endfor -%}" +
        "{{ ns.items | tojson }}"
    request("POST", baseUrl, token, "/api/template", { template: template }, onSuccess, onError)
}
