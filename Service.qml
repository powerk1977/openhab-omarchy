import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "Connection.js" as Connection
import "Credentials.js" as Credentials
import "EntityStore.js" as EntityStore
import "ConfigStore.js" as ConfigStore
import "RowModel.js" as RowModel

// Owner of all openHAB state.
//
// A `service` is mounted once per session, a `bar-widget` once per monitor, so
// the bridge, items and config live here. Widgets reach them through
// `bar.shell.serviceFor("io.github.powerk1977.openhab")`.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/io.github.powerk1977.openhab"
  readonly property string configDir: home + "/.config/omarchy/openhab"
  readonly property string configPath: configDir + "/config.json"

  // idle | connecting | connected | error
  property string phase: "idle"
  property string lastError: ""
  property string lastErrorKind: ""
  // 'token' | 'userpass' | '' — the shape of the credential currently stored
  // for this origin, once known. Settings shows it as a non-secret hint.
  property string storedCredentialForm: ""
  property bool configured: false
  property bool demoMode: false
  property string baseUrl: ""
  // Optional alternate address for the same instance — a LAN address, say —
  // the bridge tries first, but only on trustedNetwork. Shares baseUrl's
  // credential; never its own keyring origin. See Connection.signature and
  // CredentialManager.
  property string localUrl: ""
  // The Wi-Fi network name localUrl requires a match against before the
  // bridge will ever try it. See bin/oh-bridge's current_wifi_ssid.
  property string trustedNetwork: ""
  // True only while connected through localUrl rather than baseUrl.
  property bool usingLocal: false
  property int connectionGeneration: 0
  property bool connectionSuppressed: false

  readonly property bool connected: phase === "connected"

  // Entity index + state; drives rows. The store mutates itself in place, so
  // `stateRevision` provides the scalars QML bindings can watch.
  property var entityStore: EntityStore.makeStore(Model)
  property int stateRevision: 0
  readonly property int itemCount: {
    root.stateRevision
    return root.entityStore.count()
  }

  // A ListModel, not a rebuilt array: one statechanged updates one delegate
  // instead of recreating every row.
  property ListModel rows: ListModel {}

  // ------------------------------------------------------------ config

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
    onFileChanged: reload()
  }

  function currentConfig() {
    return {
      baseUrl: root.baseUrl,
      localUrl: root.localUrl,
      trustedNetwork: root.trustedNetwork,
      demoMode: root.demoMode,
      favorites: root.liveFavorites.slice(),
      demoFavorites: root.demoFavorites.slice(),
      panelOrder: root.livePanelOrder.slice(),
      demoPanelOrder: root.demoPanelOrder.slice(),
      groupByArea: root.groupByArea,
      selectedTab: root.activeTab,
      expandedEquipment: root.expandedEquipment.slice()
    }
  }

  property var expandedEquipment: []

  // Favorites live in two disjoint namespaces so the demo house never shows
  // stale picks from a live instance (and vice versa), mirroring the reference.
  property var liveFavorites: []
  property var demoFavorites: []
  readonly property var favorites: root.demoMode ? root.demoFavorites : root.liveFavorites
  property var livePanelOrder: []
  property var demoPanelOrder: []
  readonly property var panelOrder: root.demoMode ? root.demoPanelOrder : root.livePanelOrder
  property bool groupByArea: false

  // The saved tab is the intent; `tabs` is what exists right now (area tabs
  // appear only once items and locations are known).
  property string activeTab: "favorites"
  property var tabs: [{ id: "favorites", title: "Favorites", itemNames: [] }]
  property int tabsRevision: 0

  // What is actually shown right now. Area tabs exist only when grouping is on
  // and items map to them; a saved selection that does not exist yet falls
  // back to the first tab without overwriting the intent.
  readonly property string effectiveTab: {
    root.tabsRevision
    for (var i = 0; i < root.tabs.length; i++) {
      if (root.tabs[i].id === root.activeTab) return root.activeTab
    }
    return root.tabs.length ? root.tabs[0].id : "favorites"
  }

  property Timer selectedTabSaveDebounce: Timer {
    interval: 300
    onTriggered: root.saveConfig({ selectedTab: root.activeTab })
  }

  function toggleFavorite(itemName) {
    var favorites = root.favorites.slice()
    var order = root.panelOrder.slice()
    var index = favorites.indexOf(itemName)
    if (index === -1) {
      favorites.push(itemName)
      if (order.indexOf(itemName) === -1) order.push(itemName)
    } else {
      favorites.splice(index, 1)
      var orderIndex = order.indexOf(itemName)
      if (orderIndex !== -1) order.splice(orderIndex, 1)
    }
    root.savePanelSelection(favorites, order)
  }

  function isFavorite(itemName) {
    return root.favorites.indexOf(itemName) !== -1
  }

  function movePanelItem(itemName, delta) {
    var order = root.panelOrder.slice()
    var index = order.indexOf(itemName)
    if (index === -1) return
    var target = index + delta
    if (target < 0 || target >= order.length) return
    order.splice(target, 0, order.splice(index, 1)[0])
    root.saveConfig(root.demoMode
      ? { demoPanelOrder: order } : { panelOrder: order })
  }

  function savePanelSelection(favorites, order) {
    root.saveConfig(root.demoMode ? {
      demoFavorites: favorites, demoPanelOrder: order
    } : {
      favorites: favorites, panelOrder: order
    })
  }

  function setGroupByArea(enabled) {
    if (root.groupByArea === enabled) return
    root.saveConfig({ groupByArea: enabled })
  }

  function setActiveTab(tabId) {
    if (root.activeTab === tabId) return
    root.activeTab = tabId
    root.rebuildRows()
    selectedTabSaveDebounce.restart()
  }

  function saveConfig(patch) {
    var config = ConfigStore.merge(root.currentConfig(), patch)
    var text = ConfigStore.serialize(config)

    configFile.setText(text)
    // FileView does not re-emit onLoaded for its own write.
    root.applyConfig(text)
  }

  // FileView will not create a missing parent directory, and starting the
  // process is asynchronous — doing it inside saveConfig races the write it is
  // supposed to enable, which on a fresh install loses the first save silently
  // (printErrors is off). Once, at startup, is early enough for every write.
  property Process configDirProcess: Process {
    command: ["mkdir", "-p", root.configDir]
  }

  Component.onCompleted: root.configDirProcess.running = true

  // ------------------------------------------------------------ credentials

  readonly property bool tokenWritePending: credentials.writePending
  readonly property bool tokenClearPending: credentials.clearPending
  readonly property bool credentialBusy: credentials.busy

  property CredentialManager credentials: CredentialManager {
    onTokenReady: function(token, origin) {
      if (token && origin === root.currentOrigin()) {
        root.storedCredentialForm = Credentials.classify(token)
      }
      if (!root.demoMode && !root.connectionSuppressed
          && origin === root.currentOrigin()) {
        root.pushConfig(token)
      } else if (!root.connectionSuppressed) {
        Qt.callLater(root.pushCredentials)
      }
    }
    onCleared: function(origin) {
      if (origin === root.currentOrigin()) root.finishRemoveConnection()
    }
    onFailed: function(message, origin) {
      if (origin && origin !== root.currentOrigin()) return
      root.phase = "error"
      root.lastError = message
      root.lastErrorKind = "credential"
    }
  }

  function currentOrigin() {
    return Connection.normalizeOrigin(root.baseUrl)
  }

  function requiresTokenFor(url) {
    var origin = Connection.normalizeOrigin(url)
    if (!origin) return true
    return root.demoMode || !root.configured || origin !== root.currentOrigin()
  }

  function removeConnection() {
    if (root.credentialBusy) {
      root.lastError = "Wait for the current keyring operation to finish."
      return
    }
    var origin = root.currentOrigin()
    root.connectionSuppressed = true
    root.disconnectBridge()
    root.appliedConnection = ""
    root.forgetDevices()
    if (!origin) {
      root.finishRemoveConnection()
      return
    }
    if (!credentials.clear(origin)) {
      root.phase = "error"
      root.lastError = "Could not start token removal while the keyring is busy."
    }
  }

  function finishRemoveConnection() {
    root.connectionSuppressed = false
    root.storedCredentialForm = ""
    root.saveConfig({
      baseUrl: "", localUrl: "", trustedNetwork: "", demoMode: false
    })
  }

  // A mode switch, not a form field: applies the moment it flips.
  function setDemoMode(enabled) {
    if (root.demoMode === enabled) return
    if (root.credentialBusy) {
      root.lastError = "Wait for the current keyring operation to finish."
      return
    }
    root.connectionSuppressed = false
    root.saveConfig({ demoMode: enabled })
  }

  // Stops the bridge retrying without discarding the configuration.
  function cancelConnection() {
    root.connectionSuppressed = true
    root.disconnectBridge()
    root.appliedConnection = ""
    root.forgetDevices()
    root.storedCredentialForm = ""
    root.phase = "idle"
    root.lastError = "Connection cancelled."
  }

  function retryConnection() {
    root.connectionSuppressed = false
    root.appliedConnection = ""
    root.lastError = ""
    root.reconcileConnection()
  }

  function applyConnection(url, localUrl, trustedNetwork, username, password,
                           token, demo) {
    var origin = demo ? "demo" : Connection.normalizeOrigin(url)
    if (!origin) {
      root.phase = "error"
      root.lastError = "Enter a valid http(s) openHAB URL."
      return false
    }
    // Optional, and validated the same way, but blank is always fine — it
    // just means no local fallback.
    var trimmedLocal = String(localUrl || "").trim()
    if (!demo && trimmedLocal && !Connection.normalizeOrigin(trimmedLocal)) {
      root.phase = "error"
      root.lastError = "Enter a valid http(s) local network URL, or leave it blank."
      return false
    }
    // A local URL with no trusted network to gate it would otherwise be tried
    // on every Wi-Fi the laptop ever joins, sending the token to whatever
    // happens to answer at that address. The bridge enforces this too — this
    // check exists to fail fast with a clear message instead of a silently
    // inert field.
    var trimmedTrust = String(trustedNetwork || "").trim()
    if (!demo && trimmedLocal && Connection.trustedNetworkList(trimmedTrust).length === 0) {
      root.phase = "error"
      root.lastError = "Enter at least one trusted Wi-Fi network name for the local URL, or leave the local URL blank."
      return false
    }
    // Exactly one form becomes the stored credential; an access token and
    // username/password both filled is never ambiguous — the token wins.
    var cred = Credentials.encode({
      username: String(username || ""),
      password: String(password || ""),
      token: String(token || "")
    })
    if (cred.error) {
      root.phase = "error"
      root.lastError = cred.error
      return false
    }
    if (!demo && !cred.value && root.requiresTokenFor(url)) {
      root.phase = "error"
      root.lastError = "A new openHAB origin requires credentials (an access token, or a username/password pair)."
      return false
    }
    root.connectionSuppressed = false
    // Start the serialized write before applyConfig runs so reconciliation
    // cannot race a lookup of the previous credential. The local URL is never
    // its own keyring origin: it shares whatever is stored for `origin`.
    // Blanks mean "keep the stored credential", so nothing is written then.
    if (!demo && cred.value.length > 0 && !credentials.store(cred.value, origin)) {
      root.phase = "error"
      root.lastError = "Could not start credential storage while the keyring is busy."
      return false
    }
    if (cred.value.length > 0) root.storedCredentialForm = cred.form
    root.saveConfig({
      baseUrl: url, localUrl: demo ? "" : trimmedLocal,
      trustedNetwork: demo ? "" : trimmedTrust, demoMode: demo
    })
    return true
  }

  // The text last projected into the properties below. saveConfig applies its
  // own write immediately (FileView doesn't re-emit onLoaded for it), and the
  // watcher then reports the same file a moment later — so every save
  // otherwise re-applied and re-projected the whole list twice.
  property string appliedConfigText: ""

  function applyConfig(text) {
    if (text && text === root.appliedConfigText) {
      // Same bytes, so every property below already holds them. Reconciliation
      // still runs: it is idempotent, and it is what restarts a bridge that
      // exited since the last apply.
      root.reconcileConnection()
      return
    }
    root.appliedConfigText = text
    var parsed = ConfigStore.parse(text, Model.DEMO_DEFAULT_FAVORITES)
    var config = parsed.config
    if (parsed.error) root.lastError = parsed.error

    root.demoMode = config.demoMode
    root.baseUrl = config.baseUrl
    root.localUrl = config.localUrl
    root.trustedNetwork = config.trustedNetwork
    root.expandedEquipment = config.expandedEquipment
    root.liveFavorites = config.favorites
    root.demoFavorites = config.demoFavorites
    root.livePanelOrder = config.panelOrder
    root.demoPanelOrder = config.demoPanelOrder
    root.groupByArea = config.groupByArea
    root.activeTab = config.selectedTab

    root.configured = root.demoMode || root.baseUrl.length > 0
    root.rebuildRows()
    root.reconcileConnection()
  }

  // Which connection the bridge is running for. Config is saved on every
  // change, and those must not drop the bridge.
  property string appliedConnection: ""

  function forgetDevices() {
    root.entityStore.reset()
    root.stateRevision++
    root.pendingToggles = ({})
    root.pendingToggleRevision++
    root.rebuildRows()
  }

  function disconnectBridge() {
    root.connectionGeneration++
    root.send({ op: "disconnect", generation: root.connectionGeneration })
  }

  function reconcileConnection() {
    if (root.connectionSuppressed) return

    if (!root.configured) {
      if (root.appliedConnection !== "") {
        // Clearing the config is not enough: the bridge holds an authenticated
        // socket open with the old token until it is told otherwise.
        root.disconnectBridge()
        root.forgetDevices()
      }
      root.appliedConnection = ""
      root.phase = "idle"
      return
    }

    // Connection.js owns this rule, so the definition of "same connection"
    // cannot drift from the one the tests pin.
    var signature = Connection.signature(
      root.demoMode, root.baseUrl, root.localUrl, root.trustedNetwork)
    if (!signature) {
      root.phase = "error"
      root.lastError = "openHAB URL is invalid."
      return
    }
    if (signature === root.appliedConnection && bridgeController.running) return

    // A new generation is visible synchronously in QML before the command can
    // reach Python. Any lines already buffered from the old bridge generation
    // are therefore rejected by handleEvent.
    if (root.appliedConnection !== "") root.forgetDevices()
    root.appliedConnection = signature
    root.connectionGeneration++

    if (root.startBridge()) root.pushCredentials()
  }

  // Split out of reconcileConnection because a bridge restart has to redo it:
  // the push that went to the process we just signalled never arrived.
  function pushCredentials() {
    if (root.demoMode) {
      root.pushConfig("")
      return
    }
    // A token being written pushes itself; reading here would race it.
    if (credentials.writePending) return
    var origin = root.currentOrigin()
    if (!origin) return
    // lookup() refuses while any other keyring process is in flight, and says
    // so only through its return value. Dropping that on the floor leaves the
    // panel stuck on "connecting" with nothing queued to push a token.
    if (!credentials.lookup(origin)) credentialRetry.restart()
  }

  property Timer credentialRetry: Timer {
    interval: 400
    onTriggered: {
      if (root.connectionSuppressed || !root.configured || root.demoMode) return
      root.pushCredentials()
    }
  }

  // ------------------------------------------------------------ bridge

  property BridgeController bridgeController: BridgeController {
    executable: root.pluginDir + "/bin/oh-bridge"
    onLine: function(value) { root.handleEvent(value) }
    onReady: {
      root.phase = "connecting"
      root.pushCredentials()
    }
    onFailed: function(message) {
      root.phase = "error"
      root.lastError = message
    }
  }

  // Settings needs this to tell "retrying" apart from "the helper died and
  // nothing is retrying at all", which otherwise both read as phase "error".
  readonly property bool bridgeRunning: bridgeController.running

  function startBridge() {
    root.phase = "connecting"
    return bridgeController.ensureStarted()
  }

  function send(command) {
    return bridgeController.send(command)
  }

  function pushConfig(token) {
    root.send({
      op: "config",
      url: root.baseUrl,
      localUrl: root.localUrl,
      trustedNetwork: root.trustedNetwork,
      token: token,
      generation: root.connectionGeneration
    })
  }

  // ------------------------------------------------------------ actions

  // item_name -> { desired, deadline }. The row flips at once and waits for
  // statechanged to confirm.
  property var pendingToggles: ({})
  // pendingToggles is mutated in place, so bindings need a scalar revision to
  // observe optimistic checked/busy changes immediately.
  property int pendingToggleRevision: 0

  property Timer pendingSweep: Timer {
    interval: 250
    repeat: true
    onTriggered: root.sweepPendingToggles()
  }

  function hasPendingToggles() {
    for (var key in root.pendingToggles) return true
    return false
  }

  // Must outlast the bridge's own request timeout, so a slow-but-successful
  // call does not report "no response" while the bridge still waits for the
  // answer it goes on to receive.
  readonly property int pendingToggleTimeout: 6500

  function setPendingToggle(itemName, desired) {
    root.pendingToggles[itemName] = {
      desired: desired,
      deadline: Date.now() + root.pendingToggleTimeout
    }
    root.pendingToggleRevision++
    root.refreshRow(itemName)
    pendingSweep.running = true
  }

  function clearPendingToggle(itemName) {
    if (root.pendingToggles[itemName] === undefined) return
    delete root.pendingToggles[itemName]
    root.pendingToggleRevision++
    if (!root.hasPendingToggles()) pendingSweep.running = false
    root.refreshRow(itemName)
  }

  function sweepPendingToggles() {
    var current = Date.now()
    var expired = []
    for (var itemName in root.pendingToggles) {
      if (root.pendingToggles[itemName].deadline <= current) expired.push(itemName)
    }
    for (var i = 0; i < expired.length; i++) {
      delete root.pendingToggles[expired[i]]
      root.refreshRow(expired[i])
      root.lastError = "No response from openHAB."
    }
    if (expired.length) root.pendingToggleRevision++
    if (!root.hasPendingToggles()) pendingSweep.running = false
  }

  function capabilitiesOf(itemName) {
    return Model.capabilitiesFor(root.entityStore.item(itemName))
  }

  function rejectAction(message) {
    root.lastError = message
    root.lastErrorKind = "command"
    return false
  }

  function toggleItem(itemName) {
    var item = root.entityStore.item(itemName)
    if (!item) return false
    if (root.pendingToggles[itemName] !== undefined) return false
    if (!Model.capabilitiesFor(item).toggle) {
      return root.rejectAction("This item does not support toggling.")
    }

    var currentlyOn = root.displayIsOn(itemName)
    var command = Model.toggleCommand(item, currentlyOn)
    root.setPendingToggle(itemName, !currentlyOn)
    var sent = root.setItem(itemName, command, "toggle:" + itemName)
    if (!sent) {
      root.clearPendingToggle(itemName)
      root.refreshRow(itemName)
    }
    return sent
  }

  function displayIsOn(itemName) {
    var pending = root.pendingToggles[itemName]
    if (pending !== undefined) return pending.desired
    var item = root.entityStore.item(itemName)
    return item ? Model.isOn(item) : false
  }

  // Every call is tagged. An untagged one has its failure dropped on the floor
  // by the bridge.
  property int callSequence: 0

  function callTag(itemName) {
    root.callSequence++
    return "item:" + itemName + ":" + root.callSequence
  }

  function setItem(itemName, command, tag) {
    return root.send({
      op: "setItem",
      name: itemName,
      command: command,
      tag: tag || ""
    })
  }

  signal commandFailed(string tag)

  // Returns the tag to match a later failure against, or "" if nothing went out.
  function setItemTagged(itemName, command) {
    var tag = root.callTag(itemName)
    return root.setItem(itemName, command, tag) ? tag : ""
  }

  function setBrightness(itemName, percent) {
    if (!root.capabilitiesOf(itemName).brightness) {
      return root.rejectAction("This item does not support brightness control.")
    }
    var pc = Math.max(0, Math.min(100, Math.round(percent)))
    return root.setItemTagged(itemName, String(pc))
  }

  function refresh() {
    root.send({ op: "refresh" })
  }

  // ------------------------------------------------------------ events

  function handleEvent(line) {
    var text = String(line || "").trim()
    if (!text) return

    var event
    try {
      event = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!event || typeof event !== "object") return
    if (!Connection.acceptsGeneration(root.connectionGeneration, event.generation)) {
      return
    }

    switch (event.ev) {
    case "phase":
      var transition = Connection.reducePhase({
        generation: root.connectionGeneration,
        phase: root.phase,
        error: root.lastError,
        errorKind: root.lastErrorKind
      }, event)
      if (!transition.accepted) return
      root.phase = transition.state.phase
      root.lastError = transition.state.error
      root.lastErrorKind = transition.state.errorKind
      root.usingLocal = transition.state.phase === "connected" && event.usingLocal === true
      break
    case "inventory":
      root.applyInventory(event.items || [])
      break
    case "states":
      root.applyStates(event.items || {})
      break
    case "statechanged":
      var delta = {}
      if (event.name) {
        delta[event.name] = { state: event.state, type: event.type || "" }
      }
      root.applyStateChanged(delta)
      break
    case "result":
      root.handleResult(event)
      break
    case "log":
      if (event.level === "warn") console.warn("oh-bridge: " + event.msg)
      break
    }
  }

  function handleResult(event) {
    if (event.success === true) return

    var tag = String(event.tag || "")
    if (tag.indexOf("toggle:") === 0) {
      // Drop the guess now rather than at the sweep timer. On success it
      // stays: the confirming statechanged is already on its way.
      var itemName = tag.slice("toggle:".length)
      root.clearPendingToggle(itemName)
      root.refreshRow(itemName)
    } else if (tag.indexOf("item:") === 0) {
      root.commandFailed(tag)
    }
    root.lastError = event.error || "Command failed."
    root.lastErrorKind = event.errorKind || "command"
  }

  function applyInventory(items) {
    root.entityStore.applyInventory(items)
    root.stateRevision++
    root.rebuildRows()
  }

  function applyStates(states) {
    root.entityStore.pushStates(states)
    root.stateRevision++
    // An initial snapshot can populate rows that were not there yet (the
    // inventory may arrive as an empty or partial list). Rebuilding cheaply
    // on the snapshot is fine; per-change updates go through refreshRow.
    root.rebuildRows()
  }

  function applyStateChanged(states) {
    var touched = root.entityStore.pushStates(states)
    root.stateRevision++
    for (var name in states) root.clearPendingToggle(name)
    if (touched.length) {
      for (var i = 0; i < touched.length; i++) {
        root.refreshRow(touched[i])
      }
    }
  }

  function refreshRow(itemName) {
    for (var i = 0; i < rows.count; i++) {
      if (rows.get(i).itemName === itemName) {
        var descriptor = root.rowDescriptor(itemName)
        rows.set(i, RowModel.project(descriptor))
        return
      }
    }
  }

  function rowDescriptor(itemName) {
    var item = root.entityStore.item(itemName)
    if (!item) {
      return {
        rowKind: "entity", itemName: itemName, name: itemName, subtitle: "",
        badge: "", icon: Model.FALLBACK_ICON, type: "", isOn: false,
        pending: root.displayIsOn(itemName), available: false, controlKind: "none",
        brightness: false, brightnessValue: -1, color: false,
        areaName: "__aOther__", equipmentName: ""
      }
    }
    var capabilities = Model.capabilitiesFor(item)
    return {
      rowKind: "entity",
      itemName: item.name,
      name: root.entityStore.displayNameFor(item),
      subtitle: Model.subtitle(item),
      badge: Model.badgeText(item),
      icon: root.entityStore.hasSemantics() ? Model.iconFor(item) : Model.FALLBACK_ICON,
      type: item.type,
      isOn: root.displayIsOn(itemName),
      pending: root.pendingToggles[itemName] !== undefined,
      available: capabilities.available,
      controlKind: capabilities.toggle ? "toggle" : "none",
      brightness: capabilities.brightness,
      brightnessValue: capabilities.brightness ? Model.brightnessOf(item) : -1,
      color: capabilities.color,
      areaName: root.entityStore.areaNameFor(item) || "__aOther__",
      equipmentName: item.pointOf || ""
    }
  }

  // ------------------------------------------------------------ rows

  // Settings browser. Walks the pre-sorted index, so this only filters.
  function browseItems(query, filterId) {
    var out = []
    var needle = String(query || "").trim().toLowerCase()
    var names = root.entityStore.sortedItemNames()
    for (var i = 0; i < names.length; i++) {
      var itemName = names[i]
      var item = root.entityStore.item(itemName)
      if (!item) continue
      if (filterId && filterId !== "all" && item.type !== filterId) continue
      if (needle) {
        var haystack = (root.entityStore.displayNameFor(item) + " " + itemName).toLowerCase()
        if (haystack.indexOf(needle) === -1) continue
      }
      out.push({
        itemName: itemName,
        name: root.entityStore.displayNameFor(item),
        state: Model.displayState(item),
        type: item.type,
        favorite: root.isFavorite(itemName),
        available: true
      })
    }
    return out
  }

  // The "IN THE PANEL" column, in panel order. Stale picks (item no longer in
  // the inventory) stay listed as unavailable rather than vanishing.
  function favoriteSummaries() {
    return root.panelOrder.map(function(itemName) {
      var item = root.entityStore.item(itemName)
      return {
        itemName: itemName,
        name: item ? root.entityStore.displayNameFor(item) : itemName,
        state: item ? Model.displayState(item) : "Unavailable",
        available: item !== null && item !== undefined,
        favorite: true
      }
    })
  }

  function computeTabs() {
    var picked = root.panelOrder.slice()
    var labels = {}
    var locations = root.entityStore.orderedLocations()
    for (var i = 0; i < locations.length; i++) labels[locations[i].name] = locations[i].label
    labels["__aOther__"] = "Other"
    function areaFor(itemName) {
      var item = root.entityStore.item(itemName)
      return item ? root.entityStore.areaNameFor(item) : ""
    }
    return root.entityStore.computeTabs(picked, root.groupByArea, labels, areaFor)
  }

  function rebuildRows() {
    root.tabs = root.computeTabs()
    root.tabsRevision++

    // The saved tab is the intent; a stale area selection (no items there
    // yet, or items moved) falls back to the first existing tab without
    // overwriting the saved choice.
    var effective = root.tabs.length ? root.tabs[0].id : "favorites"
    for (var i = 0; i < root.tabs.length; i++) {
      if (root.tabs[i].id === root.activeTab) {
        effective = root.activeTab
        break
      }
    }
    var itemNames = root.tabs[0] && root.tabs[0].itemNames
    for (var n = 0; n < root.tabs.length; n++) {
      if (root.tabs[n].id === effective) {
        itemNames = root.tabs[n].itemNames
        break
      }
    }

    rows.clear()
    for (var k = 0; k < itemNames.length; k++) {
      rows.append(RowModel.project(root.rowDescriptor(itemNames[k])))
    }
  }
}