import * as THREE from "three"
import { GLTFLoader } from "./vendor/addons/loaders/GLTFLoader.js"
import { RoomEnvironment } from "./vendor/addons/environments/RoomEnvironment.js"
import { journey, MODEL_SCALE, WALK_SPEED } from "./journey.mjs"
import { SceneEvents } from "./effects.mjs"

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

const stone = new THREE.MeshStandardMaterial({ color: 0x182024, roughness: 0.64, metalness: 0.55 })
const dark = new THREE.MeshStandardMaterial({ color: 0x080e12, roughness: 0.65, metalness: 0.7 })
const mint = new THREE.MeshStandardMaterial({
  color: 0x23ae88,
  emissive: 0x11bd86,
  emissiveIntensity: 2.3,
  roughness: 0.3,
  metalness: 0.4
})
const violet = new THREE.MeshStandardMaterial({
  color: 0x33205c,
  emissive: 0x5632aa,
  emissiveIntensity: 2,
  roughness: 0.4
})
// Procedural stone grain: self-contained, no image or wallpaper textures.
const textureCanvas = document.createElement("canvas")
textureCanvas.width = textureCanvas.height = 256
const context = textureCanvas.getContext("2d")
context.fillStyle = "#727b7b"
context.fillRect(0, 0, 256, 256)
for (let i = 0; i < 6500; i++) {
  const v = Math.floor(70 + random() * 90)
  context.fillStyle = `rgba(${v},${v},${v},.4)`
  context.fillRect(random() * 256, random() * 256, 1 + random() * 3, 1 + random() * 3)
}
for (let i = 0; i < 12; i++) {
  context.strokeStyle = "rgba(10,20,22,.35)"
  context.beginPath()
  let x = random() * 256,
    y = random() * 256
  context.moveTo(x, y)
  for (let j = 0; j < 5; j++) {
    x += (random() - 0.5) * 55
    y += random() * 30
    context.lineTo(x, y)
  }
  context.stroke()
}
const grain = new THREE.CanvasTexture(textureCanvas)
grain.wrapS = grain.wrapT = THREE.RepeatWrapping
grain.repeat.set(2, 2)
stone.roughnessMap = grain
stone.bumpMap = grain
stone.bumpScale = 0.06
function box(w, h, d, x, y, z, material = stone) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), material)
  mesh.position.set(x, y, z)
  mesh.receiveShadow = true
  scene.add(mesh)
  return mesh
}
function beam(a, b, r, material = stone) {
  const av = new THREE.Vector3(...a),
    bv = new THREE.Vector3(...b)
  const mesh = new THREE.Mesh(new THREE.CylinderGeometry(r, r, av.distanceTo(bv), 8), material)
  mesh.position.copy(av).add(bv).multiplyScalar(0.5)
  mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), bv.sub(av).normalize())
  scene.add(mesh)
  return mesh
}
// Two traversable suspended causeways, with dark segmented slabs and inset light.
for (const level of [6, -3]) {
  box(4.6, 0.35, 31, 0, level - 0.22, 2, dark)
  for (let i = 0; i < 14; i++) {
    const z = -12.5 + i * 2.25
    box(4.5, 0.16, 2.18, 0, level - 0.08, z)
    for (const side of [-1, 1]) {
      box(0.065, 0.035, 2, side * 2.12, level + 0.015, z, mint)
      if (i % 2 === 0) box(0.22, 0.7, 0.35, side * 2.28, level + 0.1, z, dark)
    }
  }
  for (const z of [-10, 2, 14])
    for (const x of [-2, 2]) beam([x, level - 0.4, z], [x * 2, level - 4, z + 2], 0.12, dark)
}
// Monumental ribs establish a space to explore, beyond the immediate bridges.
for (const z of [-24, -12, 0, 12, 24]) {
  const points = [
    [-13, -18, z],
    [-13, 12, z],
    [-10, 19, z],
    [-5, 23, z],
    [0, 24, z],
    [5, 23, z],
    [10, 19, z],
    [13, 12, z],
    [13, -18, z]
  ]
  const curve = new THREE.CatmullRomCurve3(points.map((p) => new THREE.Vector3(...p)))
  const rib = new THREE.Mesh(new THREE.TubeGeometry(curve, 48, 0.55, 8, false), stone)
  scene.add(rib)
  for (const x of [-12.3, 12.3]) box(0.045, 22, 0.08, x, 3, z + 0.1, violet)
}
for (let i = 0; i < 38; i++) {
  const side = i % 2 ? 1 : -1
  const x = side * (20 + random() * 12),
    z = -35 + random() * 70,
    h = 17 + random() * 28
  const rock = new THREE.Mesh(
    new THREE.CylinderGeometry(0.35 + random() * 0.8, 0.7 + random(), h, 5),
    stone
  )
  rock.position.set(x, -18 + h / 2, z)
  rock.rotation.z = side * (random() - 0.5) * 0.08
  scene.add(rock)
}
box(100, 1, 100, 0, -19, 0, dark)
// Long silk curtains and stretched radial webs between structural ribs.
const silkPositions = []
function strand(a, b, steps = 8, sag = 0.2) {
  for (let j = 0; j < steps; j++) {
    for (const u of [j / steps, (j + 1) / steps]) {
      silkPositions.push(
        a[0] + (b[0] - a[0]) * u,
        a[1] + (b[1] - a[1]) * u - Math.sin(u * Math.PI) * sag,
        a[2] + (b[2] - a[2]) * u
      )
    }
  }
}
for (const side of [-1, 1])
  for (const z of [-12, 0, 12]) {
    const center = [side * 8, 8, z]
    const ring = []
    for (let i = 0; i < 14; i++) {
      const a = (i / 14) * Math.PI * 2
      ring.push([
        center[0] + Math.cos(a) * 4.3,
        center[1] + Math.sin(a) * 6,
        center[2] + Math.sin(a * 2) * 0.4
      ])
    }
    for (const point of ring) strand(center, point, 6, 0.12)
    for (let r = 1; r <= 7; r++)
      for (let i = 0; i < 14; i++) {
        const a = ring[i].map((v, j) => center[j] + ((v - center[j]) * r) / 7)
        const b = ring[(i + 1) % 14].map((v, j) => center[j] + ((v - center[j]) * r) / 7)
        strand(a, b, 3, 0.08)
      }
  }
