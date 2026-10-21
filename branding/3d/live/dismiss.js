// Independent of the 3D module, so Escape works even if WebGL or loading fails.
;(() => {
  const options = new URLSearchParams(window.location.search)
  let closed = false
  async function dismiss() {
    if (closed) return
    closed = true
    try {
      await fetch("/__dismiss", {
        method: "POST",
        headers: { "X-Aranea-Session": options.get("session") || "" }
      })
    } catch {
      /* The preview server may already be closing. */
    }
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
      document.getElementById("status").textContent =
        "Unable to start the preview. Press Escape to close."
    }
  }, 20000)
})()
