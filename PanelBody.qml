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

    // Rotating home-automation sayings shown in the hero meta line while
    // connected — the same treatment as the bluetooth panel's hero status
    // line. Non-connected phases keep their plain status text.
    property int phraseIndex: 0
    readonly property var heroSayings: [
        "Running Scenes",
        "Connecting Hubs",
        "Dimming Lights",
        "Toggling Switches"
    ]
    readonly property bool rotatingSayings: root.serviceReady
        && root.oh.configured && root.phase === "connected"

    readonly property var heroMeta: {
        if (!serviceReady)
            return "Service unavailable";
        if (!oh.configured)
            return "Not connected";
        switch (phase) {
        case "connected":
            return (oh.demoMode ? "Demo · " : "")
                + root.heroSayings[root.phraseIndex % root.heroSayings.length];
        case "connecting":
            return oh.lastError ? "Retrying" : "Connecting…";
        case "error":
            return "Disconnected";
        default:
            return "Idle";
        }
    }

    // The items chooser is Favorites-first; the service keeps the option
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

    // Scene chips (when the server has Scene-tagged rules) sit between the
    // separator and the items chooser; the strip collapses entirely when none.
    readonly property bool sceneBandShown: root.serviceReady && root.oh && root.oh.hasScenes === true

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
        if (sceneBand.visible)
            h += Style.spacing.panelGap + sceneBand.implicitHeight
        if (sceneBand.visible)
            h += Style.spacing.panelGap + itemsDivider.implicitHeight
        if (chooser.visible)
            h += Style.spacing.panelGap + chooser.implicitHeight
        h += Style.spacing.panelGap + root.regionNaturalHeight
        return h
    }

    // Cursor state, owned per surface. The scene strip is index -1 of the
    // same cursor column: when cursorInScenes the strip owns the cursor and
    // Left/Right move between chips, Down lands on the first entity row.
    property int cursorIndex: 0
    property bool cursorActive: false
    property bool cursorInScenes: false
    property int sceneActiveIndex: 0
    property string expandedItemName: ""

    function resetCursor() {
        cursorIndex = 0;
        cursorActive = false;
        cursorInScenes = false;
        expandedItemName = "";
        clampSceneIndex();
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

    // Keyboard routing for both surfaces. The shared cursor walks a single
    // column: the scene strip (index -1) at the top, then the entity rows.
    function moveRequested(dx, dy) {
        if (dx === 0 && dy === 0) return;
        if (!root.cursorActive) {
            root.focusLand();
            return;
        }
        if (dy > 0) {
            if (root.cursorInScenes) {
                root.cursorInScenes = false;
                root.cursorIndex = root.firstEntityIndex();
            } else {
                root.moveCursor(1);
            }
            return;
        }
        if (dy < 0) {
            if (root.cursorInScenes) return;
            if (root.sceneBandShown && root.cursorIndex === root.firstEntityIndex()) {
                root.cursorInScenes = true;
                return;
            }
            root.moveCursor(-1);
            return;
        }
        // Horizontal only matters on the strip.
        if (root.cursorInScenes)
            root.nudgeActiveScene(dx);
    }

    // Move the chip selection by one, skipping disabled scenes and wrapping.
    function nudgeActiveScene(dx) {
        if (!root.sceneBandShown) return;
        var list = root.oh.scenes;
        var n = list.length;
        if (n === 0) return;
        var step = dx > 0 ? 1 : -1;
        var next = root.sceneActiveIndex;
        for (var i = 0; i < n; i++) {
            next += step;
            if (next < 0) next = n - 1;
            if (next >= n) next = 0;
            if (list[next].enabled) {
                root.sceneActiveIndex = next;
                return;
            }
        }
    }

    // Run whichever chip is selected (Enter when the strip owns the cursor).
    function runActiveScene() {
        if (!root.sceneBandShown) return;
        var list = root.oh.scenes;
        var index = Math.min(Math.max(root.sceneActiveIndex, 0), list.length - 1);
        root.oh.runScene(list[index].uid);
    }

    // When the scene list shrinks, keep the selected chip in range and drop
    // the strip cursor if there are no scenes left.
    function clampSceneIndex() {
        var n = root.oh && root.oh.scenes ? root.oh.scenes.length : 0;
        if (root.sceneActiveIndex >= n) root.sceneActiveIndex = Math.max(0, n - 1);
        if (!n) root.cursorInScenes = false;
    }

    // Mouse mirrors the cursor: hovering a chip selects it and moves the
    // shared cursor up onto the strip.
    function handleSceneHover(index) {
        root.sceneActiveIndex = index;
        root.cursorActive = true;
        root.cursorInScenes = true;
    }

    function handleSceneActivate(index) {
        root.sceneActiveIndex = index;
        root.runActiveScene();
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

    // Rotate the hero meta sayings with a fade-out/in, mirroring the
    // bluetooth panel's rotating hero status line. Timers in the common
    // namespace are fine: connected phase is what gates the rotation.
    Timer {
        id: phraseTimer
        interval: 2800
        running: root.rotatingSayings
        repeat: true
        onTriggered: phraseSwap.restart()
    }

    SequentialAnimation {
        id: phraseSwap
        PropertyAnimation {
            target: heroBand
            property: "metaOpacity"
            to: 0.0
            duration: 180
            easing.type: Easing.OutQuad
        }
        ScriptAction {
            script: root.phraseIndex = (root.phraseIndex + 1) % root.heroSayings.length
        }
        PropertyAnimation {
            target: heroBand
            property: "metaOpacity"
            to: 1.0
            duration: 260
            easing.type: Easing.InQuad
        }
    }

    Connections {
        target: root
        function onRotatingSayingsChanged() {
            if (!root.rotatingSayings) {
                phraseSwap.stop()
                heroBand.metaOpacity = 1.0
            }
        }
    }

    // ---------- scene chips ----------
    // Action-only strip: runs a scene, nothing stays selected. Sits flush with
    // the left edge so it shares the Items dropdown's line; collapses entirely
    // when the server has no scenes.
    SceneStrip {
        id: sceneBand
        anchors.top: sepBand.bottom
        anchors.topMargin: Style.spacing.panelGap
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.sceneBandShown
        oh: root.oh
        bar: root.bar
        foreground: root.fg
        foregroundDim: root.dim
        fontFamily: root.family
        activeIndex: root.sceneActiveIndex
        cursorOn: root.cursorInScenes
        onChipHovered: function(index) { root.handleSceneHover(index) }
        onChipActivated: function(index) { root.handleSceneActivate(index) }
    }

    // Keep the strip cursor in range when the scene list mutates.
    Connections {
        target: root.oh
        ignoreUnknownSignals: true
        function onSceneRevisionChanged() { root.clampSceneIndex() }
    }

    // Section divider between the scenes band and the items chooser, the
    // same full-width treatment the bluetooth panel uses between sections.
    PanelSeparator {
        id: itemsDivider
        anchors.top: sceneBand.bottom
        anchors.topMargin: Style.spacing.panelGap
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.sceneBandShown
        foreground: root.fg
    }

    // ---------- items chooser ----------
    Dropdown {
        id: chooser
        anchors.top: itemsDivider.visible ? itemsDivider.bottom : sepBand.bottom
        anchors.topMargin: Style.spacing.panelGap
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.chooserShown
        label: "Items"
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
                            root.cursorInScenes = false;
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