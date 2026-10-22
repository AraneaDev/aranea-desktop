import * as THREE from "three"
import { detailTexture } from "../materials.mjs"
import { expansionState } from "./expansion-motion.mjs"

export function createScene(scene, camera) {
  scene.fog = new THREE.FogExp2("#08090b", 0.008)
  scene.add(new THREE.HemisphereLight("#b7c9f8", "#080b15", 1.8))
  const key = new THREE.DirectionalLight("#b2ffde", 4)
  key.position.set(-12, 15, 12)
  scene.add(key)
  const rim = new THREE.PointLight("#7a5cff", 260, 80)
  rim.position.set(12, -2, -6)
  scene.add(rim)
  const fill = new THREE.DirectionalLight("#8e8bff", 2.3)
  fill.position.set(12, 5, 14)
  scene.add(fill)
  const nebula = new THREE.Mesh(
    new THREE.PlaneGeometry(1, 1),
    new THREE.ShaderMaterial({
      depthWrite: false,
      transparent: true,
      fog: false,
      uniforms: { time: { value: 0 } },
      vertexShader:
        "varying vec2 uv0;void main(){uv0=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}",
      fragmentShader: `varying vec2 uv0;uniform float time;
      void main(){vec2 p=uv0-.5;float haze=0.;float fine=0.;
      for(int i=0;i<5;i++){float n=float(i);float y=p.y+sin(p.x*5.+n*.67+time*.012)*.12+n*.028-.08;
      haze+=exp(-y*y*(65.+n*16.))*(.1+n*.012);fine+=exp(-y*y*1900.)*.028;}
      float edge=exp(-dot(p*vec2(.8,1.),p*vec2(.8,1.))*3.);
      vec3 c=mix(vec3(.12,.055,.28),vec3(.025,.22,.17),smoothstep(-.4,.4,p.x));
      gl_FragColor=vec4(c*(haze+fine)*edge,.85);
      #include <colorspace_fragment>
      }`
    })
  )
  scene.add(nebula)
  const trailPoints = []
  for (let ring = 0; ring < 4; ring++)
    for (let j = 0; j < 240; j++) {
      const a = (j / 240) * Math.PI * 2,
        b = ((j + 1) / 240) * Math.PI * 2,
        r = 19 + ring * 4
      trailPoints.push(
        Math.cos(a) * r,
        Math.sin(a) * r * 0.32 - 2,
        -10 + Math.sin(a) * 3,
        Math.cos(b) * r,
        Math.sin(b) * r * 0.32 - 2,
        -10 + Math.sin(b) * 3
      )
    }
  const trails = new THREE.LineSegments(
    new THREE.BufferGeometry().setAttribute(
      "position",
      new THREE.Float32BufferAttribute(trailPoints, 3)
    ),
    new THREE.LineBasicMaterial({ color: "#7a5cff", transparent: true, opacity: 0.15 })
  )
  scene.add(trails)
  const texture = detailTexture(THREE, "metal", 31)
  texture.repeat.set(3, 2)
  const metal = new THREE.MeshStandardMaterial({
    color: "#82969e",
    metalness: 0.88,
    roughness: 0.48,
    map: texture,
    bumpMap: texture,
    bumpScale: 0.025
  })
  const violet = new THREE.MeshStandardMaterial({
    color: "#41336c",
    metalness: 0.75,
    roughness: 0.3,
    map: texture
  })
  const mint = new THREE.MeshBasicMaterial({ color: "#3bff9e", toneMapped: false })
  const sand = new THREE.MeshStandardMaterial({
    color: "#b99d66",
    metalness: 0.7,
    roughness: 0.42,
    map: texture
  })
  const loom = new THREE.Group()
  loom.rotation.set(0.3, 0, -0.32)
  scene.add(loom)
  const core = new THREE.Mesh(new THREE.IcosahedronGeometry(4.1, 4), metal)
  loom.add(core)
  const coreGrid = new THREE.LineSegments(
    new THREE.WireframeGeometry(new THREE.IcosahedronGeometry(4.14, 2)),
    new THREE.LineBasicMaterial({ color: "#7a5cff", transparent: true, opacity: 0.29 })
  )
  loom.add(coreGrid)
  const rings = []
  for (let i = 0; i < 7; i++) {
    const group = new THREE.Group()
    group.rotation.set(i * 0.42, i * 0.29, i * 0.31)
    const radius = 6 + i * 0.94
    group.add(
      new THREE.Mesh(
        new THREE.TorusGeometry(radius, i % 2 ? 0.09 : 0.16, 8, 160),
        i % 3 === 0 ? sand : metal
      )
    )
    const light = new THREE.Mesh(
      new THREE.TorusGeometry(radius + 0.2, 0.018, 4, 160),
      i % 2 ? mint : new THREE.MeshBasicMaterial({ color: "#7a5cff", toneMapped: false })
    )
    group.add(light)
    const ticks = new THREE.InstancedMesh(
      new THREE.BoxGeometry(0.065, 0.38, 0.12),
      i % 2 ? violet : sand,
      96
    )
    const dummy = new THREE.Object3D()
    for (let j = 0; j < 96; j++) {
      const a = (j / 96) * Math.PI * 2
      dummy.position.set(Math.cos(a) * radius, Math.sin(a) * radius, 0)
      dummy.rotation.z = a - Math.PI / 2
      dummy.updateMatrix()
      ticks.setMatrixAt(j, dummy.matrix)
    }
    group.add(ticks)
    const moon = new THREE.Mesh(
      new THREE.SphereGeometry(0.35 + i * 0.055, 16, 12),
      i % 2 ? violet : sand
    )
    group.add(moon)
    loom.add(group)
    rings.push({ group, moon, radius })
  }
  const threadPositions = new Float32Array(160 * 3 * 2)
  const threads = new THREE.LineSegments(
    new THREE.BufferGeometry().setAttribute(
      "position",
      new THREE.BufferAttribute(threadPositions, 3)
    ),
    new THREE.LineBasicMaterial({
      color: "#3bff9e",
      transparent: true,
      opacity: 0.24,
      blending: THREE.AdditiveBlending
    })
  )
  loom.add(threads)
  const beads = new THREE.InstancedMesh(new THREE.SphereGeometry(0.055, 6, 4), mint, 160)
  loom.add(beads)
  const dummy = new THREE.Object3D()
  const starPositions = []
  for (let i = 0; i < 1400; i++) {
    const a = i * 2.399963,
      r = 25 + ((i * 31) % 100) * 0.63
    starPositions.push(Math.cos(a) * r, Math.sin(a) * r * 0.65, -18 - (i % 70))
  }
  scene.add(
    new THREE.Points(
      new THREE.BufferGeometry().setAttribute(
        "position",
        new THREE.Float32BufferAttribute(starPositions, 3)
      ),
      new THREE.PointsMaterial({ color: "#afa4da", size: 0.065, transparent: true, opacity: 0.65 })
    )
  )
  const eclipse = new THREE.Mesh(
    new THREE.SphereGeometry(3.94, 48, 32),
    new THREE.MeshStandardMaterial({ color: "#080b13", metalness: 0.35, roughness: 0.8 })
  )
  loom.add(eclipse)
  return (time) => {
    const state = expansionState(time)
    nebula.material.uniforms.time.value = time
    trails.rotation.z = Math.sin(time * 0.025) * 0.08
    loom.rotation.y = time * 0.045
    core.rotation.y = -time * 0.075
    coreGrid.rotation.copy(core.rotation)
    rings.forEach(({ group, moon, radius }, i) => {
      group.rotation.x = i * 0.42 + Math.sin(time * 0.1 + i) * 0.18 + state.eclipse * (i - 3) * 0.11
      group.rotation.y = i * 0.29 + time * (i % 2 ? -0.024 : 0.033)
      const a = time * (0.11 + i * 0.012) + i * 1.9
      moon.position.set(Math.cos(a) * radius, Math.sin(a) * radius, 0)
    })
    for (let i = 0; i < 160; i++) {
      const a = (i / 160) * Math.PI * 2 + time * 0.04
      const b = a * 3 + time * 0.16
      const r = 10.8 - state.eclipse * 2.5
      const p = [Math.cos(a) * r, Math.sin(a) * r, Math.sin(b) * (2 + state.eclipse * 3)]
      const q = [Math.cos(a + 1.3) * 5.1, Math.sin(a + 1.3) * 5.1, Math.cos(b) * 2]
      threadPositions.set(p, i * 6)
      threadPositions.set(q, i * 6 + 3)
      const f = (((time * 0.13 + i * 0.017) % 1) + 1) % 1
      dummy.position.set(...p.map((v, j) => v * (1 - f) + q[j] * f))
      dummy.updateMatrix()
      beads.setMatrixAt(i, dummy.matrix)
    }
    threads.geometry.attributes.position.needsUpdate = true
    beads.instanceMatrix.needsUpdate = true
    eclipse.position.set((1 - state.eclipse) * 14, 0.3, 4.5)
    camera.position.set(
      18.7 + Math.sin(time * 0.032) * 2.55,
      8.5 + Math.sin(time * 0.047) * 1.7,
      24.65
    )
    camera.lookAt(0, 0, 0)
    // Camera-facing, overscanned background retains full coverage at every aspect.
    const distance = 150
    const height = 2 * distance * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * 1.2
    nebula.position.set(0, 0, -distance).applyQuaternion(camera.quaternion).add(camera.position)
    nebula.quaternion.copy(camera.quaternion)
    nebula.scale.set(height * camera.aspect, height, 1)
  }
}
