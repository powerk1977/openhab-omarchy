import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

// Shared panel body: hero, section chooser, body states and the item list.
// Mounted once inside the bar popup and once inside the pop-out FloatingWindow;
// both read the same Service.qml object, so toggles stay live-synced. Each
// surface owns its own cursor and expansion state.
//
// Layout is anchor-driven: the hero, separator and chooser sit at the top with
// their natural heights, and the body region fills whatever is left — a fixed
// height in the popup (the panel sizes the card from contentImplicitHeight) and
// the full window in the pop-out case, so the list grows with the window.
Item {
    id: root

    required property var oh
    property QtObject bar: null

    // The popup sizes its card to this inner width; the pop-out window is a
    // normal WM-resizable toplevel and just fills itself instead.
    property int preferredWidth: Style.space(420)

    // Host hook for the "Settings" button (and the "s" key path the host
    // intercepts itself). Summoning settings closes the popup first.
    property var settingsOpener: null

    signal popoutRequested()

    // Whether the host's pop-out window is currently open. Drives the header
    // pop-out action's icon (open the window vs close it) and tooltip.
    property bool popoutOpen: false

    // Colors fall back to the theme when there is no bar (the window case),
    // mirroring EntityRow's own fallbacks.
    readonly property color fg: bar ? bar.foreground : Color.foreground
    readonly property string family: bar ? bar.fontFamily : Style.font.family
    readonly property color dim: Qt.darker(fg, 1.4)
    readonly property color hoverFill: Style.hoverFillFor(fg, Color.accent)
    readonly property color selectedFill: Style.selectedFillFor(fg, Color.accent)

    readonly property bool serviceReady: oh !== null
    readonly property string phase: serviceReady ? oh.phase : "idle"
    readonly property int rowCount: serviceReady ? oh.rows.count : 0
    readonly property bool hasDevices: serviceReady && oh.itemCount > 0
    readonly property bool grouped: serviceReady && oh.groupByArea && rowCount > 0

    // Body states, mirrored from the original panel's per-state Columns.
    readonly property bool stateNotConfigured: !root.serviceReady || !root.oh.configured
    readonly property bool stateNoDevices: root.serviceReady && root.oh.configured && !root.hasDevices
    readonly property bool stateNothingPinned: root.serviceReady && root.oh.configured && root.hasDevices && root.rowCount === 0
    readonly property bool listShown: root.serviceReady && root.oh.configured && root.hasDevices && root.rowCount > 0

    readonly property var heroMeta: {
        if (!serviceReady)
            return "Service unavailable";
        if (!oh.configured)
            return "Not connected";
        switch (phase) {
        case "connected":
            return (oh.demoMode ? "Demo · " : "") + oh.itemCount + " items";
        case "connecting":
            return oh.lastError ? "Retrying" : "Connecting…";
        case "error":
            return "Disconnected";
        default:
            return "Idle";
        }
    }

    // The section chooser is Favorites-first; the service keeps the option
    // list in sync with the locations that actually exist. A stale saved
    // selection (location no longer listed) falls back to Favorites for the
    // trigger, so the dropdown never shows a blank value.
    readonly property var panelChoices: serviceReady ? (oh.panelChoices || []) : []
    readonly property string selectedView: {
        if (!root.grouped) return "";
        var sel = String(root.oh.panelSelection || "favorites");
        for (var i = 0; i < root.panelChoices.length; i++) {
            if (root.panelChoices[i].value === sel) return sel;
        }
        return "favorites";
    }
    readonly property bool chooserShown: root.grouped && root.panelChoices.length > 1

    // The host keycatcher suspends itself while the dropdown owns the keys.
    readonly property bool blockedKeys: chooser && chooser.popupOpen

    // Sizing for the popup card. The list is capped so the popup never grows
    // unbounded; the pop-out window overrides the region with full height.
    readonly property int listCap: Style.space(420)
    readonly property int listNaturalHeight: listShown
        ? Math.min(rowsColumn.implicitHeight, root.listCap) : 0
    readonly property int regionNaturalHeight: root.listShown
        ? root.listNaturalHeight
        : (root.stateNotConfigured ? notConfiguredBody.implicitHeight
            : root.stateNoDevices ? noDevicesBody.implicitHeight
            : root.stateNothingPinned ? nothingPinnedBody.implicitHeight
            : 0)

    readonly property int contentImplicitHeight: {
        var h = heroBand.implicitHeight
        h += Style.spacing.panelGap + sepBand.implicitHeight
        if (chooser.visible)
            h += Style.spacing.panelGap + chooser.implicitHeight
        h += Style.spacing.panelGap + root.regionNaturalHeight
        return h
    }

    // Cursor state, owned per surface.
    property int cursorIndex: 0
    property bool cursorActive: false
    property string expandedItemName: ""

    function resetCursor() {
        cursorIndex = 0;
        cursorActive = false;
        expandedItemName = "";
    }

    function isHeaderIndex(i) {
        var it = entityRepeater.itemAt(i);
        return it !== null && it.locationHeader;
    }

    // Park the cursor on the first entity row (headers are not actionable).
    function firstEntityIndex() {
        var n = entityRepeater.count;
        var idx = 0;
        while (idx < n && isHeaderIndex(idx)) idx++;
        return idx < n ? idx : -1;
    }

    // Wake the cursor. Keep a hovered/previous position when it is still a
    // valid entity row; otherwise park on the first entity row.
    function focusLand() {
        if (cursorIndex < 0 || cursorIndex >= entityRepeater.count
                || isHeaderIndex(cursorIndex)) {
            cursorIndex = firstEntityIndex();
        }
        cursorActive = true;
    }

    function moveCursor(delta) {
        var n = entityRepeater.count;
        if (n === 0 || delta === 0) return;
        var next = cursorIndex + delta;
        while (next >= 0 && next < n && isHeaderIndex(next)) next += delta;
        if (next < 0 || next >= n) return;
        cursorIndex = next;
    }

    function currentRow() {
        var items = entityRepeater.count;
        if (cursorIndex < 0 || cursorIndex >= items) return null;
        return entityRepeater.itemAt(cursorIndex);
    }

    function activateCursor() {
        var item = currentRow();
        if (item) item.activate();
    }

    function toggleRowExpansion(itemName, currentlyExpanded) {
        expandedItemName = currentlyExpanded ? "" : itemName;
        cursorIndex = 0;
    }

    // ---------- hero ----------
    PanelHero {
        id: heroBand
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        title: "openHAB"
        meta: root.heroMeta
        foreground: root.fg
        fontFamily: root.family
        iconOpacity: root.phase === "connected" ? 1.0 : 0.55

        iconComponent: OpenHabIcon {
            iconSize: Style.font.display
            color: root.phase === "error" ? Color.urgent : root.fg
        }

        trailingControl: Component {
            Row {
                spacing: Style.spacing.xs
                PanelActionButton {
                    iconText: "󰒓"                  // md-cog
                    tooltipText: "Settings"
                    foreground: Qt.darker(root.fg, 1.4)
                    fontFamily: root.family
                    onClicked: {
                        if (typeof root.settingsOpener === "function")
                            root.settingsOpener("connection")
                    }
                }
                PanelActionButton {
                    iconText: root.popoutOpen ? "󰖭" : "󰏌"      // md-window_close / md-open_in_new
                    tooltipText: root.popoutOpen ? "Close pop-out" : "Pop out"
                    foreground: Qt.darker(root.fg, 1.4)
                    fontFamily: root.family
                    onClicked: root.popoutRequested()
                }
            }
        }
    }

    PanelSeparator {
        id: sepBand
        anchors.top: heroBand.bottom
        anchors.topMargin: Style.spacing.panelGap
        anchors.left: parent.left
        anchors.right: parent.right
        foreground: root.fg
    }

    // ---------- section chooser ----------
    Dropdown {
        id: chooser
        anchors.top: sepBand.bottom
        anchors.topMargin: Style.spacing.panelGap
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.chooserShown
        label: "View"
        options: root.panelChoices
        value: root.selectedView
        foreground: root.fg
        fontFamily: root.family
        onChanged: function(value) { root.oh.setPanelSelection(value) }
    }

    // ---------- body region: list or state ----------
    Item {
        id: bodyRegion
        anchors.top: chooser.visible ? chooser.bottom : sepBand.bottom
        anchors.topMargin: Style.spacing.panelGap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        ScrollView {
            id: listScroller
            anchors.fill: parent
            visible: root.listShown
            implicitHeight: root.listNaturalHeight
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                id: rowsColumn
                width: listScroller.availableWidth
                spacing: Style.spacing.hairline

                Repeater {
                    id: entityRepeater
                    model: root.serviceReady ? root.oh.rows : null
                    delegate: EntityRow {
                        // Required-properties mode; ask for `index` explicitly or the
                        // cursor never matches a row.
                        required property int index

                        width: rowsColumn.width
                        service: root.oh
                        bar: root.bar
                        fill: root.hoverFill
                        currentFill: root.selectedFill
                        hasCursor: root.cursorActive && root.cursorIndex === index
                        expanded: root.expandedItemName === itemName
                        onCursorRequested: {
                            root.cursorActive = true;
                            root.cursorIndex = index;
                        }
                        onExpandToggled: {
                            root.toggleRowExpansion(itemName, expanded);
                        }
                    }
                }
            }
        }

        // Not configured / service down.
        Column {
            id: notConfiguredBody
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            visible: root.stateNotConfigured
            spacing: Style.spacing.xl

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: !root.serviceReady ? "The openHAB service did not start." : "Connect to your openHAB instance, or try the demo first."
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.family
                font.pixelSize: Style.font.bodySmall
            }

            Button {
                visible: root.serviceReady
                bordered: true
                text: "Open settings"
                foreground: root.fg
                fontFamily: root.family
                onClicked: {
                    if (typeof root.settingsOpener === "function")
                        root.settingsOpener("connection")
                }
            }
        }

        // Configured but holding nothing.
        Column {
            id: noDevicesBody
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            visible: root.stateNoDevices
            spacing: Style.spacing.xl

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: {
                    if (root.phase !== "connecting" && root.phase !== "error")
                        return "Not connected.";
                    var reason = root.oh.lastError || "Cannot reach openHAB.";
                    return root.oh.lastErrorKind === "credential" ? reason + " Open settings to connect." : reason;
                }
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.family
                font.pixelSize: Style.font.bodySmall
            }

            Row {
                spacing: Style.spacing.lg

                Button {
                    bordered: true
                    text: "Settings"
                    foreground: root.fg
                    fontFamily: root.family
                    onClicked: {
                        if (typeof root.settingsOpener === "function")
                            root.settingsOpener("connection")
                    }
                }

                Button {
                    visible: root.phase === "idle"
                    bordered: true
                    text: "Retry"
                    foreground: root.fg
                    fontFamily: root.family
                    onClicked: root.oh.retryConnection()
                }
            }
        }

        // Connected with items but nothing pinned yet.
        Column {
            id: nothingPinnedBody
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            visible: root.stateNothingPinned
            spacing: Style.spacing.xl

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "Nothing is pinned to the panel yet. "
                    + "Open settings to choose which lights appear here."
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.family
                font.pixelSize: Style.font.bodySmall
            }

            Button {
                bordered: true
                text: "Choose items"
                foreground: root.fg
                fontFamily: root.family
                onClicked: {
                    if (typeof root.settingsOpener === "function")
                        root.settingsOpener("items")
                }
            }
        }
    }
}