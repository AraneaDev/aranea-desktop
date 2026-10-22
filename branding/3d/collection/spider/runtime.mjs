import * as THREE from "three"
import { GLTFLoader } from "../../live/vendor/addons/loaders/GLTFLoader.js"
import { RoomEnvironment } from "../../live/vendor/addons/environments/RoomEnvironment.js"
import { weaver, spiderfall } from "./motion.mjs"

const fall = document.body.dataset.scene === "fall"
const options = new URLSearchParams(location.search)
const fixed = Number(options.get("time"))
const still = options.has("still")
const sample = fall ? spiderfall : weaver
const mint = "#3bff9e",
  violet = "#7a5cff",
  gold = "#e6c98a"
let renderer, environment
function failure(error) {
  document.body.dataset.error = "Unable to render the local spider scene"
  document.getElementById("status").textContent =
    "Unable to load this scene. Press any key to close."
  console.error(error)
}
try {
  const scene = new THREE.Scene()
  scene.background = new THREE.Color("#08090b")
  scene.fog = new THREE.FogExp2("#08090b", fall ? 0.037 : 0.023)
  const camera = new THREE.PerspectiveCamera(fall ? 47 : 48, 1, 0.1, 150)
  renderer = new THREE.WebGLRenderer({
    antialias: true,
    preserveDrawingBuffer: still,
    powerPreference: "low-power"
  })
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.35
  document.body.appendChild(renderer.domElement)
  const pmrem = new THREE.PMREMGenerator(renderer)
  const room = new RoomEnvironment()
  environment = pmrem.fromScene(room, 0.04)
  scene.environment = environment.texture
  scene.environmentIntensity = 0.55
  room.dispose()
  pmrem.dispose()
  const dark = new THREE.MeshStandardMaterial({
    color: "#11191d",
    roughness: 0.42,
    metalness: 0.75
  })
  const side = new THREE.MeshStandardMaterial({
    color: "#121016",
    roughness: 0.55,
    metalness: 0.65
  })
  const glow = (color, opacity = 1) =>
    new THREE.MeshBasicMaterial({ color, transparent: opacity < 1, opacity })
  const green = glow(mint),
    purple = glow(violet),
    amber = glow(gold)
  const boxGeometry = new THREE.BoxGeometry(1, 1, 1)
  function box(x, y, z, w, h, d, material = dark, parent = scene) {
    const mesh = new THREE.Mesh(boxGeometry, material)
    mesh.position.set(x, y, z)
    mesh.scale.set(w, h, d)
    parent.add(mesh)
    return mesh
  }
  function line(points, color = mint, opacity = 0.65) {
    const geometry = new THREE.BufferGeometry().setFromPoints(
      points.map((p) => new THREE.Vector3(...p))
    )
    const object = new THREE.Line(
      geometry,
      new THREE.LineBasicMaterial({ color, transparent: true, opacity })
    )
    scene.add(object)
    return object
  }
  const key = new THREE.DirectionalLight("#d7ffe9", 3.5)
  key.position.set(3, 8, 4)
  scene.add(key, key.target, new THREE.HemisphereLight("#a4ffe0", "#31203b", 1.6))
  const rim = new THREE.PointLight(violet, 65, 22, 1.5)
  const local = new THREE.PointLight(mint, 35, 16, 1.6)
  scene.add(rim, local)
  const animated = []
  let web, tether
  if (!fall) {
    // A suspended annular promenade surrounds a luminous, partly woven oculus.
    const floor = new THREE.Mesh(new THREE.RingGeometry(4.8, 7.4, 96), dark)
    floor.rotation.x = -Math.PI / 2
    floor.position.y = -0.1
    scene.add(floor)
    for (const radius of [4.8, 7.35]) {
      const rail = new THREE.Mesh(
        new THREE.TorusGeometry(radius, 0.018, 5, 128),
        radius < 5 ? green : purple
      )
      rail.rotation.x = Math.PI / 2
      rail.position.y = 0.04
      scene.add(rail)
    }
    const vertices = []
    for (let i = 0; i < 48; i++) {
      const a = (i / 48) * Math.PI * 2
      const x = Math.cos(a),
        z = Math.sin(a)
      vertices.push(0, -0.12, 0, x * 4.75, 0.12, z * 4.75)
      for (let j = 1; j < 9; j++) {
        const b = a + (Math.PI * 2) / 48,
          r = j * 0.52
        vertices.push(
          x * r,
          0.12 - 0.12 * Math.sin(j),
          z * r,
          Math.cos(b) * r,
          0.12 - 0.12 * Math.sin(j),
          Math.sin(b) * r
        )
      }
    }
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3))
    web = new THREE.LineSegments(
      geometry,
      new THREE.LineBasicMaterial({ color: mint, transparent: true, opacity: 0.65 })
    )
    scene.add(web)
    for (let i = 0; i < 16; i++) {
      const a = (i * Math.PI) / 8,
        x = 10 * Math.cos(a),
        z = 10 * Math.sin(a)
      box(x, 3, z, 0.65, 8, 0.65)
      box(x + 0.34, 3, z, 0.025, 7, 0.7, i % 3 ? green : purple)
      const arch = new THREE.Group()
      arch.position.set(x, 6.5, z)
      arch.rotation.y = -a
      box(-2, 0, 0, 4.8, 0.32, 0.5, dark, arch)
      box(-2, -0.2, 0, 4.8, 0.025, 0.52, i % 3 ? purple : green, arch)
      scene.add(arch)
      box(8 * Math.cos(a), -1.5, 8 * Math.sin(a), 0.4, 3, 0.4)
      box(6 * Math.cos(a), -0.4, 6 * Math.sin(a), 2.8, 0.25, 0.12)
      const peg = box(4.8 * Math.cos(a), 0.28, 4.8 * Math.sin(a), 0.08, 0.7, 0.08, amber)
      animated.push(peg)
    }
    // Broken upper rings and distant city slabs frame the open observatory.
    for (let i = 0; i < 30; i++) {
      const a = i * 2.39996,
        r = 17 + (i % 5) * 2
      box(r * Math.cos(a), -2 + (i % 7), r * Math.sin(a), 1.4, 5 + (i % 8) * 2, 1.8, side)
      box(
        r * Math.cos(a) + 0.72,
        1 + (i % 7),
        r * Math.sin(a),
        0.03,
        1.6,
        0.9,
        i % 4 ? purple : amber
      )
    }
    tether = line(
      [
        [0, 0.1, 0],
        [6, 0.3, 0]
      ],
      gold,
      0.8
    )
  } else {
    // Deep layered machinery: each level has a different opening and live shutter.
    for (let level = 0; level < 15; level++) {
      const y = 14 - level * 4
      const group = new THREE.Group()
      group.position.y = y
      group.rotation.y = ((level % 3) - 1) * 0.12
      for (let wall = 0; wall < 4; wall++) {
        const panel = new THREE.Group()
        panel.rotation.y = (wall * Math.PI) / 2
        box(0, 0, -5, 10, 0.35, 0.75, dark, panel)
        box(0, 0.2, -4.6, 9, 0.035, 0.035, level % 3 ? green : purple, panel)
        box(-4.65, -1.8, -5, 0.55, 4.2, 1, side, panel)
        box(-4.3, -1.5, -4.8, 0.025, 2.1, 0.08, level % 4 ? purple : amber, panel)
        box(2, -1.5, -5.3, 2.3, 1.4, 0.7, dark, panel)
        group.add(panel)
      }
      scene.add(group)
      const shutter = box(0, y - 0.6, -4.2, 5, 0.09, 1.4, side)
      animated.push(shutter)
      if (level % 2 === 0) {
        const lamp = new THREE.PointLight(level % 4 ? violet : mint, 18, 10, 1.7)
        lamp.position.set(level % 4 ? -3.8 : 3.8, y, 1)
        scene.add(lamp)
      }
    }
    // Long uninterrupted uprights make the changing height legible.
    for (const x of [-5, 5])
      for (const z of [-5, 5]) {
        box(x, -14, z, 0.7, 64, 0.7)
        box(x - 0.36, -14, z, 0.035, 64, 0.18, purple)
      }
    const bottom = box(0, -46, 0, 10, 0.2, 10)
    bottom.material = side
    tether = line(
      [
        [0, 12, 0],
        [0, 4.7, 0]
      ],
      mint,
      0.9
    )
  }
  let seed = 41417
  const random = () => {
    seed = (seed * 1664525 + 1013904223) >>> 0
    return seed / 4294967296
  }
  const dustBase = Array.from({ length: 260 }, () => [
    (random() - 0.5) * 30,
    fall ? random() * 64 - 46 : random() * 16 - 4,
    (random() - 0.5) * 30,
    random() * Math.PI * 2
  ])
  const dustGeometry = new THREE.BufferGeometry()
  const dustArray = new Float32Array(dustBase.length * 3)
  dustGeometry.setAttribute("position", new THREE.BufferAttribute(dustArray, 3))
  scene.add(
    new THREE.Points(
      dustGeometry,
      new THREE.PointsMaterial({
        color: mint,
        size: 0.035,
        transparent: true,
        opacity: 0.45,
        sizeAttenuation: true
      })
    )
  )
  const gltf = await new GLTFLoader().loadAsync("../../aranea-spider.glb")
  const spider = new THREE.Group()
  gltf.scene.scale.setScalar(0.65)
  spider.add(gltf.scene)
  scene.add(spider)
  const mixer = new THREE.AnimationMixer(gltf.scene)
  const idle = mixer.clipAction(THREE.AnimationClip.findByName(gltf.animations, "Idle")).play()
  const walk = mixer.clipAction(THREE.AnimationClip.findByName(gltf.animations, "Walk")).play()
  const hips = []
  gltf.scene.traverse((obj) => {
    if (obj.isBone && obj.name.endsWith("hip")) hips.push(obj)
  })
  function resize() {
    const w = Math.max(1, innerWidth),
      h = Math.max(1, innerHeight)
    renderer.setPixelRatio(Math.min(devicePixelRatio, 1.4, Math.sqrt(2100000 / (w * h))))
    renderer.setSize(w, h)
    camera.aspect = w / h
    camera.updateProjectionMatrix()
  }
  resize()
  addEventListener("resize", resize)
  const initial = options.has("time") && Number.isFinite(fixed) ? fixed : fall ? 17 : 22
  const start = performance.now()
  let previous = -Infinity,
    frames = 0
  function draw(now) {
    if (!still && now - previous < 1000 / 30 - 1) return
    previous = now
    const t = initial + (still ? 0 : (now - start) / 1000)
    const state = sample(t)
    idle.setEffectiveWeight(1 - state.walk)
    walk.setEffectiveWeight(state.walk)
    // Absolute ground distance synchronizes the walk cycle, even in deterministic stills.
    walk.time =
      (((state.distance / 0.22) % walk.getClip().duration) + walk.getClip().duration) %
      walk.getClip().duration
    idle.time = ((t % idle.getClip().duration) + idle.getClip().duration) % idle.getClip().duration
    mixer.update(0)
    if (fall)
      hips.forEach((bone, i) => {
        bone.rotation.x += 0.16
        bone.rotation.z += 0.025 * Math.sin(t * 0.7 + i)
      })
    spider.position.fromArray(state.position)
    spider.position.y -= 0.065
    spider.rotation.set(
      fall ? 0.025 * Math.sin(t * 0.6) : 0,
      state.heading,
      fall ? 0.05 * Math.sin(t * 0.8) : 0
    )
    camera.position.fromArray(state.camera)
    camera.lookAt(...state.target)
    key.position.set(state.position[0] + 4, state.position[1] + 8, state.position[2] + 5)
    key.target.position.fromArray(state.position)
    local.position.set(state.position[0] - 2, state.position[1] + 3, state.position[2] + 2)
    rim.position.set(state.position[0] + 3, state.position[1] + 1, state.position[2] - 3)
    const points = tether.geometry.attributes.position
    if (fall) {
      points.setXYZ(0, ...state.anchor)
      points.setXYZ(1, state.position[0], state.position[1] + 0.7, state.position[2])
      animated.forEach((shutter, i) => {
        shutter.position.x = 1.2 * Math.sin(t * 0.14 + i * 1.7)
        shutter.rotation.y = 0.12 * Math.sin(t * 0.1 + i)
      })
    } else {
      const angle = Math.atan2(state.position[2], state.position[0])
      points.setXYZ(0, 4.7 * Math.cos(angle), 0.14, 4.7 * Math.sin(angle))
      points.setXYZ(1, state.position[0], 0.35, state.position[2])
      const progress = state.progress
      const fade = Math.min(1, (1 - progress) * 18)
      web.material.opacity = (0.7 + 0.15 * Math.sin(t * 0.2)) * fade
      web.geometry.setDrawRange(0, Math.max(18, Math.floor(progress * 48) * 18))
      animated.forEach((peg, i) => {
        peg.scale.y = 0.7 + 0.05 * Math.sin(t * 0.4 + i)
      })
    }
    points.needsUpdate = true
    tether.geometry.computeBoundingSphere()
    dustBase.forEach((p, i) => {
      dustArray[i * 3] = p[0] + 0.18 * Math.sin(t * 0.12 + p[3])
      dustArray[i * 3 + 1] = p[1] + 0.4 * Math.sin(t * 0.1 + p[3])
      dustArray[i * 3 + 2] = p[2] + 0.18 * Math.cos(t * 0.15 + p[3])
    })
    dustGeometry.attributes.position.needsUpdate = true
    renderer.render(scene, camera)
    document.body.dataset.ready = "true"
    document.body.dataset.phase = state.phase
    document.body.dataset.frames = String(++frames)
    document.body.dataset.calls = String(renderer.info.render.calls)
  }
  draw(start)
  if (!still)
    renderer.setAnimationLoop((now) => {
      try {
        draw(now)
      } catch (error) {
        renderer.setAnimationLoop(null)
        failure(error)
      }
    })
  addEventListener(
    "pagehide",
    () => {
      renderer.setAnimationLoop(null)
      environment.dispose()
      renderer.dispose()
    },
    { once: true }
  )
} catch (error) {
  failure(error)
}
