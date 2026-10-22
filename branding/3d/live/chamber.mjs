import * as THREE from "three"
import { detailTexture } from "../collection/materials.mjs"
import { chamberBeat, writeChamberSignals } from "./journey.mjs"

// Build the chamber in scene order; the host animates these runtime handles.
export function createChamber(scene, random) {
  const stone = new THREE.MeshStandardMaterial({
    color: 0x182024,
    roughness: 0.64,
    metalness: 0.55
  })
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
  const grain = detailTexture(THREE, "stone", 8181)
  grain.repeat.set(2, 2)
  stone.roughnessMap = grain
  stone.bumpMap = grain
  stone.bumpScale = 0.065
  const metalGrain = detailTexture(THREE, "metal", 28)
  metalGrain.repeat.set(3, 3)
  dark.roughnessMap = metalGrain
  dark.bumpMap = metalGrain
  dark.bumpScale = 0.035
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
  // Relief seams and suspended silk collectors are batched into two draws.
  const detailGeometry = new THREE.BoxGeometry(1, 1, 1)
  const matrix = new THREE.Object3D()
  const fittings = new THREE.InstancedMesh(detailGeometry, dark, 168)
  for (let i = 0; i < fittings.count; i++) {
    const side = i % 2 ? 1 : -1,
      slab = Math.floor(i / 2) % 14
    const level = Math.floor(i / 28) % 2 ? -3 : 6
    const row = Math.floor(i / 56)
    matrix.position.set(side * (1.5 + row * 0.22), level + 0.015, -12.5 + slab * 2.25)
    matrix.scale.set(0.055, 0.04, 1.8 - row * 0.2)
    matrix.updateMatrix()
    fittings.setMatrixAt(i, matrix.matrix)
  }
  scene.add(fittings)
  const collectors = new THREE.InstancedMesh(new THREE.OctahedronGeometry(0.22, 0), violet, 36)
  collectors.instanceMatrix.setUsage(THREE.DynamicDrawUsage)
  collectors.frustumCulled = false
  scene.add(collectors)
  const collectorRings = []
  for (const side of [-1, 1]) {
    for (const z of [-12, 0, 12]) {
      const ring = new THREE.Mesh(new THREE.TorusGeometry(2.9, 0.045, 6, 64), mint)
      ring.position.set(side * 8, 8, z)
      scene.add(ring)
      collectorRings.push(ring)
    }
  }
  const carrierPositions = new Float32Array(224 * 3)
  const carrierGeometry = new THREE.BufferGeometry()
  carrierGeometry.setAttribute("position", new THREE.BufferAttribute(carrierPositions, 3))
  const carrierMaterial = new THREE.PointsMaterial({
    color: 0xb9ffe1,
    size: 0.065,
    transparent: true,
    opacity: 0.8,
    depthWrite: false,
    blending: THREE.AdditiveBlending
  })
  const carriers = new THREE.Points(carrierGeometry, carrierMaterial)
  carriers.frustumCulled = false
  scene.add(carriers)
  function updateChamber(time) {
    const beat = chamberBeat(time)
    writeChamberSignals(carrierPositions, time)
    carrierGeometry.attributes.position.needsUpdate = true
    carrierMaterial.opacity = 0.55 + 0.4 * beat.resonance
    collectorRings.forEach((ring, i) => {
      ring.rotation.y = 0.12 * Math.sin(time * 0.13 + i) + beat.resonance * 0.7
      ring.scale.setScalar(1 - 0.2 * beat.resonance)
    })
    for (let i = 0; i < collectors.count; i++) {
      const ring = collectorRings[Math.floor(i / 6)]
      const angle = (i / 6) * Math.PI * 2 + time * 0.08
      const radius = 2.9 - beat.resonance * 0.6
      matrix.position.set(
        ring.position.x + radius * Math.cos(angle),
        8 + radius * Math.sin(angle),
        ring.position.z + beat.resonance * Math.sin(angle) * 1.2
      )
      matrix.rotation.set(angle * 0.5, time * 0.15 + i, 0)
      matrix.scale.setScalar(1 + beat.resonance * 0.6)
      matrix.updateMatrix()
      collectors.setMatrixAt(i, matrix.matrix)
    }
    collectors.instanceMatrix.needsUpdate = true
    mint.emissiveIntensity = 2.3 + beat.resonance * 0.8
    violet.emissiveIntensity = 2 + beat.resonance * 1.2
  }
  return {
    updateChamber,
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
  }
}
