.pragma library

// Theme icon per Home Assistant entity, shared by the room list and the
// detail pages. Only monochrome icon-m-* theme names; callers tint them with
// "image://theme/<name>?" + a Theme color. (icon-m-play and icon-m-dot have
// a filled circle background -- not used as status icons.)
function iconFor(domain, entityId, unit) {
    switch (domain) {
    case "light": return "icon-m-day"
    case "switch":
    case "input_boolean": return "icon-m-reboot"
    case "fan": return "icon-m-sync"
    case "cover": return "icon-m-home"
    case "climate": return "icon-m-levels"
    case "media_player": return "icon-m-speaker"
    case "scene": return "icon-m-wizard"
    case "script": return "icon-m-simple-play"
    case "button":
    case "input_button": return "icon-m-gesture"
    case "lock": return "icon-m-device-lock"
    case "camera": return "icon-m-camera"
    case "alarm_control_panel": return "icon-m-remote-security"
    case "vacuum": return "icon-m-toy"
    case "weather": return "icon-m-day"
    case "todo": return "icon-m-events"
    case "sensor":
        if (String(entityId || "").indexOf("battery") >= 0) {
            return "icon-m-battery"
        }
        if (["W", "kW", "Wh", "kWh"].indexOf(String(unit || "")) >= 0) {
            return "icon-m-charging"
        }
        return "icon-m-diagnostic"
    default: return "icon-m-other"
    }
}
