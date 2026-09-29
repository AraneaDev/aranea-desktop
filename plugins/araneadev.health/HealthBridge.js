.pragma library
// Compatibility facade for the health plugin's existing imports.
/* @aranea-facade-start: plugins/araneadev.shared/ServiceRegistry.js */
// Creates an isolated service publication slot for a QML plugin bridge.

/**
 * Creates a publish/retract/current service registry.
 * @returns {object} Registry with publish, retract and current methods.
 */
function create() {
  /** @type {*} */
  var service = null
  return {
    publish: function (/** @type {*} */ value) {
      service = value || null
    },
    retract: function (/** @type {*} */ value) {
      if (service === value) service = null
    },
    current: function () {
      return service
    }
  }
}

if (typeof module !== "undefined") module.exports = { create: create }
/* @aranea-facade-end */
var registry = create()
/**
 * Publishes the live health service.
 * @param {*} value - Service object.
 */
function publish(value) { registry.publish(value) }
/**
 * Retracts the service when it is still current.
 * @param {*} value - Service object.
 */
function retract(value) { registry.retract(value) }
/**
 * Returns the current health service.
 * @returns {*} Service object or null.
 */
function current() { return registry.current() }
