import * as THREE from "three"
import { renderScale } from "./motion.mjs"

const options = new URLSearchParams(location.search)
const still = options.has("still")
const requestedTime = Number(options.get("time"))
const startTime = options.has("time") && Number.isFinite(requestedTime) ? requestedTime : 24
let renderer
try {
  renderer = new THREE.WebGLRenderer({
    antialias: true,
    preserveDrawingBuffer: still,
    powerPreference: "low-power"
  })
  renderer.debug.onShaderError = () => {
    throw new Error("Unable to compile the local scene shaders")
  }
  renderer.setClearColor("#08090b")
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.2
  document.body.append(renderer.domElement)
  const scene = new THREE.Scene()
  scene.fog = new THREE.FogExp2("#08090b", 0.014)
  const camera = new THREE.PerspectiveCamera(54, 1, 0.1, 360)
  const resize = () => {
    renderer.setPixelRatio(renderScale(innerWidth, innerHeight, devicePixelRatio))
    renderer.setSize(innerWidth, innerHeight)
    camera.aspect = innerWidth / innerHeight
    camera.updateProjectionMatrix()
  }
  resize()
  addEventListener("resize", resize)
  const module = await import(`./${document.body.dataset.scene}.mjs`)
  const update = await module.createScene(scene, camera)
  let frames = 0,
    previous = -Infinity
  const origin = performance.now()
  function draw(now) {
    if (now - previous < 1000 / 30 - 0.2) return
    previous = now
    const time = startTime + (still ? 0 : (now - origin) / 1000)
    update(time)
    renderer.render(scene, camera)
    document.body.dataset.frames = String(++frames)
    document.body.dataset.calls = String(renderer.info.render.calls)
    document.body.dataset.ready = "true"
  }
  draw(origin)
  if (!still) renderer.setAnimationLoop(draw)
  addEventListener(
    "pagehide",
    () => {
      renderer.setAnimationLoop(null)
      renderer.dispose()
    },
    { once: true }
  )
} catch (error) {
  document.body.dataset.error = "Unable to render the local scene"
  document.getElementById("status").textContent =
    "Unable to start the scene. Press Escape to close."
  console.error(error)
}
