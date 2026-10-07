.pragma library
// Publication slot for the persistent audio default-device owner.
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
 * Publishes the current default-device owner.
 * @param {*} value - live owner
 * @returns {void} no return value
 */
function publish(value) { registry.publish(value) }
/**
 * Retracts an owner only if it still occupies the publication slot.
 * @param {*} value - owner being destroyed
 * @returns {void} no return value
 */
function retract(value) { registry.retract(value) }
/**
 * Returns the live default-device owner.
 * @returns {*} live owner or null
 */
function current() { return registry.current() }
