import * as THREE from "three"
import { GLTFLoader } from "./vendor/addons/loaders/GLTFLoader.js"
import { RoomEnvironment } from "./vendor/addons/environments/RoomEnvironment.js"
import { journey, MODEL_SCALE, WALK_SPEED } from "./journey.mjs"
import { SceneEvents } from "./effects.mjs"
import { createChamber } from "./chamber.mjs"

const options = new URLSearchParams(window.location.search)
const fixed = options.has("time") ? Number(options.get("time")) : null
const still = options.has("still")
let seed = 8181
const random = () => {
  seed = (seed * 1664525 + 1013904223) >>> 0
  return seed / 4294967296
}
const scene = new THREE.Scene()
scene.background = new THREE.Color("#060c0e")
scene.fog = new THREE.FogExp2("#060c0e", 0.024)
const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 140)
let renderer
try {
  renderer = new THREE.WebGLRenderer({
    antialias: true,
    preserveDrawingBuffer: still,
    powerPreference: "low-power"
  })
} catch (error) {
  document.getElementById("status").textContent =
    "Unable to start 3D preview. Press Escape to close."
  throw error
}
renderer.toneMapping = THREE.ACESFilmicToneMapping
renderer.toneMappingExposure = 1.25
renderer.shadowMap.enabled = true
renderer.shadowMap.type = THREE.PCFSoftShadowMap
document.body.appendChild(renderer.domElement)
const pmrem = new THREE.PMREMGenerator(renderer)
const room = new RoomEnvironment()
const environment = pmrem.fromScene(room, 0.04)
scene.environment = environment.texture
scene.environmentIntensity = 0.45
room.dispose()
pmrem.dispose()
function resize() {
  const w = window.innerWidth,
    h = window.innerHeight
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.4, Math.sqrt(2100000 / (w * h))))
  renderer.setSize(w, h)
  camera.aspect = w / h
  camera.updateProjectionMatrix()
}
resize()
window.addEventListener("resize", resize)

const {
  silkMaterial,
  silkWeb,
  tetherGeometry,
  tether,
  particleBase,
  particles,
  particleGeometry,
  key,
  movingLight,
  purpleLight
} = createChamber(scene, random)

try {
  const effects = new SceneEvents(scene, options.get("event"))
  await effects.load()
  const gltf = await new GLTFLoader().loadAsync("../aranea-spider.glb")
  const spider = new THREE.Group()
  spider.add(gltf.scene)
  scene.add(spider)
  gltf.scene.scale.setScalar(MODEL_SCALE)
  gltf.scene.traverse((obj) => {
    if (obj.isMesh) {
      obj.castShadow = true
      obj.receiveShadow = true
    }
  })
  const mixer = new THREE.AnimationMixer(gltf.scene)
  const idle = mixer.clipAction(THREE.AnimationClip.findByName(gltf.animations, "Idle")).play()
  const walk = mixer.clipAction(THREE.AnimationClip.findByName(gltf.animations, "Walk")).play()
  const hips = []
  gltf.scene.traverse((obj) => {
    if (obj.isBone && obj.name.endsWith("hip")) hips.push(obj)
  })
  let elapsed = fixed ?? 20,
    last = performance.now(),
    lastFrame = 0,
    frames = 0,
    facing = journey(elapsed).heading
  function draw(now) {
    if (!still && now - lastFrame < 1000 / 30 - 1) return
    const delta = Math.min(0.1, Math.max(0, (now - last) / 1000))
    last = now
    lastFrame = now
    if (!still) elapsed += delta
    const state = journey(elapsed)
    walk.setEffectiveWeight(state.walk)
    idle.setEffectiveWeight(1 - state.walk)
    walk.setEffectiveTimeScale(Math.min(7, state.speed / WALK_SPEED))
    mixer.update(still ? 0 : delta)
    if (still) {
      walk.time = (elapsed * 0.9) % walk.getClip().duration
      idle.time = elapsed % idle.getClip().duration
      mixer.update(0)
    }
    spider.position.set(state.position[0], state.position[1] - 0.065, state.position[2])
    const turn = Math.atan2(Math.sin(state.heading - facing), Math.cos(state.heading - facing))
    facing += turn * (still ? 1 : 1 - Math.exp(-delta * 6))
    spider.rotation.y = facing
    const hanging = state.phase === "descend" || state.phase === "ascend"
    spider.rotation.z = hanging ? 0.055 * Math.sin(elapsed * 1.4) : 0
    if (hanging)
      hips.forEach((bone, i) => {
        bone.rotation.x += 0.12
        bone.rotation.z += 0.025 * Math.sin(elapsed * 0.6 + i)
      })
    camera.position.fromArray(state.camera)
    camera.lookAt(...state.target)
    key.position.set(state.position[0] - 4, state.position[1] + 7, state.position[2] + 4)
    key.target.position.fromArray(state.position)
    movingLight.position.set(
      4 * Math.sin(elapsed * 0.07),
      state.position[1] + 3,
      state.position[2] - 3
    )
    purpleLight.position.set(-5, state.position[1] + 1, state.position[2] + 5)
    silkWeb.rotation.y = 0.006 * Math.sin(elapsed * 0.11)
    silkMaterial.opacity = 0.18 + 0.05 * Math.sin(elapsed * 0.17)
    tether.visible = hanging || state.phase === "anchor" || state.phase === "landing"
    const points = tetherGeometry.attributes.position
    points.setXYZ(0, state.position[2] < 0 ? 4.4 : -4.4, 23, state.position[2])
    points.setXYZ(1, spider.position.x, spider.position.y + 0.75, spider.position.z)
    points.needsUpdate = true
    tetherGeometry.computeBoundingSphere()
    particleBase.forEach((p, i) => {
      particles[i * 3] = p[0] + 0.3 * Math.sin(elapsed * 0.12 + p[3])
      particles[i * 3 + 1] = p[1] + 0.4 * Math.sin(elapsed * 0.15 + p[3])
      particles[i * 3 + 2] = p[2] + 0.3 * Math.cos(elapsed * 0.1 + p[3])
    })
    particleGeometry.attributes.position.needsUpdate = true
    movingLight.intensity = 34
    effects.update(elapsed, state, camera, silkMaterial, movingLight)
    renderer.render(scene, camera)
    document.body.dataset.ready = "true"
    document.body.dataset.phase = state.phase
    document.body.dataset.event = effects.current?.kind || "none"
    document.body.dataset.frames = String(++frames)
    document.body.dataset.calls = String(renderer.info.render.calls)
  }
  document.body.dataset.webgl = renderer.capabilities.isWebGL2 ? "2" : "1"
  draw(performance.now() + 34)
  renderer.setAnimationLoop(draw)
  window.addEventListener(
    "pagehide",
    () => {
      renderer.setAnimationLoop(null)
      effects.dispose()
      environment.dispose()
      renderer.dispose()
    },
    { once: true }
  )
} catch (error) {
  document.getElementById("status").textContent =
    "Unable to load the spider scene. Press Escape to close."
  document.body.dataset.error = String(error)
  console.error(error)
}
