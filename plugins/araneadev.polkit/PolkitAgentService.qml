// The system-bus polkit agent of the Aranea prompt (Omarchy's agent path).
// PolkitAgent.qml creates it when agentEnabled and passes itself as `root`;
// tests leave it out (it would register a real agent on the system bus).

import Quickshell.Services.Polkit

PolkitAgent {
  id: polkitAgent

  // The polkit entry (PolkitAgent.qml) this agent reports to; set at creation.
  required property var root
  path: "/org/omarchy/PolkitAgent"

  onAuthenticationRequestStarted: polkitAgent.root.beginFlow()
  onIsActiveChanged: {
    if (isActive)
      polkitAgent.root.syncFromFlow()
    else if (!polkitAgent.root.closing)
      polkitAgent.root.resetSnapshot()
  }
  onIsRegisteredChanged: {
    if (isRegistered)
      console.log("aranea polkit agent registered")
    else
      console.warn("aranea polkit agent is not registered; another agent may be running")
  }
}
