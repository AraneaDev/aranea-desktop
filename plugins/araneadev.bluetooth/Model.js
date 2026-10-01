/**
 * The device's display label: its friendly deviceName, else its raw name.
 * @param {*} device - the BlueZ device (Quickshell BluetoothDevice), or falsy
 * @returns {string} the trimmed label, or "" when device is falsy
 */
function deviceLabel(device) {
  if (!device) return ""
  return String(device.deviceName || device.name || "").trim()
}

/**
 * Copies a live list-like value (a Quickshell model or plain array) into a
 * plain array snapshot.
 * @param {*} values - the list-like value, or falsy
 * @returns {Array<*>} a plain array copy, or [] when values has no slice()
 */
function toArray(values) {
  if (!values) return []
  if (Array.isArray(values)) return values.slice()

  var length = Number(values.length || 0)
  if (!isFinite(length) || length <= 0) return []

  var list = []
  for (var i = 0; i < length; i++) list.push(values[i])
  return list
}

/**
 * Tells whether a label looks like a Bluetooth service UUID (128-bit, short
 * hex form, or the Bluetooth base UUID) rather than a human-chosen name.
 * @param {*} value - the raw label
 * @returns {boolean} true when value looks like a UUID
 */
function isUuidLike(value) {
  var text = String(value || "").trim()
  if (text === "") return false
  return (
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text) ||
    /^[0-9a-f]{32}$/i.test(text) ||
    /^0x[0-9a-f]{4,32}$/i.test(text) ||
    /^0000[0-9a-f]{4}-0000-1000-8000-00805f9b34fb$/i.test(text)
  )
}

/**
 * Tells whether a label looks like a MAC address rather than a human-chosen
 * name.
 * @param {*} value - the raw label
 * @returns {boolean} true when value looks like a MAC address
 */
function isAddressLike(value) {
  var text = String(value || "").trim()
  return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(text)
}

/**
 * A MAC address with separators and case stripped, for substring matching.
 * @param {*} value - the raw address-like text
 * @returns {string} lower-case hex digits only
 */
function normalizedAddress(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^0-9a-f]/g, "")
}

/**
 * Tells whether a device has a name beyond its own UUID or MAC address
 * (BlueZ reports those as the name for devices it knows nothing else about).
 * @param {*} device - the BlueZ device, or falsy
 * @returns {boolean} true when the device has a human-chosen name
 */
function hasHumanName(device) {
  var label = deviceLabel(device)
  return label !== "" && !isUuidLike(label) && !isAddressLike(label)
}

/**
 * A Pipewire node's properties bag, safe to read even before it is bound.
 * @param {*} node - the Pipewire node, or falsy
 * @returns {{[key: string]: string}} node.properties when the node is ready, else {}
 */
function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

/**
 * All of a Pipewire node's name-ish fields and properties, joined and
 * lower-cased, for matching a node against a Bluetooth device.
 * @param {*} node - the Pipewire node, or falsy
 * @returns {string} the lower-cased, space-joined text blob
 */
function nodeText(node) {
  var props = nodeProps(node)
  return [
    node ? node.name : "",
    node ? node.description : "",
    node ? node.nickname : "",
    node ? node.nick : "",
    props["node.name"],
    props["node.description"],
    props["node.nick"],
    props["device.name"],
    props["device.description"],
    props["device.product.name"],
    props["device.alias"],
    props["device.string"],
    props["api.bluez5.address"],
    props["bluez5.address"],
    props["media.name"]
  ]
    .join(" ")
    .toLowerCase()
}

/**
 * Tells whether a Pipewire sink node is the audio output for a given
 * Bluetooth device, matched by address or by label substring.
 * @param {*} node - the Pipewire node, or falsy
 * @param {*} device - the BlueZ device, or falsy
 * @returns {boolean} true when node is device's audio sink
 */
function bluetoothSinkMatchesDevice(node, device) {
  if (!node || !node.isSink || node.isStream || !device) return false

  var address = normalizedAddress(device.address)
  var text = nodeText(node)
  if (address !== "" && normalizedAddress(text).indexOf(address) !== -1) return true

  var label = deviceLabel(device).toLowerCase()
  return label !== "" && text.indexOf(label) !== -1
}

/**
 * A list-like value of devices, snapshotted and sorted by display label.
 * @param {*} devices - the list-like value of BlueZ devices
 * @returns {Array<*>} the devices, sorted by deviceLabel
 */
function sortedByLabel(devices) {
  var list = toArray(devices)
  list.sort(function (a, b) {
    return deviceLabel(a).localeCompare(deviceLabel(b))
  })
  return list
}

