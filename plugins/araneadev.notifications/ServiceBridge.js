.pragma library
// One instance per QML engine, shared by every file of this plugin that
// imports it. The Aranea bar is a replacement bar, so the host hands its
// widgets a facade without service lookup; Service.qml publishes itself here
// and Panel.qml (the bar widget) reads it back. Nothing outside this plugin
// imports this module.

var service = null

/**
 * Stores the live notification service for the bar widget to find.
 * @param {?object} value - the Service.qml root object; a falsy value clears the slot
 */
function publish(value) {
  service = value || null
}

/**
 * Clears the slot, but only when it still holds this service.
 *
 * Only the instance that published may clear the slot: during a reload the
 * new service can publish before the old one is destroyed.
 * @param {?object} value - the Service.qml root object being destroyed
 */
function retract(value) {
  if (service === value) service = null
}

/**
 * The published notification service.
 * @returns {?object} the Service.qml root object, or null when none is live
 */
function current() {
  return service
}