for (let i = 0; i < 50; i++) {
  const x = (random() - 0.5) * 22,
    z = -27 + random() * 55
  strand([x, 23, z], [x + (random() - 0.5) * 2, -9 - random() * 7, z + random()], 10, 0.18)
}
const silkGeometry = new THREE.BufferGeometry()
silkGeometry.setAttribute("position", new THREE.Float32BufferAttribute(silkPositions, 3))
const silkMaterial = new THREE.LineBasicMaterial({
  color: 0x519d8c,
  transparent: true,
  opacity: 0.22,
  blending: THREE.AdditiveBlending,
  depthWrite: false
})
const silkWeb = new THREE.LineSegments(silkGeometry, silkMaterial)
scene.add(silkWeb)
const tetherGeometry = new THREE.BufferGeometry().setFromPoints([
  new THREE.Vector3(),
  new THREE.Vector3(0, 20, 0)
])
const tether = new THREE.Line(
  tetherGeometry,
  new THREE.LineBasicMaterial({ color: 0x8cedce, transparent: true, opacity: 0.8 })
)
scene.add(tether)
for (const [x, z] of [
  [4.4, -6],
  [-4.4, 10]
]) {
  beam(
    [x, 23, z],
    [x, 6.1, z],
    0.006,
    new THREE.MeshBasicMaterial({ color: 0x4b8275, transparent: true, opacity: 0.3 })
  )
  box(0.7, 0.18, 0.7, x, 23, z, dark)
}
const particleCount = 550,
  particleBase = []
const particles = new Float32Array(particleCount * 3)
for (let i = 0; i < particleCount; i++)
  particleBase.push([
    (random() - 0.5) * 32,
    -12 + random() * 37,
    -30 + random() * 60,
    random() * Math.PI * 2
  ])
const particleGeometry = new THREE.BufferGeometry()
particleGeometry.setAttribute("position", new THREE.BufferAttribute(particles, 3))
const motes = new THREE.Points(
  particleGeometry,
  new THREE.PointsMaterial({
    color: 0x7ab7a7,
    size: 0.026,
    transparent: true,
    opacity: 0.45,
    depthWrite: false,
    blending: THREE.AdditiveBlending
  })
)
scene.add(motes)
scene.add(new THREE.HemisphereLight(0x97c9bd, 0x15202c, 1.2))
const key = new THREE.DirectionalLight(0xbed5d6, 3.2)
scene.add(key)
scene.add(key.target)
key.castShadow = true
key.shadow.mapSize.set(1024, 1024)
key.shadow.camera.left = -7
key.shadow.camera.right = 7
key.shadow.camera.top = 7
key.shadow.camera.bottom = -7
key.shadow.bias = -0.001
const movingLight = new THREE.PointLight(0x4dffd0, 34, 28, 1.5)
scene.add(movingLight)
const purpleLight = new THREE.PointLight(0x6942f5, 45, 35, 1.5)
scene.add(purpleLight)
for (const z of [-16, 2, 20]) {
  const light = new THREE.PointLight(0x295c79, 22, 30, 1.5)
  light.position.set(-7, 14, z)
  scene.add(light)
  const shaft = new THREE.Mesh(
    new THREE.ConeGeometry(3, 29, 24, 1, true),
    new THREE.MeshBasicMaterial({
      color: 0x61b6b2,
      transparent: true,
      opacity: 0.025,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      side: THREE.DoubleSide
    })
  )
  shaft.position.set(-7, 6, z)
  scene.add(shaft)
}
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
