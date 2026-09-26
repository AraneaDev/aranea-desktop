.pragma library
// One instance per QML engine, shared by every file of this plugin that
// imports it. The Aranea bar is a replacement bar, so the host hands its
// widgets a facade without service lookup; Service.qml publishes itself here
// and Panel.qml (the bar widget) reads it back. Nothing outside this plugin
// imports this module.

var service = null

function publish(value) {
  service = value || null
}

// Only the instance that published may clear the slot: during a reload the
// new service can publish before the old one is destroyed.
function retract(value) {
  if (service === value) service = null
}

function current() {
  return service
}
