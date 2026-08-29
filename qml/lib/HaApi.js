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