// Primitives-only projection of a BlueZ device for list-model rows. Holding
// the Device QObject in model data puts a live wrapper into every delegate's
// var property, and BlueZ churn (discovery timeouts, unpair) can destroy the
// object while a delegate is still incubating, which segfaults quickshell.
// Actions resolve the backend object via Panel.deviceFor().
/**
 * The primitives-only row for a BlueZ device.
 * @param {*} d - the BlueZ device, or falsy
 * @returns {?object} the primitives-only row, or null when d is falsy
 */
function deviceRow(d) {
  if (!d) return null
  return {
    address: d.address || "",
    name: d.name || "",
    deviceName: d.deviceName || "",
    connected: !!d.connected,
    state: d.state !== undefined ? d.state : -1,
    batteryAvailable: !!d.batteryAvailable,
    battery: d.battery !== undefined ? d.battery : 0,
    pairing: !!d.pairing
  }
}

/**
 * Splits known BlueZ devices into connected, known (paired/bonded/trusted
 * but not connected) and discovered (unremembered) lists, each sorted by
 * label. Devices without a human-chosen name are dropped entirely.
 * @param {*} devices - the list-like value of BlueZ devices
 * @returns {{connected: Array<*>, known: Array<*>, discovered: Array<*>}} the three lists
 */
function deviceLists(devices) {
  var values = toArray(devices)
  var connected = []
  var known = []
  var discovered = []

  for (var i = 0; i < values.length; i++) {
    var d = values[i]
    if (!d || !hasHumanName(d)) continue
    if (d.connected) connected.push(d)
    else if (d.paired || d.bonded || d.trusted) known.push(d)
    else discovered.push(d)
  }

  return {
    connected: sortedByLabel(connected),
    known: sortedByLabel(known),
    discovered: sortedByLabel(discovered)
  }
}

/**
 * A shallow copy of a pending-actions map (address -> action string).
 * @param {*} map - the map, or falsy
 * @returns {{[key: string]: string}} the copy
 */
function cloneMap(map) {
  /** @type {{[key: string]: string}} */
  var next = {}
  for (var key in map || {}) next[key] = map[key]
  return next
}

/**
 * The pending action for a device address, if any.
 * @param {*} actions - the pending-actions map
 * @param {*} address - the device address
 * @returns {string} the action ("connecting"/"disconnecting"/"forgetting"), or ""
 */
function pendingAction(actions, address) {
  return address && actions && actions[address] ? actions[address] : ""
}

/**
 * A copy of the pending-actions map with address's action set (or cleared).
 * @param {*} actions - the pending-actions map
 * @param {*} address - the device address
 * @param {*} action - the action to record, or falsy to clear it
 * @returns {{[key: string]: string}} the updated copy
 */
function withPendingAction(actions, address, action) {
  var next = cloneMap(actions)
  if (!address) return next
  if (action) next[address] = action
  else delete next[address]
  return next
}

/**
 * Which device-list sections have content to show, in display order.
 * "discovered" only counts while a scan (discovering) is active.
 * @param {*} lists - the {connected, known, discovered} lists from deviceLists
 * @param {*} discovering - whether the adapter is currently scanning
 * @returns {Array<string>} the visible section names
 */
function visibleSections(lists, discovering) {
  var sections = []
  if (lists && lists.connected && lists.connected.length > 0) sections.push("connected")
  if (lists && lists.known && lists.known.length > 0) sections.push("known")
  if (discovering && lists && lists.discovered && lists.discovered.length > 0)
    sections.push("discovered")
  return sections
}

/**
 * The devices belonging to one section of the {connected, known, discovered}
 * lists.
 * @param {*} lists - the lists from deviceLists
 * @param {string} section - "connected", "known" or "discovered"
 * @returns {Array<*>} the section's devices, or [] for an unknown section
 */
function sectionDevices(lists, section) {
  if (!lists) return []
  if (section === "connected") return lists.connected || []
  if (section === "known") return lists.known || []
  if (section === "discovered") return lists.discovered || []
  return []
}

if (typeof module !== "undefined") {
  module.exports = {
    deviceLabel: deviceLabel,
    toArray: toArray,
    isUuidLike: isUuidLike,
    isAddressLike: isAddressLike,
    normalizedAddress: normalizedAddress,
    hasHumanName: hasHumanName,
    nodeProps: nodeProps,
    nodeText: nodeText,
    bluetoothSinkMatchesDevice: bluetoothSinkMatchesDevice,
    sortedByLabel: sortedByLabel,
    deviceRow: deviceRow,
    deviceLists: deviceLists,
    cloneMap: cloneMap,
    pendingAction: pendingAction,
    withPendingAction: withPendingAction,
    visibleSections: visibleSections,
    sectionDevices: sectionDevices
  }
}
