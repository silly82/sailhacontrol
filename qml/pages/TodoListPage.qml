import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/HaApi.js" as HaApi
import "../lib/TodoUiState.js" as TodoUiState

// Items of one Home Assistant to-do list (opened from TodoListsPage.qml).
// Items are read via todo.get_items with a service response (REST
// ?return_response) and changed via todo.add_item / update_item /
// remove_item / remove_completed_items. Open items come first, completed
// ones follow under a "Completed" section header, which is collapsed by
// default (tap to expand; remembered per list for the app session).
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    // The todo entity's state == number of open items; kept current via
    // stateSource and shown in the page header.
    property string entityState: ""
    // RoomsView.qml's liveStateReceived (passed on by TodoListsPage.qml).
    // Every state change of this list (e.g. an item checked on another
    // device) triggers a debounced reload. May be null.
    property var stateSource: null

    readonly property bool configured: Credentials.baseUrl.length > 0 && Credentials.token.length > 0
    property bool loading: false
    property bool loadedOnce: false
    property string errorText: ""
    // Incremented per load; answers of an older load are dropped, so a slow
    // response can't overwrite a newer one.
    property int loadGeneration: 0
    property int completedCount: 0
    // Completed rows are hidden (height 0, invisible) unless expanded --
    // on long-lived lists they would otherwise bury the few open items.
    // Remembered per list for the app session in TodoUiState.js.
    // (Binding is replaced by the first tap; entityId is fixed per page.)
    property bool completedExpanded: TodoUiState.isCompletedExpanded(entityId)
    onCompletedExpandedChanged: {
        if (entityId.length > 0) {
            TodoUiState.setCompletedExpanded(entityId, completedExpanded)
        }
    }

    // Emitted when an item is checked while the completed block is
    // collapsed -- the section header briefly pulses, so the row vanishing
    // into the folded block reads as "moved", not "lost".
    signal completedWhileCollapsed()

    function countLabel(state) {
        var n = parseInt(state, 10)
        if (state === "unavailable") {
            return qsTr("Unavailable")
        }
        if (isNaN(n)) {
            return state
        }
        return n === 0 ? qsTr("Nothing open") : qsTr("%n open", "to-do items", n)
    }

    function errorHint(error) {
        if (error && error.code === "no_service_response") {
            return qsTr("Home Assistant did not return the list items. To-do lists need a newer Home Assistant version (2024.8 or later).")
        }
        return (error && error.hint) || qsTr("Unknown error")
    }

    function formatDue(due) {
        if (!due) {
            return ""
        }
        var d
        // Date only ("2026-11-06") -- parse as local date, new Date() would
        // treat it as UTC midnight and could show the previous day.
        var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(due)
        if (m) {
            d = new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10))
            return qsTr("Due %1").arg(Qt.formatDate(d, Qt.DefaultLocaleShortDate))
        }
        d = new Date(due)
        if (isNaN(d.getTime())) {
            return qsTr("Due %1").arg(due)
        }
        return qsTr("Due %1").arg(Qt.formatDateTime(d, Qt.DefaultLocaleShortDate))
    }

    // todo.update_item / remove_item accept the uid or the summary; the uid
    // is unambiguous, the summary is only a fallback for integrations that
    // don't report one.
    function itemKeyOf(item) {
        return (item.uid !== undefined && item.uid !== null && String(item.uid).length > 0)
            ? String(item.uid) : String(item.summary || "")
    }

    function makeRow(item) {
        var parts = []
        if (item.due) {
            parts.push(formatDue(item.due))
        }
        if (item.description) {
            parts.push(item.description)
        }
        return {
            itemKey: itemKeyOf(item),
            summary: String(item.summary || ""),
            status: item.status === "completed" ? "completed" : "needs_action",
            details: parts.join(" · ")
        }
    }

    function applyItems(items) {
        var open = []
        var done = []
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (!it || typeof it !== "object") {
                continue
            }
            var row = makeRow(it)
            if (row.status === "completed") {
                done.push(row)
            } else {
                open.push(row)
            }
        }
        completedCount = done.length
        // Our own changes come back as a state_changed event and trigger a
        // reload -- leave the model alone if nothing differs, so delegates
        // (and a running delete remorse on one of them) aren't recreated.
        var rows = open.concat(done)
        if (rows.length === itemsModel.count) {
            var same = true
            for (var r = 0; r < rows.length && same; r++) {
                var cur = itemsModel.get(r)
                same = cur.itemKey === rows[r].itemKey && cur.summary === rows[r].summary
                    && cur.status === rows[r].status && cur.details === rows[r].details
            }
            if (same) {
                return
            }
        }
        itemsModel.clear()
        for (var j = 0; j < open.length; j++) {
            itemsModel.append(open[j])
        }
        for (var k = 0; k < done.length; k++) {
            itemsModel.append(done[k])
        }
    }

    // silent: live/after-change reloads keep the current list visible and
    // don't show the BusyIndicator.
    function reload(silent) {
        if (!configured || entityId.length === 0) {
            return
        }
        loadGeneration += 1
        var generation = loadGeneration
        if (!silent) {
            loading = true
            requestTimeout.restart()
        }
        HaApi.callServiceWithResponse(Credentials.baseUrl, Credentials.token,
            "todo", "get_items", { entity_id: entityId, status: ["needs_action", "completed"] },
            function (response) {
                if (generation !== loadGeneration) {
                    return
                }
                requestTimeout.stop()
                loading = false
                var entry = response[entityId]
                if (!entry || typeof entry !== "object" || !Array.isArray(entry.items)) {
                    errorText = qsTr("Unexpected answer from Home Assistant.")
                    return
                }
                errorText = ""
                loadedOnce = true
                applyItems(entry.items)
            },
            function (error) {
                if (generation !== loadGeneration) {
                    return
                }
                requestTimeout.stop()
                loading = false
                errorText = errorHint(error)
            })
    }

    function indexOfKey(key) {
        for (var i = 0; i < itemsModel.count; i++) {
            if (itemsModel.get(i).itemKey === key) {
                return i
            }
        }
        return -1
    }

    // Moves the row to the end of the open block (needs_action) or the
    // start of the completed block, so the section grouping stays intact.
    function moveToStatus(key, status) {
        var from = indexOfKey(key)
        if (from < 0) {
            return
        }
        var oldStatus = itemsModel.get(from).status
        if (oldStatus === status) {
            return
        }
        itemsModel.setProperty(from, "status", status)
        var openCount = 0
        for (var i = 0; i < itemsModel.count; i++) {
            if (i !== from && itemsModel.get(i).status !== "completed") {
                openCount += 1
            }
        }
        // Target index after removing the row: open rows occupy
        // [0, openCount), the moved row goes right at that boundary.
        var to = openCount
        if (to !== from) {
            itemsModel.move(from, to, 1)
        }
        completedCount += status === "completed" ? 1 : -1
    }

    // Optimistic: the row moves immediately and moves back if HA refuses.
    function setItemStatus(key, status) {
        var oldIndex = indexOfKey(key)
        if (oldIndex < 0) {
            return
        }
        var oldStatus = itemsModel.get(oldIndex).status
        errorText = ""
        moveToStatus(key, status)
        if (status === "completed" && oldStatus !== "completed" && !completedExpanded) {
            completedWhileCollapsed()
        }
        HaApi.callService(Credentials.baseUrl, Credentials.token,
            "todo", "update_item", { entity_id: entityId, item: key, status: status },
            function () {},
            function (error) {
                moveToStatus(key, oldStatus)
                errorText = errorHint(error)
            })
    }

    function addItem(text) {
        var summary = text.trim()
        if (summary.length === 0) {
            return
        }
        errorText = ""
        HaApi.callService(Credentials.baseUrl, Credentials.token,
            "todo", "add_item", { entity_id: entityId, item: summary },
            function () { reload(true) },
            function (error) { errorText = errorHint(error) })
    }

    function renameItem(key, newSummary) {
        var summary = newSummary.trim()
        if (summary.length === 0) {
            return
        }
        errorText = ""
        HaApi.callService(Credentials.baseUrl, Credentials.token,
            "todo", "update_item", { entity_id: entityId, item: key, rename: summary },
            function () { reload(true) },
            function (error) { errorText = errorHint(error) })
    }

    function removeItem(key) {
        errorText = ""
        HaApi.callService(Credentials.baseUrl, Credentials.token,
            "todo", "remove_item", { entity_id: entityId, item: key },
            function () { reload(true) },
            function (error) {
                errorText = errorHint(error)
                reload(true)
            })
    }

    function removeCompleted() {
        errorText = ""
        HaApi.callService(Credentials.baseUrl, Credentials.token,
            "todo", "remove_completed_items", { entity_id: entityId },
            function () { reload(true) },
            function (error) {
                errorText = errorHint(error)
                reload(true)
            })
    }

    Timer {
        id: requestTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            loading = false
            errorText = qsTr("Home Assistant is not responding.")
        }
    }

    // Several state_changed events can arrive in a burst (e.g. "remove
    // completed" on another device) -- reload once after they settle.
    Timer {
        id: liveReloadDelay
        interval: 500
        repeat: false
        onTriggered: page.reload(true)
    }

    Connections {
        target: stateSource
        onLiveStateReceived: {
            if (changedEntityId !== page.entityId || !newState) {
                return
            }
            page.entityState = newState.state || ""
            liveReloadDelay.restart()
        }
    }

    Component.onCompleted: reload(false)
    onConfiguredChanged: if (!loadedOnce) reload(false)

    RemorsePopup {
        id: remorsePopup
    }

    ListModel {
        id: itemsModel
    }

    Component {
        id: renameDialogComponent

        Dialog {
            id: renameDialog

            property string itemKey
            property string summary

            canAccept: renameField.text.trim().length > 0
            onAccepted: page.renameItem(itemKey, renameField.text)

            Column {
                width: parent.width

                DialogHeader {
                    acceptText: qsTr("Rename")
                }

                TextField {
                    id: renameField
                    width: parent.width
                    label: qsTr("Name")
                    text: renameDialog.summary
                    focus: true
                    EnterKey.enabled: text.trim().length > 0
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: renameDialog.accept()
                }
            }
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: itemsModel

        PullDownMenu {
            MenuItem {
                text: qsTr("Remove completed")
                enabled: page.completedCount > 0
                onClicked: remorsePopup.execute(qsTr("Removing completed items"), function () {
                    page.removeCompleted()
                })
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.reload(false)
            }
        }

        header: Column {
            width: listView.width

            PageHeader {
                title: page.entityName
                description: page.countLabel(page.entityState)
            }

            TextField {
                id: addField
                width: parent.width
                enabled: page.configured
                label: qsTr("Add item")
                placeholderText: qsTr("Add item")
                EnterKey.enabled: text.trim().length > 0
                EnterKey.iconSource: "image://theme/icon-m-add"
                EnterKey.onClicked: {
                    page.addItem(text)
                    text = ""
                }
            }

            Label {
                visible: page.errorText.length > 0 && itemsModel.count > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: page.errorText
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        // Only the completed block gets a visible header; the open items
        // sit directly under the "Add item" field. The header (styled like
        // a SectionHeader) toggles the completed block, collapsed by default.
        section.property: "status"
        section.delegate: BackgroundItem {
            id: sectionItem
            readonly property bool isCompleted: section === "completed"
            width: listView.width
            height: isCompleted ? Theme.itemSizeSmall : 0
            visible: isCompleted
            enabled: isCompleted
            onClicked: page.completedExpanded = !page.completedExpanded

            Label {
                id: completedLabel
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: expandIcon.left
                    rightMargin: Theme.paddingSmall
                    verticalCenter: parent.verticalCenter
                }
                horizontalAlignment: Text.AlignRight
                truncationMode: TruncationMode.Fade
                text: qsTr("Completed (%1)").arg(page.completedCount)
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                transformOrigin: Item.Right
            }

            Icon {
                id: expandIcon
                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }
                source: "image://theme/icon-m-down"
                highlighted: true
                rotation: page.completedExpanded ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 150 } }
            }

            SequentialAnimation {
                id: pulseAnimation
                NumberAnimation { target: completedLabel; property: "scale"; to: 1.2; duration: 120; easing.type: Easing.OutQuad }
                NumberAnimation { target: completedLabel; property: "scale"; to: 1.0; duration: 240; easing.type: Easing.InQuad }
            }

            Connections {
                target: page
                onCompletedWhileCollapsed: if (sectionItem.isCompleted) pulseAnimation.restart()
            }
        }

        delegate: ListItem {
            id: delegateItem
            // Completed rows fold away like collapsed rooms in RoomsView.qml
            // (height 0 + invisible) -- the model and the open/completed
            // ordering stay untouched, so check/uncheck, remorse and live
            // reloads work the same in both states.
            readonly property bool rowVisible: model.status !== "completed" || page.completedExpanded
            width: listView.width
            contentHeight: rowVisible ? itemSwitch.height : 0
            visible: rowVisible
            menu: itemMenuComponent

            TextSwitch {
                id: itemSwitch
                automaticCheck: false
                checked: model.status === "completed"
                text: model.summary
                description: model.details
                // Same key for the remorse/rename closures -- the index can
                // point to a different row after a (live) reload.
                onClicked: page.setItemStatus(model.itemKey, checked ? "needs_action" : "completed")
                // The switch covers the whole row and would swallow the
                // ListItem's own press-and-hold.
                onPressAndHold: delegateItem.openMenu()
            }

            Component {
                id: itemMenuComponent
                ContextMenu {
                    MenuItem {
                        text: qsTr("Rename")
                        onClicked: pageStack.push(renameDialogComponent, {
                            itemKey: model.itemKey,
                            summary: model.summary
                        })
                    }
                    MenuItem {
                        text: qsTr("Delete")
                        onClicked: {
                            var key = model.itemKey
                            delegateItem.remorseDelete(function () { page.removeItem(key) })
                        }
                    }
                }
            }
        }

        ViewPlaceholder {
            flickable: listView
            verticalOffset: listView.headerItem ? listView.headerItem.height / 2 : 0
            enabled: !configured
            text: qsTr("Not configured yet")
            hintText: qsTr("Enter the Home Assistant URL and a long-lived access token in Settings first.")
        }
        ViewPlaceholder {
            flickable: listView
            verticalOffset: listView.headerItem ? listView.headerItem.height / 2 : 0
            enabled: configured && errorText.length > 0 && !loading && itemsModel.count === 0
            text: qsTr("Could not load the list")
            hintText: errorText
        }
        ViewPlaceholder {
            flickable: listView
            verticalOffset: listView.headerItem ? listView.headerItem.height / 2 : 0
            enabled: configured && loadedOnce && !loading && errorText.length === 0 && itemsModel.count === 0
            text: qsTr("Nothing on this list")
            hintText: qsTr("Add an item with the field above.")
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.loading
    }
}
