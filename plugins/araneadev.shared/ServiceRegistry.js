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
