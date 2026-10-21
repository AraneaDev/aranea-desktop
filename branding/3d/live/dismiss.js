// Independent of the 3D module, so Escape works even if WebGL or loading fails.
;(() => {
  const options = new URLSearchParams(window.location.search)
  const screenId = options.get("screen") || "legacy"
  let closed = false,
    ready = false,
    failed = false
  async function notify(kind, message) {
    try {
      await fetch(`/__${kind}`, {
        method: "POST",
        headers: { "X-Aranea-Session": options.get("session") || "" },
        body: JSON.stringify(message ? { screenId, message } : { screenId })
      })
    } catch {
      /* The session server may already be closing. */
    }
  }
  function failure() {
    if (failed) return
    failed = true
    void notify("failed", "Unable to render the local scene.")
  }
  window.addEventListener("error", failure)
  window.addEventListener("unhandledrejection", failure)
  const observer = new MutationObserver(() => {
    if (document.body.dataset.error) failure()
    if (!ready && document.body.dataset.ready === "true") {
      ready = true
      void notify("ready")
    }
  })
  observer.observe(document.body, {
    attributes: true,
    attributeFilter: ["data-ready", "data-error"]
  })
  async function dismiss() {
    if (closed) return
    closed = true
    await notify("dismiss")
    window.close()
  }
  window.addEventListener("keydown", dismiss)
  window.addEventListener("pointerdown", dismiss)
  let origin = null
  const armedAt = performance.now() + 1500
  window.addEventListener("pointermove", (event) => {
    if (performance.now() < armedAt || !origin) {
      origin = [event.clientX, event.clientY]
      return
    }
    if (Math.hypot(event.clientX - origin[0], event.clientY - origin[1]) > 20) dismiss()
  })
  setTimeout(() => {
    if (document.body.dataset.ready !== "true") {
      failure()
      document.getElementById("status").textContent =
        "Unable to start the preview. Press Escape to close."
    }
  }, 20000)
})()
