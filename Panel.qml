import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Bar button plus popup panel. Owns the keyboard cursor; the service owns the
// items and the connection.
Panel {
    id: root
    moduleName: "io.github.powerk1977.openhab"
    ipcTarget: "io.github.powerk1977.openhab"
    // We own the target's single IpcHandler, so the methods below can sit
    // alongside the base open/close/toggle.
    manageIpc: false

    readonly property var oh: bar && bar.shell ? bar.shell.serviceFor("io.github.powerk1977.openhab") : null
    readonly property bool serviceReady: oh !== null
    readonly property string phase: serviceReady ? oh.phase : "idle"

    // One cursor for keyboard and mouse, per the CursorSurface contract.
    // Dormant until a key is pressed.
    property int cursorIndex: 0
    property bool cursorActive: false
    property string expandedItemName: ""

    readonly property int rowCount: serviceReady ? oh.rows.count : 0
    readonly property bool hasDevices: serviceReady && oh.itemCount > 0

    // Quickshell's `Qt` facade has no `fontMetrics`, so the estimate below
    // measures chips with a real FontMetrics element in their exact font.
    // Prefer the REAL laid-out strip width (tabGroup.implicitWidth) once the
    // panel has rendered; the estimate is only a pre-layout fallback.
    property int naturalStripWidth: Style.space(380)

    function estimateStripWidth() {
        var sum = 0;
        for (var i = 0; i < root.oh.tabs.length; i++) {
            var title = String(root.oh.tabs[i].title || "");
            sum += Math.ceil(tabMeasure.advanceWidth(title))
                + Style.spacing.controlPaddingX * 2
                + 2;
        }
        sum += (root.oh.tabs.length - 1) * Style.spacing.md;
        return sum;
    }

    function recomputeStripWidth() {
        if (!root.serviceReady || !root.oh.tabs || root.oh.tabs.length < 2
                || !root.hasDevices) {
            root.naturalStripWidth = Style.space(380);
            return;
        }
        // `tabGroup` is an id, not a root member – reference it bare.
        var w = tabGroup.implicitWidth;
        if (w <= 0)
            w = root.estimateStripWidth();
        root.naturalStripWidth = Math.max(Style.space(380), w + Style.space(16));
    }

    onOpenedChanged: if (!opened) {
        expandedItemName = "";
        cursorActive = false;
        cursorIndex = 0;
    }

    function toggleRowExpansion(itemName, currentlyExpanded) {
        expandedItemName = currentlyExpanded ? "" : itemName;
        cursorIndex = 0;
    }

    function moveCursor(delta) {
        if (rowCount === 0 || delta === 0)
            return;
        var next = Math.max(0, Math.min(rowCount - 1, cursorIndex + delta));
        if (next !== cursorIndex)
            cursorIndex = next;
    }

    function switchPanel(direction) {
        expandedItemName = "";
        cursorIndex = 0;
        return root.switchPanelFrom(direction);
    }

    // Left/right within the panel: area tabs when there are any, otherwise
    // defer to the shell-level panel switch.
    function switchTab(delta) {
        if (!root.serviceReady || !root.oh.tabs
            || root.oh.tabs.length < 2)
            return false;
        var tabs = root.oh.tabs;
        var current = root.oh.effectiveTab;
        var index = 0;
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].id === current) { index = i; break; }
        }
        var next = Math.max(0, Math.min(tabs.length - 1, index + delta));
        if (next !== index) {
            root.oh.setActiveTab(tabs[next].id);
            root.expandedItemName = "";
            root.cursorActive = false;
            root.cursorIndex = 0;
        }
        return true;
    }

    function currentRow() {
        var items = entityRepeater.count;
        if (cursorIndex < 0 || cursorIndex >= items)
            return null;
        return entityRepeater.itemAt(cursorIndex);
    }

    function activateCursor() {
        var item = currentRow();
        if (item)
            item.activate();
    }

    // A separate plugin surface, so it goes through the shell. The popup closes
    // first because the overlay takes exclusive keyboard focus.
    function openSettings(tab) {
        if (!bar || !bar.shell || typeof bar.shell.summon !== "function")
            return;
        close();
        bar.shell.summon("io.github.powerk1977.openhab", JSON.stringify({
            tab: tab || "connection"
        }));
    }

    readonly property color iconColor: {
        var base = bar ? bar.barForeground : Color.foreground;
        return phase === "connected" ? base : Qt.darker(base, 1.5);
    }

    // The bar relies on `button.active` for the text-glyph path; a custom
    // iconComponent is not tinted, so the icon picks urgent itself like the
    // built-in's `activeColor` binding.
    readonly property color barIconColor: phase === "error" ? (bar ? bar.urgent : Color.urgent) : iconColor

    readonly property color fg: bar ? bar.foreground : Color.foreground
    readonly property string family: bar ? bar.fontFamily : Style.font.family
    readonly property color dim: Qt.darker(fg, 1.4)
    readonly property color hoverFill: Style.hoverFillFor(fg, Color.accent)
    readonly property color selectedFill: Style.selectedFillFor(fg, Color.accent)

    readonly property string heroMeta: {
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

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    IpcHandler {
        target: "io.github.powerk1977.openhab"

        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
        function show(): void {
            root.open();
        }
        function hide(): void {
            root.close();
        }
        function toggle(): void {
            root.toggle();
        }

        function status(): string {
            if (!root.serviceReady)
                return "service: UNREACHABLE";
            root.recomputeStripWidth();
            var groupW = root.serviceReady && root.oh.tabs.length > 1
                ? Math.round(tabGroup.implicitWidth) : 0;
            return "phase=" + root.oh.phase + " configured=" + root.oh.configured + " demo=" + root.oh.demoMode + " items=" + root.oh.itemCount + " rows=" + root.oh.rows.count + " tabs=" + root.oh.tabs.length + " groupW=" + groupW + " stripW=" + root.naturalStripWidth + (root.oh.lastError ? " error=" + root.oh.lastError : "");
        }

        function refresh(): void {
            if (root.serviceReady)
                root.oh.refresh();
        }

        //   bind = SUPER, L, exec, omarchy-shell openhab toggleItem LivingRoom_Ceiling_Dimmer
        function toggleItem(itemName: string): string {
            if (!root.serviceReady)
                return "service unavailable";
            if (!root.oh.entityStore.item(itemName))
                return "unknown item " + itemName;
            return root.oh.toggleItem(itemName) ? "ok" : (root.oh.lastError || "item isn't toggleable");
        }

        //   bind = SUPER, T, exec, omarchy-shell openhab setBrightness LivingRoom_Ceiling_Dimmer 40
        function setBrightness(itemName: string, percent: int): string {
            if (!root.serviceReady)
                return "service unavailable";
            if (!root.oh.entityStore.item(itemName))
                return "unknown item " + itemName;
            return root.oh.setBrightness(itemName, percent) ? "ok" : (root.oh.lastError || "item isn't dimmable");
        }

        // Two no-arg calls, not one taking a tab: IpcHandler makes declared
        // arguments mandatory, so `settings` alone would refuse to run.
        function settings(): void {
            root.openSettings("connection");
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconComponent: Component {
            OpenHabIcon {
                anchors.centerIn: parent
                iconSize: Style.bar.iconCanvas
                color: root.barIconColor
            }
        }
        foreground: root.barIconColor
        active: root.phase === "error"
        onPressed: root.toggle()
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        // naturalStripWidth is the needed *inner* width; `fittedContentWidth`
        // only compensates for height, so reserve the card's horizontal
        // insets (padding + borders) here or the strip clips behind them.
        contentWidth: panel.fittedContentWidth(root.naturalStripWidth
            + panel.padding * 2 + Border.left(panel.borderSpec) + Border.right(panel.borderSpec))
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        // Re-measure the tab strip each time the popup opens so the panel
        // stays wide enough for every chip (measured after it has laid out).
        onOpenChanged: if (open) root.recomputeStripWidth()

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }
            onMoveRequested: function (dx, dy) {
                // Sideways moves tabs (when there are tabs to move between);
                // the first key press only wakes the cursor.
                if (dx !== 0 && root.switchTab(dx > 0 ? 1 : -1))
                    return;
                if (!root.cursorActive) {
                    root.cursorActive = true;
                    return;
                }
                if (dy !== 0)
                    root.moveCursor(dy);
            }
            onActivateRequested: if (root.cursorActive)
                root.activateCursor()
            onTextKey: function (key) {
                var lower = String(key).toLowerCase();
                if (lower === "r" && root.serviceReady)
                    root.oh.refresh();
                else if (lower === "e" && root.cursorActive) {
                    var item = currentRow();
                    if (item && !item.locationHeader && item.expandable) {
                        root.toggleRowExpansion(item.itemName, item.expanded);
                    }
                } else if (lower === "s")
                    root.openSettings("connection");
            }

            Column {
                id: column
                anchors.fill: parent
                spacing: Style.spacing.panelGap

                // ---------- hero: mark · title · status ----------
                PanelHero {
                    width: parent.width
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
                        PanelActionButton {
                            iconText: "󰒓"                  // md-cog
                            tooltipText: "Settings"
                            foreground: Qt.darker(root.fg, 1.4)
                            fontFamily: root.family
                            onClicked: root.openSettings("connection")
                        }
                    }
                }

                PanelSeparator {
                    width: parent.width
                    foreground: root.fg
                }

                // ---------- area tabs ----------
                // ButtonGroup is a Row and does not wrap, so it scrolls instead
                // of pushing chips off the panel edge.
                // Measures chips in the same font they use, so the panel can
                // grow to show every tab without a layout race.
                FontMetrics {
                    id: tabMeasure
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                }

ScrollView {
                        width: parent.width
                        visible: root.serviceReady && root.oh.tabs.length > 1
                            && root.hasDevices
                        implicitHeight: tabGroup.implicitHeight
                        clip: true
// Grow the panel to fit the whole strip when possible;
                        // where the screen cannot, keep the strip scrollable so
                        // no chip is ever unreachable behind the clip.
                        contentWidth: Math.max(width, root.naturalStripWidth)
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                    ButtonGroup {
                        id: tabGroup
                        // The panel owns the cursor, so this is not its own Tab stop.
                        focusable: false
                        foreground: root.fg
                        fontFamily: root.family
                        fontSize: Style.font.caption
                        options: root.serviceReady ? root.oh.tabs.map(function(tab) {
                            return { value: tab.id, label: tab.title };
                        }) : []
                        value: root.serviceReady ? root.oh.effectiveTab : "favorites"
                        onChanged: function(value) {
                            if (!root.serviceReady) return;
                            root.oh.setActiveTab(value);
                            root.cursorIndex = 0;
                            root.cursorActive = false;
                            root.expandedItemName = "";
                        }
                        // Track the real strip width after layout so the panel
                        // always fits every chip exactly.
                        onImplicitWidthChanged: root.recomputeStripWidth()
                    }
                }

                // ---------- body ----------
                Column {
                    width: parent.width
                    visible: !root.serviceReady || !root.oh.configured
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
                        onClicked: root.openSettings("connection")
                    }
                }

                // Configured but holding nothing.
                Column {
                    width: parent.width
                    visible: root.serviceReady && root.oh.configured && !root.hasDevices
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
                            onClicked: root.openSettings("connection")
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
                    width: parent.width
                    visible: root.serviceReady && root.oh.configured
                        && root.hasDevices && root.rowCount === 0
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
                        onClicked: root.openSettings("items")
                    }
                }

                ScrollView {
                    id: listScroller
                    visible: root.serviceReady && root.hasDevices && root.rowCount > 0
                    width: parent.width
                    implicitHeight: Math.min(rowsColumn.implicitHeight, Style.space(420))
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
            }
        }
    }
}
