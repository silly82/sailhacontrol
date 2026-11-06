import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/HaApi.js" as HaApi

// Generic "pick one entity" list: loads all states, keeps the ones in
// `domains`, groups them by domain and offers a search field plus one
// optional default row on top (e.g. "Last used light", "None",
// "Automatic"). It stores nothing itself -- the caller connects to
// picked() and writes its own ConfigurationValues, so the same page serves
// both cover button slots (CoverSettingsPage.qml) and the weather entity
// (SensorsView.qml). An empty entityId means "the default row was chosen".
Page {
    id: page

    allowedOrientations: Orientation.All

    property string headerTitle
    property string description
    property var domains: []
    // Empty -> no default row.
    property string defaultLabel
    property string defaultDescription
    // Highlighted row; "" highlights the default row.
    property string currentId
    property string searchPlaceholder: qsTr("Search")
    property string noMatchesHint
    property string nothingHint

    signal picked(string entityId, string name, string domain)

    readonly property bool configured: Credentials.baseUrl.length > 0 && Credentials.token.length > 0
    property bool loading: false
    property bool loadedOnce: false
    property string errorText: ""
    // Full candidate list from the last getStates, already sorted; the
    // ListModel only holds the rows matching the current search text.
    property var allCandidates: []

    function domainLabel(domain) {
        switch (domain) {
        case "scene": return qsTr("Scenes")
        case "script": return qsTr("Scripts")
        case "light": return qsTr("Lights")
        case "switch": return qsTr("Switches")
        case "weather": return qsTr("Weather")
        }
        return domain
    }

    function select(entityId, name, domain) {
        page.picked(entityId, name, domain)
        pageStack.pop()
    }

    function buildCandidates(states) {
        var list = []
        for (var i = 0; i < states.length; i++) {
            var st = states[i]
            var domain = st.entity_id.split(".")[0]
            if (domains.indexOf(domain) < 0) {
                continue
            }
            list.push({
                entityId: st.entity_id,
                name: (st.attributes && st.attributes.friendly_name) || st.entity_id,
                domain: domain
            })
        }
        list.sort(function (a, b) {
            var d = domains.indexOf(a.domain) - domains.indexOf(b.domain)
            return d !== 0 ? d : a.name.localeCompare(b.name)
        })
        allCandidates = list
        applyFilter()
    }

    function applyFilter() {
        var needle = searchText.toLowerCase()
        candidatesModel.clear()
        for (var i = 0; i < allCandidates.length; i++) {
            var c = allCandidates[i]
            if (needle.length > 0
                    && c.name.toLowerCase().indexOf(needle) < 0
                    && c.entityId.toLowerCase().indexOf(needle) < 0) {
                continue
            }
            candidatesModel.append(c)
        }
    }

    function refresh() {
        if (!configured) {
            return
        }
        errorText = ""
        loading = true
        requestTimeout.restart()
        var profileId = Credentials.activeProfileId
        HaApi.getStates(Credentials.baseUrl, Credentials.token,
            function (states) {
                if (profileId !== Credentials.activeProfileId) return
                requestTimeout.stop()
                loading = false
                loadedOnce = true
                buildCandidates(states || [])
            },
            function (error) {
                if (profileId !== Credentials.activeProfileId) return
                requestTimeout.stop()
                loading = false
                errorText = error.hint || qsTr("Unknown error")
            })
    }

    property string searchText: ""
    onSearchTextChanged: filterDelay.restart()

    // Same limit as the sub-views: without it the BusyIndicator would spin
    // forever when Home Assistant is unreachable.
    Timer {
        id: requestTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            loading = false
            errorText = qsTr("Home Assistant is not responding.")
        }
    }
    // Rebuilding the model on every keystroke is cheap for a few hundred
    // rows, but a short delay keeps fast typing from doing it repeatedly.
    Timer {
        id: filterDelay
        interval: 200
        repeat: false
        onTriggered: applyFilter()
    }

    Component.onCompleted: refresh()
    onConfiguredChanged: if (!loadedOnce) refresh()

    ListModel {
        id: candidatesModel
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: candidatesModel

        PullDownMenu {
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.refresh()
            }
        }

        header: Column {
            width: listView.width

            PageHeader {
                title: page.headerTitle
            }

            Label {
                visible: text.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: page.description
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            ListItem {
                id: defaultItem
                visible: page.defaultLabel.length > 0
                width: parent.width
                contentHeight: visible ? Theme.itemSizeMedium : 0
                onClicked: page.select("", "", "")

                Column {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        text: page.defaultLabel
                        color: page.currentId.length === 0 || defaultItem.highlighted
                            ? Theme.highlightColor : Theme.primaryColor
                    }
                    Label {
                        visible: text.length > 0
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        text: page.defaultDescription
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                    }
                }
            }

            SearchField {
                width: parent.width
                placeholderText: page.searchPlaceholder
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onTextChanged: page.searchText = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        section.property: "domain"
        section.delegate: SectionHeader {
            text: page.domainLabel(section)
        }

        delegate: ListItem {
            id: delegateItem
            width: listView.width
            contentHeight: Theme.itemSizeSmall
            readonly property bool selected: model.entityId === page.currentId
            onClicked: page.select(model.entityId, model.name, model.domain)

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                truncationMode: TruncationMode.Fade
                text: model.name
                color: delegateItem.selected || delegateItem.highlighted
                    ? Theme.highlightColor : Theme.primaryColor
            }
        }

        ViewPlaceholder {
            flickable: listView
            // The list header (text, default row, search) is tall -- without
            // an offset the placeholder would sit on top of it.
            verticalOffset: listView.headerItem ? listView.headerItem.height + Theme.itemSizeSmall : 0
            enabled: !configured
            text: qsTr("Not configured yet")
            hintText: qsTr("Enter the Home Assistant URL and a long-lived access token in Settings first.")
        }
        ViewPlaceholder {
            flickable: listView
            verticalOffset: listView.headerItem ? listView.headerItem.height + Theme.itemSizeSmall : 0
            enabled: configured && errorText.length > 0 && !loading
            text: qsTr("No connection")
            hintText: errorText
        }
        ViewPlaceholder {
            flickable: listView
            verticalOffset: listView.headerItem ? listView.headerItem.height + Theme.itemSizeSmall : 0
            enabled: configured && loadedOnce && !loading && errorText.length === 0 && candidatesModel.count === 0
            text: page.searchText.length > 0 ? qsTr("No matches") : qsTr("Nothing to choose from")
            hintText: page.searchText.length > 0 ? page.noMatchesHint : page.nothingHint
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.loading
    }
}
