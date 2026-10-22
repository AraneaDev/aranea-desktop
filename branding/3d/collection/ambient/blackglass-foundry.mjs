import * as THREE from "three"
import { detailTexture } from "../materials.mjs"
import { expansionState, foundryParticleTravel } from "./expansion-motion.mjs"

export function createScene(scene, camera) {
  scene.fog = new THREE.FogExp2("#08090b", 0.017)
  scene.add(new THREE.HemisphereLight("#8e9fcb", "#101220", 2.2))
  const key = new THREE.DirectionalLight("#c4ceee", 3.8)
  key.position.set(-6, 18, 10)
  scene.add(key)
  const glow = new THREE.PointLight("#3bff9e", 330, 60)
  glow.position.set(0, 5, 0)
  scene.add(glow)
  const purpleLight = new THREE.PointLight("#7a5cff", 350, 65)
  purpleLight.position.set(7, 10, -9)
  scene.add(purpleLight)
  const map = detailTexture(THREE, "metal", 79)
  map.repeat.set(2, 3)
  const dark = new THREE.MeshStandardMaterial({
    color: "#465065",
    metalness: 0.88,
    roughness: 0.34,
    map,
    bumpMap: map,
    bumpScale: 0.025
  })
  const steel = new THREE.MeshStandardMaterial({
    color: "#738390",
    metalness: 0.85,
    roughness: 0.44,
    map
  })
  const sand = new THREE.MeshStandardMaterial({
    color: "#b79e6c",
    metalness: 0.75,
    roughness: 0.42,
    map
  })
  const mint = new THREE.MeshBasicMaterial({ color: "#3bff9e", toneMapped: false })
  const violet = new THREE.MeshBasicMaterial({ color: "#7a5cff", toneMapped: false })
  const fill = new THREE.DirectionalLight("#a4b6d7", 1.8)
  fill.position.set(9, 8, 17)
  scene.add(fill)
  const root = new THREE.Group()
  scene.add(root)
  const platform = new THREE.Mesh(new THREE.CylinderGeometry(14, 15, 1.5, 64), dark)
  platform.position.y = -3.7
  root.add(platform)
  const mechanism = []
  const dummy = new THREE.Object3D()
  for (let layer = 0; layer < 5; layer++) {
    const group = new THREE.Group()
    group.position.y = -2 + layer * 2.65
    group.add(new THREE.Mesh(new THREE.TorusGeometry(5.3, 0.32, 10, 96), layer % 2 ? steel : dark))
    group.rotation.x = 0
    // Machine rings lie horizontally; the cartridge plates orbit vertically above them.
    group.children[0].rotation.x = Math.PI / 2
    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(4.84, 0.045, 6, 96),
      layer % 2 ? violet : mint
    )
    ring.rotation.x = Math.PI / 2
    group.add(ring)
    const teeth = new THREE.InstancedMesh(
      new THREE.BoxGeometry(0.62, 0.55, 1.0),
      layer % 2 ? dark : steel,
      48
    )
    for (let i = 0; i < 48; i++) {
      const a = (i * Math.PI) / 24
      dummy.position.set(Math.cos(a) * 5.6, 0, Math.sin(a) * 5.6)
      dummy.rotation.set(0, -a, 0)
      dummy.updateMatrix()
      teeth.setMatrixAt(i, dummy.matrix)
    }
    group.add(teeth)
    root.add(group)
    mechanism.push(group)
  }
  const columns = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.36, 0.45, 16, 12), dark, 8)
  const collars = new THREE.InstancedMesh(
    new THREE.CylinderGeometry(0.66, 0.66, 0.22, 16),
    sand,
    64
  )
  for (let i = 0; i < 8; i++) {
    const a = (i * Math.PI) / 4
    dummy.position.set(Math.cos(a) * 9.3, 3.7, Math.sin(a) * 9.3)
    dummy.rotation.set(0, 0, 0)
    dummy.updateMatrix()
    columns.setMatrixAt(i, dummy.matrix)
    for (let j = 0; j < 8; j++) {
      dummy.position.y = -3 + j * 2
      dummy.updateMatrix()
      collars.setMatrixAt(i * 8 + j, dummy.matrix)
    }
  }
  root.add(columns, collars)
  const panels = new THREE.InstancedMesh(new THREE.BoxGeometry(1.35, 1.8, 0.48), dark, 36)
  const seams = new THREE.InstancedMesh(new THREE.BoxGeometry(1.0, 0.045, 0.5), mint, 36)
  root.add(panels, seams)
  const core = new THREE.Mesh(
    new THREE.CylinderGeometry(1.15, 1.15, 13.3, 32, 1, true),
    new THREE.MeshBasicMaterial({
      color: "#3bff9e",
      transparent: true,
      opacity: 0.23,
      side: THREE.DoubleSide,
      depthWrite: false
    })
  )
  core.position.y = 3.3
  root.add(core)
  const cage = new THREE.Mesh(
    new THREE.CylinderGeometry(1.6, 1.6, 13.7, 12, 8, true),
    new THREE.MeshBasicMaterial({
      color: "#7a5cff",
      wireframe: true,
      transparent: true,
      opacity: 0.22
    })
  )
  cage.position.y = 3.3
  root.add(cage)
  const molten = new THREE.InstancedMesh(new THREE.OctahedronGeometry(0.18, 0), mint, 220)
  root.add(molten)
  const circuit = new THREE.InstancedMesh(new THREE.BoxGeometry(0.055, 0.04, 4), violet, 48)
  for (let i = 0; i < 48; i++) {
    const a = (i * Math.PI) / 24
    dummy.position.set(Math.cos(a) * 10.3, -2.91, Math.sin(a) * 10.3)
    dummy.rotation.set(0, Math.PI / 2 - a, 0)
    dummy.updateMatrix()
    circuit.setMatrixAt(i, dummy.matrix)
  }
  root.add(circuit)
  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(150, 150),
    new THREE.MeshStandardMaterial({
      color: "#0b1018",
      roughness: 0.5,
      metalness: 0.55,
      map: detailTexture(THREE, "stone", 8)
    })
  )
  floor.rotation.x = -Math.PI / 2
  floor.position.y = -4.5
  scene.add(floor)
  // Repeating structural bays anchor the reactor in a deep industrial hall.
  const vault = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), dark, 60)
  const lamps = new THREE.InstancedMesh(new THREE.BoxGeometry(0.07, 1, 0.07), violet, 20)
  let count = 0
  for (let bay = 0; bay < 5; bay++) {
    const z = -18 - bay * 10
    for (const side of [-1, 1]) {
      dummy.position.set(side * 20, 8, z)
      dummy.rotation.set(0, 0, 0)
      dummy.scale.set(1.2, 26, 1.5)
      dummy.updateMatrix()
      vault.setMatrixAt(count++, dummy.matrix)
      dummy.position.set(side * 17, 20, z)
      dummy.rotation.z = side * 0.6
      dummy.scale.set(1, 8, 1.2)
      dummy.updateMatrix()
      vault.setMatrixAt(count++, dummy.matrix)
      dummy.position.set(side * 20, 1, z)
      dummy.rotation.set(0, 0, 0)
      dummy.scale.set(2.8, 0.45, 9)
      dummy.updateMatrix()
      vault.setMatrixAt(count++, dummy.matrix)
      dummy.position.set(side * 19.3, 9, z + 0.8)
      dummy.scale.set(1, 16, 1)
      dummy.updateMatrix()
      lamps.setMatrixAt(bay * 4 + (side === 1 ? 2 : 0), dummy.matrix)
      dummy.position.set(side * 17, 19, z + 0.8)
      dummy.rotation.z = side * 0.6
      dummy.scale.set(1, 7, 1)
      dummy.updateMatrix()
      lamps.setMatrixAt(bay * 4 + (side === 1 ? 3 : 1), dummy.matrix)
    }
    for (let rail = 0; rail < 6; rail++) {
      dummy.position.set(-15 + rail * 6, 22, z)
      dummy.rotation.set(0, 0, 0)
      dummy.scale.set(0.45, 0.7, 10)
      dummy.updateMatrix()
      vault.setMatrixAt(count++, dummy.matrix)
    }
  }
  scene.add(vault, lamps)
  const conduits = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.24, 0.24, 62, 10), steel, 8)
  for (let i = 0; i < 8; i++) {
    dummy.position.set((i % 2 ? 1 : -1) * (16 + (i % 4) * 0.7), -2.9 + Math.floor(i / 4) * 0.7, -19)
    dummy.rotation.set(Math.PI / 2, 0, 0)
    dummy.scale.setScalar(1)
    dummy.updateMatrix()
    conduits.setMatrixAt(i, dummy.matrix)
  }
  scene.add(conduits)
  const spark = new THREE.InstancedMesh(new THREE.BoxGeometry(0.025, 0.32, 0.025), mint, 100)
  scene.add(spark)
  const steam = new THREE.InstancedMesh(
    new THREE.IcosahedronGeometry(0.7, 1),
    new THREE.MeshBasicMaterial({
      color: "#739d9d",
      transparent: true,
      opacity: 0.035,
      depthWrite: false
    }),
    32
  )
  scene.add(steam)
  return (time) => {
    const { overload } = expansionState(time)
    for (let i = 0; i < 100; i++) {
      const age = (((time * 0.19 + i * 0.073) % 1) + 1) % 1,
        a = i * 2.399
      dummy.position.set(
        Math.cos(a) * (2 + age * 7),
        9 + age * 6 - age * age * 13,
        Math.sin(a) * (2 + age * 7)
      )
      dummy.rotation.set(Math.sin(a) * age, 0, Math.cos(a) * age)
      dummy.scale.setScalar((1 - age) * (0.35 + overload * 0.9))
      dummy.updateMatrix()
      spark.setMatrixAt(i, dummy.matrix)
    }
    spark.instanceMatrix.needsUpdate = true
    for (let i = 0; i < 32; i++) {
      const age = (((time * 0.055 + i * 0.071) % 1) + 1) % 1,
        a = i * 2.399
      dummy.position.set(Math.cos(a) * (7 + age * 3), -1 + age * 15, Math.sin(a) * (7 + age * 3))
      dummy.rotation.set(age, i, 0)
      dummy.scale.set(1 + age * 2, 1.3 + age * 3, 1 + age * 2)
      dummy.updateMatrix()
      steam.setMatrixAt(i, dummy.matrix)
    }
    steam.instanceMatrix.needsUpdate = true
    dummy.scale.setScalar(1)
    mechanism.forEach((group, i) => {
      group.rotation.y = time * (i % 2 ? -0.1 : 0.075) + i * 0.3
      group.position.y = -2 + i * 2.65 + Math.sin(time * 0.5 + i) * 0.12 + overload * (i - 2) * 0.65
    })
    for (let i = 0; i < 36; i++) {
      const row = Math.floor(i / 6),
        a = ((i % 6) * Math.PI) / 3 + time * (row % 2 ? -0.16 : 0.12)
      const radius = 2.7 + overload * (2 + row * 0.45)
      dummy.position.set(
        Math.cos(a) * radius,
        -2 + row * 2 + Math.sin(time * 0.7 + i) * overload * 0.7,
        Math.sin(a) * radius
      )
      dummy.rotation.set(
        overload * Math.sin(i + time * 0.3) * 0.45,
        -a + Math.PI / 2,
        overload * 0.3
      )
      dummy.updateMatrix()
      panels.setMatrixAt(i, dummy.matrix)
      seams.setMatrixAt(i, dummy.matrix)
    }
    panels.instanceMatrix.needsUpdate = true
    seams.instanceMatrix.needsUpdate = true
    for (let i = 0; i < 220; i++) {
      const a = i * 2.399 + time * 0.2,
        r = 0.35 + (i % 13) * 0.058 + overload * 0.7
      dummy.position.set(
        Math.cos(a) * r,
        (((foundryParticleTravel(time, i) % 13) + 13) % 13) - 3,
        Math.sin(a) * r
      )
      dummy.rotation.set(time * 0.3 + i, a, i)
      dummy.scale.setScalar(0.4 + (i % 7) * 0.12)
      dummy.updateMatrix()
      molten.setMatrixAt(i, dummy.matrix)
    }
    dummy.scale.setScalar(1)
    molten.instanceMatrix.needsUpdate = true
    core.scale.set(1 + overload * 0.6, 1, 1 + overload * 0.6)
    cage.rotation.y = -time * 0.13
    glow.intensity = 300 + overload * 170 + Math.sin(time * 0.9) * 25
    const orbit = time * 0.028
    camera.position.set(
      Math.sin(orbit + 0.7) * 29,
      15 + Math.sin(time * 0.055) * 2,
      Math.cos(orbit + 0.7) * 29
    )
    camera.lookAt(0, 3, 0)
  }
}
