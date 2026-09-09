import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Connection.js" as Connection

// Connection credentials and demo mode.
//
// Summoned by the shell, not by IPC: the bar widget already owns the
// "io.github.powerk1977.openhab" target and a target routes to one handler.
//   omarchy-shell shell summon openhab '{"tab":"connection"}'
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property string tab: "connection"

  // Local until Connect, so a half-typed URL never reaches the bridge.
  property string urlDraft: ""
  property string localUrlDraft: ""
  // Required whenever localUrlDraft is non-empty: the local URL is only ever
  // tried on this Wi-Fi network. See bin/oh-bridge's current_wifi_ssid.
  property string trustedNetworkDraft: ""
  // Collapsed unless a local URL is already saved: most people never need
  // this field.
  property bool localUrlExpanded: false
  // Suggestion only, for the trusted-network field — read-only, not a
  // security decision. The bridge determines the actual network in Python
  // before ever using a local URL.
  property string detectedWifiSsid: ""
  property string tokenDraft: ""
  property string userDraft: ""
  property string passwordDraft: ""

  // Item picker state. Search is debounced so a burst of keystrokes costs one
  // pass over the items; the list rebuild is throttled separately because
  // live state changes tick stateRevision on every row update.
  property string query: ""
  property string appliedQuery: ""
  property string filterChip: "all"

  property Timer queryDebounce: Timer {
    interval: 120
    onTriggered: root.appliedQuery = root.query
  }

  onQueryChanged: queryDebounce.restart()

  property int shownRevision: 0
  readonly property int liveRevision: root.service ? root.service.stateRevision : 0

  onLiveRevisionChanged: if (!revisionThrottle.running) revisionThrottle.start()

  property Timer revisionThrottle: Timer {
    interval: 400
    onTriggered: root.shownRevision = root.liveRevision
  }

  readonly property var typeFilters: [
    { value: "all", label: "All" },
    { value: "Switch", label: "Switch" },
    { value: "Dimmer", label: "Dimmer" },
    { value: "Color", label: "Color" }
  ]

  Process {
    id: wifiSsidProbe
    // --rescan no: only what NetworkManager already knows about the active
    // connection is needed here.
    command: ["nmcli", "-t", "-f", "active,ssid", "dev", "wifi", "list",
              "--rescan", "no"]
    stdout: SplitParser {
      onRead: function(value) {
        var ssid = Connection.parseNmcliActiveSsid(value)
        if (ssid) root.detectedWifiSsid = ssid
      }
    }
  }

  readonly property string family: Style.font.menuFamily
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property var borderSpec: Border.surfaceSpec(
    "menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  function open(payloadJson) {
    root.opened = true
    root.resetDrafts()
    try {
      var payload = payloadJson ? JSON.parse(payloadJson) : {}
      if (payload.tab === "items" || payload.tab === "connection") {
        root.tab = payload.tab
      }
    } catch (e) {
      // Not worth refusing to open over.
    }
    // Fresh view each time to the picker opens.
    root.query = ""
    root.appliedQuery = ""
    root.filterChip = "all"
    // Fresh on every open: the answer can change between sessions, and a
    // stale one from an old network would suggest the wrong name.
    root.detectedWifiSsid = ""
    if (!wifiSsidProbe.running) wifiSsidProbe.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.powerk1977.openhab")
    }
  }

  function resetDrafts() {
    if (!service) return
    root.urlDraft = service.baseUrl
    root.localUrlDraft = service.localUrl
    root.trustedNetworkDraft = service.trustedNetwork
    root.localUrlExpanded = service.localUrl.length > 0
    // The stored credential never comes back to screen; blank means "keep it".
    root.userDraft = ""
    root.passwordDraft = ""
    root.tokenDraft = ""
  }

  function applyConnection() {
    if (!service) return
    if (service.applyConnection(root.urlDraft.trim(), root.localUrlDraft.trim(),
                                root.trustedNetworkDraft.trim(), root.userDraft,
                                root.passwordDraft, root.tokenDraft, false)) {
      root.userDraft = ""
      root.passwordDraft = ""
      root.tokenDraft = ""
    }
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "openhab-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      readonly property int preferredWidth:
        root.tab === "items" ? Style.space(940) : Style.space(620)
      readonly property int preferredHeight:
        root.tab === "items" ? Style.space(620) : Style.space(560)
      width: Math.min(card.preferredWidth, window.width - Style.gapsOut * 2)
      height: Math.min(card.preferredHeight, window.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        onCloseRequested: root.dismiss()

        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          implicitHeight: heading.implicitHeight
          height: implicitHeight

          Text {
            textFormat: Text.PlainText
            id: heading
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "openHAB settings"
            color: root.foreground
            font.family: root.family
            font.pixelSize: Style.font.title
            font.weight: Font.Medium
          }

          ButtonGroup {
            id: tabRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
            fontFamily: root.family
            fontSize: Style.font.caption
            options: [{ value: "connection", label: "Connection" },
                      { value: "items", label: "Items" }]
            value: root.tab
            onChanged: function(value) { root.tab = value }
          }
        }

        PanelSeparator {
          id: rule
          anchors { top: header.bottom; left: parent.left; right: parent.right }
          anchors.topMargin: Style.space(12)
        }

        Item {
          id: body
          anchors {
            top: rule.bottom; bottom: parent.bottom
            left: parent.left; right: parent.right
          }
          anchors.topMargin: Style.space(14)

          Flickable {
            id: connectionFlick
            anchors.fill: parent
            visible: root.tab === "connection"
            clip: true
            contentWidth: width
            contentHeight: connectionColumn.height
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: connectionColumn
              width: connectionFlick.width
              spacing: Style.spacing.xxxl

              Column {
                width: connectionColumn.width
                spacing: Style.spacing.sm

                Text {
                  textFormat: Text.PlainText
                  text: "openHAB URL"
                  color: Color.muted
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                }

                TextField {
                  width: connectionColumn.width
                  text: root.urlDraft
                  placeholderText: "http://192.168.1.50:8080"
                  onTextChanged: root.urlDraft = text
                }

                Text {
                  textFormat: Text.PlainText
                  width: connectionColumn.width
                  visible: root.urlDraft.trim().toLowerCase().indexOf("http://") === 0
                  text: "Warning: this URL sends your access token without transport encryption. Use HTTPS unless this is a trusted local network."
                  color: Color.muted
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              Column {
                width: connectionColumn.width
                spacing: Style.spacing.sm

                Toggle {
                  width: connectionColumn.width
                  label: "Local network URL"
                  description: "Try a LAN address first, e.g. your instance's local IP, before falling back to the URL above. Uses the same access token."
                  checked: root.localUrlExpanded
                  foreground: root.foreground
                  fontFamily: root.family
                  onClicked: {
                    root.localUrlExpanded = !root.localUrlExpanded
                    // Collapsing means "no local URL" — a hidden stale draft
                    // would otherwise still reach applyConnection.
                    if (!root.localUrlExpanded) {
                      root.localUrlDraft = ""
                      root.trustedNetworkDraft = ""
                    }
                  }
                }

                TextField {
                  visible: root.localUrlExpanded
                  width: connectionColumn.width
                  text: root.localUrlDraft
                  placeholderText: "http://192.168.1.50:8080"
                  onTextChanged: root.localUrlDraft = text
                }

                Text {
                  textFormat: Text.PlainText
                  width: connectionColumn.width
                  visible: root.localUrlExpanded
                    && root.localUrlDraft.trim().toLowerCase().indexOf("http://") === 0
                  text: "Warning: this URL sends your access token without transport encryption. Use HTTPS unless this is a trusted local network."
                  color: Color.muted
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.localUrlExpanded
                  text: "Trusted Wi-Fi network name(s)"
                  color: Color.muted
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                }

                TextField {
                  visible: root.localUrlExpanded
                  width: connectionColumn.width
                  text: root.trustedNetworkDraft
                  placeholderText: "Home, Home 5G"
                  onTextChanged: root.trustedNetworkDraft = text
                }

                // A suggestion, not an autofill.
                Row {
                  visible: root.localUrlExpanded
                    && root.trustedNetworkDraft.trim().length === 0
                    && root.detectedWifiSsid.length > 0
                  spacing: Style.spacing.sm

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Currently on “" + root.detectedWifiSsid + "”."
                    color: Color.muted
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                  }

                  Button {
                    anchors.verticalCenter: parent.verticalCenter
                    bordered: true
                    text: "Use this"
                    foreground: root.foreground
                    fontFamily: root.family
                    onClicked: root.trustedNetworkDraft = root.detectedWifiSsid
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: connectionColumn.width
                  visible: root.localUrlExpanded
                  text: "Required. Comma-separated if your router has more than one. The local URL is only ever tried while connected to one of these — never on any other network, so the token can't be sent to whatever happens to answer at that address elsewhere."
                  color: Color.muted
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              Column {
                width: connectionColumn.width
                spacing: Style.spacing.sm

                Column {
                  width: connectionColumn.width
                  spacing: Style.spacing.sm

                  Text {
                    textFormat: Text.PlainText
                    text: "Credentials"
                    color: Color.muted
                    font.family: root.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  TextField {
                    width: connectionColumn.width
                    text: root.userDraft
                    placeholderText: "openHAB username"
                    onTextChanged: root.userDraft = text
                  }

                  TextField {
                    width: connectionColumn.width
                    text: root.passwordDraft
                    password: true
                    placeholderText: "openHAB password"
                    onTextChanged: root.passwordDraft = text
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: connectionColumn.width
                  text: "or"
                  color: Color.muted
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                }

                Column {
                  width: connectionColumn.width
                  spacing: Style.spacing.sm

                  Text {
                    textFormat: Text.PlainText
                    text: "Access token"
                    color: Color.muted
                    font.family: root.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  TextField {
                    width: connectionColumn.width
                    text: root.tokenDraft
                    password: true
                    placeholderText: "Paste your openHAB API token"
                    onTextChanged: root.tokenDraft = text
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: connectionColumn.width
                    text: "Use an API token (recommended, starts with oh.) or your MainUI username/password — e.g. when openHAB sits behind a proxy. \"Bearer \" and stray quotes/spaces are cleaned up automatically. Fill one or the other; if both, the token wins. Leave blank to keep the stored credential."
                    color: Color.muted
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: connectionColumn.width
                    text: root.service && root.service.configured && !root.service.demoMode
                      && root.service.storedCredentialForm
                      ? (root.service.storedCredentialForm === "userpass"
                         ? "Stored: username + password"
                         : "Stored: access token")
                      : ""
                    visible: text.length > 0
                    color: Color.muted
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Row {
                spacing: Style.spacing.xl

                Button {
                  bordered: true   // Ui/Button is flat otherwise, reading as a label
                  text: "Connect"
                  foreground: root.foreground
                  fontFamily: root.family
                  onClicked: root.applyConnection()
                }

                Button {
                  visible: root.service && root.service.configured
                    && !root.service.demoMode && !root.service.credentialBusy
                  bordered: true
                  text: "Remove"
                  opacity: (root.service && root.service.configured
                            && !root.service.credentialBusy) ? 1.0 : 0.45
                  foreground: root.foreground
                  fontFamily: root.family
                  onClicked: {
                    if (!root.service || !root.service.configured) return
                    root.service.removeConnection()
                    root.resetDrafts()
                  }
                }
              }

              PanelSeparator { width: connectionColumn.width }

              Toggle {
                width: connectionColumn.width
                label: "Demo mode"
                description: "A fake house, so you can try the panel without an instance."
                checked: root.service ? root.service.demoMode : false
                foreground: root.foreground
                fontFamily: root.family
                onClicked: if (root.service) root.service.setDemoMode(!root.service.demoMode)
              }

              // From the live connection, not a probe.
              Row {
                spacing: Style.spacing.lg

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(8); height: width; radius: width / 2
                  color: !root.service ? Color.muted
                       : root.service.phase === "connected" ? "#4caf50"
                       : root.service.phase === "error" ? Color.urgent
                       : Color.muted
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: connectionColumn.width - Style.space(24)
                  text: {
                    if (!root.service) return "Service unavailable"
                    if (!root.service.configured) return "Not connected"
                    switch (root.service.phase) {
                    case "connected":
                      return (root.service.demoMode ? "Demo running · "
                        : root.service.usingLocal ? "Connected (local network) · "
                        : "Connected · ")
                        + root.service.itemCount + " items"
                    case "connecting": return root.service.lastError
                      ? "Connecting… · " + root.service.lastError
                      : "Connecting…"
                    case "error": return root.service.lastError || "Connection failed"
                    default: return root.service.lastError || "Idle"
                    }
                  }
                  color: Color.muted
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          Item {
            id: picker
            anchors.fill: parent
            visible: root.tab === "items"

            // Both lists rebuild when the throttled state revision ticks
            // (live updates), and immediately when the user types, changes a
            // filter, or stars something. `favorites` is read at binding scope
            // so a star flips its state in both columns without waiting for
            // the throttle; `shownRevision` is read at binding scope so live
            // state changes refresh the lists.
            readonly property var results: root.service
              ? (void root.shownRevision, void root.service.favorites,
                 root.service.browseItems(root.appliedQuery, root.filterChip))
              : []
            readonly property var favorites: root.service
              ? (void root.shownRevision, root.service.favoriteSummaries())
              : []

            TextField {
              id: search
              anchors { top: parent.top; left: parent.left; right: parent.right }
              text: root.query
              placeholderText: "Search items…"
              onTextChanged: root.query = text
            }

            ButtonGroup {
              id: chips
              anchors { top: search.bottom; left: parent.left; right: parent.right }
              anchors.topMargin: Style.spacing.xl
              foreground: root.foreground
              fontFamily: root.family
              fontSize: Style.font.caption
              options: root.typeFilters
              value: root.filterChip
              onChanged: function(value) { root.filterChip = value }
            }

            Toggle {
              id: groupToggle
              anchors { top: chips.bottom; left: parent.left; right: parent.right }
              anchors.topMargin: Style.spacing.xl
              width: parent.width
              label: "Group by area"
              description: "Add area tabs for picked items, alongside Favorites."
              checked: root.service ? root.service.groupByArea : false
              foreground: root.foreground
              fontFamily: root.family
              onClicked: if (root.service) {
                root.service.setGroupByArea(!root.service.groupByArea)
              }
            }

            // Side by side, not stacked: the panel list and the list it was
            // picked from each keep the full height of the card.
            Item {
              id: columns
              anchors {
                top: groupToggle.bottom; bottom: parent.bottom
                left: parent.left; right: parent.right
              }
              anchors.topMargin: Style.spacing.xxl

              readonly property int gap: Style.spacing.huge
              readonly property int columnWidth: Math.floor((width - gap) / 2)

              // ---------- left: everything there is ----------
              Item {
                id: browseColumn
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: columns.columnWidth

                PanelSectionHeader {
                  id: allHeader
                  anchors { top: parent.top; left: parent.left; right: parent.right }
                  text: root.appliedQuery.length > 0 || root.filterChip !== "all"
                    ? "MATCHING ITEMS" : "ALL ITEMS"
                  foreground: root.foreground
                  fontFamily: root.family
                }

                // The note collapses to zero height when hidden, but the
                // collapse is driven by a wrapper so the Text's height is
                // never bound to its own implicitHeight (which QML flags as a
                // binding loop).
                Item {
                  id: emptyNote
                  anchors { top: allHeader.bottom; left: parent.left; right: parent.right }
                  anchors.topMargin: Style.spacing.lg
                  visible: picker.results.length === 0
                  height: visible ? noteText.implicitHeight : 0

                  Text {
                    textFormat: Text.PlainText
                    id: noteText
                    anchors.fill: parent
                    visible: emptyNote.visible
                    text: root.service && root.service.itemCount === 0
                    ? "No items yet — connect first."
                      : "Nothing matches that search."
                    color: Color.muted
                    font.family: root.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                ListView {
                  id: itemList
                  anchors {
                    top: emptyNote.bottom; bottom: parent.bottom
                    left: parent.left; right: parent.right
                  }
                  anchors.topMargin: Style.spacing.sm
                  clip: true
                  spacing: Style.spacing.xxs
                  model: picker.results
                  cacheBuffer: Style.space(200)
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  Connections {
                    target: root
                    function onAppliedQueryChanged() { itemList.positionViewAtBeginning() }
                    function onFilterChipChanged() { itemList.positionViewAtBeginning() }
                  }

                  delegate: SettingsItemRow {
                    required property var modelData
                    width: itemList.width
                    itemName: modelData.itemName
                    name: modelData.name
                    detail: modelData.available ? modelData.state : "Unavailable"
                    favorite: modelData.favorite
                    available: modelData.available
                    panelItem: false
                    service: root.service
                  }
                }
              }

              // ---------- right: what the panel shows ----------
              Item {
                id: favColumn
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                width: columns.columnWidth

                PanelSectionHeader {
                  id: favHeader
                  anchors { top: parent.top; left: parent.left; right: parent.right }
                  text: picker.favorites.length > 0
                    ? "IN THE PANEL · " + picker.favorites.length
                    : "IN THE PANEL"
                  foreground: root.foreground
                  fontFamily: root.family
                }

                // The column keeps its width when empty, so it needs to say
                // why it is blank rather than read as a rendering fault.
                Item {
                  id: favEmptyNote
                  anchors { top: favHeader.bottom; left: parent.left; right: parent.right }
                  anchors.topMargin: Style.spacing.lg
                  visible: picker.favorites.length === 0
                  height: visible ? favNoteText.implicitHeight : 0

                  Text {
                    textFormat: Text.PlainText
                    id: favNoteText
                    anchors.fill: parent
                    visible: favEmptyNote.visible
                    text: "Nothing picked yet — star an item on the left."
                    color: Color.muted
                    font.family: root.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                ListView {
                  id: favList
                  anchors {
                    top: favEmptyNote.bottom; bottom: parent.bottom
                    left: parent.left; right: parent.right
                  }
                  anchors.topMargin: Style.spacing.sm
                  clip: true
                  spacing: Style.spacing.xxs
                  model: picker.favorites
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  delegate: SettingsItemRow {
                    required property var modelData
                    width: favList.width
                    itemName: modelData.itemName
                    name: modelData.name
                    detail: modelData.available ? modelData.state : "Unavailable"
                    favorite: true
                    available: modelData.available
                    panelItem: true
                    service: root.service
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}