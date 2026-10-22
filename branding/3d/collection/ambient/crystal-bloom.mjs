import * as THREE from "three"
import { detailTexture } from "../materials.mjs"
import { expansionState, crystalTwist } from "./expansion-motion.mjs"

export function createScene(scene, camera) {
  scene.fog = new THREE.FogExp2("#08090b", 0.018)
  scene.add(new THREE.HemisphereLight("#a7bded", "#18252b", 2))
  const key = new THREE.DirectionalLight("#c5ffe6", 4)
  key.position.set(-9, 15, 8)
  scene.add(key)
  const mintLight = new THREE.PointLight("#3bff9e", 240, 45)
  mintLight.position.set(-4, 4, 2)
  const violetLight = new THREE.PointLight("#7a5cff", 290, 45)
  violetLight.position.set(6, 7, -4)
  scene.add(mintLight, violetLight)
  const texture = detailTexture(THREE, "crystal", 117)
  const mineral = new THREE.MeshStandardMaterial({
    color: "#c1ffec",
    roughnessMap: texture,
    vertexColors: true,
    emissive: "#092c27",
    emissiveIntensity: 0.7,
    bumpMap: texture,
    bumpScale: 0.008,
    roughness: 0.325,
    metalness: 0.43,
    flatShading: true
  })
  const amethyst = new THREE.MeshStandardMaterial({
    color: "#c1afff",
    roughnessMap: texture,
    vertexColors: true,
    emissive: "#092c27",
    emissiveIntensity: 0.7,
    bumpMap: texture,
    bumpScale: 0.008,
    roughness: 0.32,
    metalness: 0.46,
    flatShading: true
  })
  const stone = new THREE.MeshStandardMaterial({
    color: "#222b36",
    map: detailTexture(THREE, "stone", 49),
    roughness: 0.87,
    flatShading: true
  })
  const gold = new THREE.MeshStandardMaterial({
    color: "#c4af80",
    metalness: 0.65,
    roughness: 0.47
  })
  const mint = new THREE.MeshBasicMaterial({ color: "#3bff9e", toneMapped: false })
  const violet = new THREE.MeshBasicMaterial({ color: "#7a5cff", toneMapped: false })
  const garden = new THREE.Group()
  scene.add(garden)
  const island = new THREE.Mesh(new THREE.IcosahedronGeometry(11, 1), stone)
  island.scale.set(1.2, 0.18, 0.95)
  island.position.y = -2.4
  garden.add(island)
  // A six-sided terminated mineral: full opaque facets avoid expensive glass sorting.
  const shape = new THREE.LatheGeometry(
    [
      new THREE.Vector2(0, -0.5),
      new THREE.Vector2(0.48, -0.33),
      new THREE.Vector2(0.48, 0.27),
      new THREE.Vector2(0, 0.65)
    ],
    6
  )
  const colors = []
  const position = shape.attributes.position
  for (let i = 0; i < position.count; i++) {
    const y = position.getY(i),
      color = new THREE.Color("#324b5c")
    if (y > 0.26) color.set("#9c6fff")
    else if (y > -0.34) color.set("#55d8b1")
    colors.push(...color.toArray())
  }
  shape.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3))
  const crystals = new THREE.InstancedMesh(shape, mineral, 160)
  const purpleCrystals = new THREE.InstancedMesh(shape, amethyst, 100)
  garden.add(crystals, purpleCrystals)
  const seeds = []
  for (let i = 0; i < 260; i++) {
    const a = i * 2.399963,
      r = Math.sqrt(i / 260) * 9.9
    seeds.push({
      a,
      r,
      x: Math.cos(a) * r,
      z: Math.sin(a) * r * 0.78,
      height: 1.0 + 5.2 * (1 - r / 12) * (0.45 + ((i * 31) % 97) / 97),
      tilt: 0.08 + r * 0.043
    })
  }
  const veins = new THREE.LineSegments(
    new THREE.BufferGeometry(),
    new THREE.LineBasicMaterial({ color: "#3bff9e", transparent: true, opacity: 0.36 })
  )
  const veinPositions = []
  for (let branch = 0; branch < 42; branch++) {
    const a = branch * 2.399963
    for (let j = 0; j < 7; j++) {
      const r = 1 + j * 1.25
      veinPositions.push(
        Math.cos(a + j * 0.1) * r,
        -0.62 + Math.sin(j) * 0.05,
        Math.sin(a + j * 0.1) * r * 0.8,
        Math.cos(a + (j + 1) * 0.1) * (r + 1.25),
        -0.62 + Math.sin(j + 1) * 0.05,
        Math.sin(a + (j + 1) * 0.1) * (r + 1.25) * 0.8
      )
    }
  }
  veins.geometry.setAttribute("position", new THREE.Float32BufferAttribute(veinPositions, 3))
  garden.add(veins)
  const stamens = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.045, 0.085, 1, 6), gold, 48)
  const tips = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.13, 0), mint, 48)
  garden.add(stamens, tips)
  const central = new THREE.Group()
  central.position.y = 1.8
  garden.add(central)
  const heart = new THREE.Mesh(
    new THREE.OctahedronGeometry(1.65, 0),
    new THREE.MeshStandardMaterial({
      color: "#92ffe0",
      emissive: "#14764d",
      emissiveIntensity: 0.6,
      metalness: 0.45,
      roughness: 0.24
    })
  )
  central.add(heart)
  const heartFrame = new THREE.LineSegments(
    new THREE.EdgesGeometry(heart.geometry),
    new THREE.LineBasicMaterial({ color: "#3bff9e", transparent: true, opacity: 0.8 })
  )
  central.add(heartFrame)
  const petals = new THREE.InstancedMesh(shape, amethyst, 18)
  central.add(petals)
  const shards = new THREE.InstancedMesh(new THREE.TetrahedronGeometry(0.16, 0), violet, 180)
  garden.add(shards)
  const dustPositions = []
  for (let i = 0; i < 800; i++) {
    const a = i * 2.399963,
      r = 12 + (i % 21)
    dustPositions.push(Math.cos(a) * r, -0.8 + ((i * 17) % 100) * 0.13, Math.sin(a) * r)
  }
  const dust = new THREE.Points(
    new THREE.BufferGeometry().setAttribute(
      "position",
      new THREE.Float32BufferAttribute(dustPositions, 3)
    ),
    new THREE.PointsMaterial({ color: "#afa0dc", size: 0.045, transparent: true, opacity: 0.45 })
  )
  scene.add(dust)
  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(140, 140),
    new THREE.MeshStandardMaterial({
      color: "#0b1419",
      roughness: 0.64,
      metalness: 0.35,
      map: detailTexture(THREE, "stone", 12)
    })
  )
  floor.rotation.x = -Math.PI / 2
  floor.position.y = -4.4
  scene.add(floor)
  const dummy = new THREE.Object3D()
  return (time) => {
    const { bloom, shatter } = expansionState(time)
    for (let i = 0; i < 260; i++) {
      const seed = seeds[i],
        growth = 0.86 + Math.sin(time * 0.21 - seed.r * 0.4) * 0.08 + bloom * 0.25
      const lift = shatter * (0.4 + (i % 17) * 0.4)
      dummy.position.set(
        seed.x * (1 + shatter * 0.35),
        -0.45 + seed.height * growth * 0.42 + lift,
        seed.z * (1 + shatter * 0.35)
      )
      dummy.rotation.set(
        Math.sin(seed.a) * seed.tilt + shatter * Math.sin(i) * 0.38,
        seed.a + crystalTwist(time, i),
        Math.cos(seed.a) * seed.tilt + shatter * Math.cos(i) * 0.38
      )
      dummy.scale.set(0.36 + seed.height * 0.12, seed.height * growth, 0.36 + seed.height * 0.12)
      dummy.updateMatrix()
      ;(i < 160 ? crystals : purpleCrystals).setMatrixAt(i < 160 ? i : i - 160, dummy.matrix)
    }
    crystals.instanceMatrix.needsUpdate = true
    purpleCrystals.instanceMatrix.needsUpdate = true
    for (let i = 0; i < 48; i++) {
      const a = i * 2.399963 + time * 0.025,
        r = 5 + (i % 7) * 0.65,
        h = 1.3 + Math.sin(i * 4) * 0.5 + bloom
      dummy.position.set(Math.cos(a) * r, h / 2 - 0.6, Math.sin(a) * r * 0.8)
      dummy.rotation.set(Math.sin(a) * 0.2, a, Math.cos(a) * 0.2)
      dummy.scale.set(1, h, 1)
      dummy.updateMatrix()
      stamens.setMatrixAt(i, dummy.matrix)
      dummy.position.y += h / 2
      dummy.scale.setScalar(1)
      dummy.updateMatrix()
      tips.setMatrixAt(i, dummy.matrix)
    }
    stamens.instanceMatrix.needsUpdate = true
    tips.instanceMatrix.needsUpdate = true
    for (let i = 0; i < 18; i++) {
      const a = (i / 18) * Math.PI * 2 + time * 0.07,
        r = 1.8 + bloom * 1.7 + shatter * 1.8
      dummy.position.set(Math.cos(a) * r, Math.sin(i * 2) * 0.4 + bloom * 0.5, Math.sin(a) * r)
      dummy.rotation.set(Math.sin(a) * (0.75 + bloom), a, Math.cos(a) * (0.75 + bloom))
      dummy.scale.set(0.8, 2.8 + bloom, 0.8)
      dummy.updateMatrix()
      petals.setMatrixAt(i, dummy.matrix)
    }
    petals.instanceMatrix.needsUpdate = true
    for (let i = 0; i < 180; i++) {
      const a = i * 2.399963 + time * 0.07,
        r = 2 + (i % 23) * 0.32 + shatter * 5
      dummy.position.set(
        Math.cos(a) * r,
        1.3 + ((((i * 0.17 + time * 0.12) % 6) + 6) % 6) + shatter * Math.sin(i) * 2,
        Math.sin(a) * r * 0.8
      )
      dummy.rotation.set(a, i + time * 0.15, a)
      dummy.scale.setScalar(0.2 + (i % 7) * 0.07 + shatter * 0.5)
      dummy.updateMatrix()
      shards.setMatrixAt(i, dummy.matrix)
    }
    shards.instanceMatrix.needsUpdate = true
    heart.rotation.set(time * 0.12, time * 0.18, 0.1)
    heartFrame.rotation.copy(heart.rotation)
    central.position.y = 4.5 + Math.sin(time * 0.4) * 0.25 + bloom * 1.3
    dust.rotation.y = -time * 0.012
    violetLight.position.set(Math.cos(time * 0.1) * 8, 6, Math.sin(time * 0.1) * 8)
    mintLight.intensity = 220 + bloom * 120
    camera.position.set(18 + Math.sin(time * 0.035) * 4, 12 + Math.sin(time * 0.04) * 1.6, 23)
    camera.lookAt(0, 1, 0)
  }
}
