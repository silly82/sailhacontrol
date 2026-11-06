.pragma library

// One domain -> theme icon mapping for the whole app (room list rows and the
// detail pages' status block), so both always show the same symbol.
// Only monochrome icon-m-* names that exist in the stock Sailfish theme
// (checked against /usr/share/themes/sailfish-default/silica/z1.0/
// icons-monochrome on the 5.1 emulator), so `?<color>` tinting works.
// Chosen by looking at the actual images, not by name:
//   light                  icon-m-day             (sun)
//   switch, input_boolean  icon-m-reboot          (power symbol)
//   fan                    icon-m-sync            (rotating arrows)
//   cover                  icon-m-home
//   climate                icon-m-levels          (no thermometer in the theme)
//   media_player           icon-m-speaker
//   scene                  icon-m-wizard          (magic wand)
//   script                 icon-m-simple-play
//   button, input_button   icon-m-gesture         (tapping finger)
//   lock                   icon-m-device-lock
//   camera                 icon-m-camera
//   alarm_control_panel    icon-m-remote-security (lock with radio waves)
//   vacuum                 icon-m-toy             (small robot car)
//   weather                icon-m-day
//   todo                   icon-m-events          (list)
//   sensor: battery        icon-m-battery
//   sensor: W/kW/Wh/kWh    icon-m-charging        (lightning bolt)
//   sensor: other          icon-m-diagnostic      (graph)
//   anything else          icon-m-other
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
        if ((entityId || "").indexOf("battery") >= 0) {
            return "icon-m-battery"
        }
        if (unit === "W" || unit === "kW" || unit === "Wh" || unit === "kWh") {
            return "icon-m-charging"
        }
        return "icon-m-diagnostic"
    default: return "icon-m-other"
    }
}
