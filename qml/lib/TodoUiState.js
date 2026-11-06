.pragma library

// UI state of the to-do pages that should survive leaving and reopening
// TodoListPage.qml, but only for the running app session (no persistence).
// ".pragma library" = one shared instance per QML engine.

// entity_id -> true when the "Completed" block of that list is expanded.
// Missing key == collapsed (the default).
var completedExpanded = {}

function isCompletedExpanded(entityId) {
    return completedExpanded[entityId] === true
}

function setCompletedExpanded(entityId, expanded) {
    if (expanded) {
        completedExpanded[entityId] = true
    } else {
        delete completedExpanded[entityId]
    }
}
