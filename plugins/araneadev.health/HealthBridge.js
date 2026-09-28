.pragma library
// One instance per QML engine, shared by every file of this plugin that
// imports it. The Aranea bar is a replacement bar, so the host hands its
// widgets a facade without service lookup; Service.qml publishes itself here
// and Panel.qml (the bar widget) reads it back. Nothing outside this plugin
// imports this module.

// The published Service.qml item, or null while none is live.
var service = null

/**
 * Stores the health service so the bar widgets can find it.
 * @param {?object} value - the Service.qml root item; a falsy value clears the slot
 */
function publish(value) {
  service = value || null
}

// Only the instance that published may clear the slot: during a reload the
// new service can publish before the old one is destroyed.
/**
 * Clears the slot, but only when `value` is the service currently published.
 * @param {?object} value - the Service.qml item that is going away
 */
function retract(value) {
  if (service === value) service = null
}

/**
 * Returns the published health service.
 * @returns {?object} the Service.qml root item, or null if none is published
 */
function current() {
  return service
}
