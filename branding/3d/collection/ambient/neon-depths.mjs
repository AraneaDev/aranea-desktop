import * as THREE from "three"
import { mergeGeometries } from "../../live/vendor/addons/utils/BufferGeometryUtils.js"
import { cityDepth } from "./motion.mjs"
export function createScene(scene, camera) {
  scene.fog = new THREE.FogExp2("#08090b", 0.018)
  const palette = ["#3bff9e", "#7a5cff", "#3bff9e", "#7a5cff", "#e6c98a"]
  const dark = new THREE.MeshBasicMaterial({ color: "#0b151a" })
  const blocks = []
  // Twenty-four repeating depth slices keep the architecture continuous at any time.
  for (let row = 0; row < 24; row++) {
    const slice = new THREE.Group()
    for (let side = -1; side <= 1; side += 2)
      for (let lane = 0; lane < 3; lane++) {
        const n = row * 6 + lane * 2 + (side + 1) / 2
        const height = 13 + ((n * 37) % 29),
          width = 4 + ((n * 13) % 4),
          depth = 6 + ((n * 7) % 4)
        const building = new THREE.Group()
        building.position.set(side * (10 + lane * 10), height / 2 - 9, 0)
        const geometry = new THREE.BoxGeometry(width, height, depth)
        building.add(new THREE.Mesh(geometry, dark))
        const glow = new THREE.LineSegments(
          new THREE.EdgesGeometry(geometry),
          new THREE.LineBasicMaterial({ color: palette[n % 5], transparent: true, opacity: 0.42 })
        )
        building.add(glow)
        const railMaterial = new THREE.MeshBasicMaterial({ color: palette[n % 5] })
        for (const z of [-depth / 2, depth / 2]) {
          const rail = new THREE.Mesh(new THREE.BoxGeometry(0.1, height, 0.1), railMaterial)
          rail.position.set(-side * (width / 2 + 0.03), 0, z)
          building.add(rail)
        }
        if (n % 3 === 0) {
          const sign = new THREE.Mesh(new THREE.BoxGeometry(0.12, 2.6, 1.4), railMaterial)
          sign.position.set(-side * (width / 2 + 0.1), height * 0.24, 0)
          building.add(sign)
        }
        // Fine window banks, inset into the front face; one draw call per building.
        const windows = []
        for (let y = -height / 2 + 1; y < height / 2 - 1; y += 1.4)
          for (let x = -width / 2 + 0.5; x < width / 2 - 0.3; x += 0.85) {
            if ((Math.floor(y * 10) + n * 3 + Math.floor(x * 10)) % 4 === 0) continue
            windows.push(x - 0.16, y, depth / 2 + 0.025, x + 0.16, y, depth / 2 + 0.025)
          }
        // Window strips along the inward-facing wall stay visible during flight.
        for (let y = -height / 2 + 1; y < height / 2 - 1; y += 1.5)
          for (let z = -depth / 2 + 0.7; z < depth / 2 - 0.4; z += 1.15) {
            if ((Math.floor(y * 2) + n + Math.floor(z * 3)) % 5 === 0) continue
            const x = -side * (width / 2 + 0.025)
            windows.push(x, y, z - 0.27, x, y, z + 0.27)
          }
        building.add(
          new THREE.LineSegments(
            new THREE.BufferGeometry().setAttribute(
              "position",
              new THREE.Float32BufferAttribute(windows, 3)
            ),
            new THREE.LineBasicMaterial({
              color: palette[(n + 1) % 5],
              transparent: true,
              opacity: 0.5
            })
          )
        )
        slice.add(building)
      }
    if (row % 4 === 0) {
      const arch = new THREE.Mesh(
        new THREE.BoxGeometry(19, 0.15, 0.25),
        new THREE.MeshBasicMaterial({ color: "#7a5cff", transparent: true, opacity: 0.75 })
      )
      arch.position.y = 10 + (row % 3) * 3
      slice.add(arch)
    }
    const track = new THREE.LineSegments(
      new THREE.BufferGeometry().setAttribute(
        "position",
        new THREE.Float32BufferAttribute(
          [
            -5, -8, 6, -5, -8, -6, 5, -8, 6, 5, -8, -6, -0.1, -8, 6, -0.1, -8, 2, 0.1, -8, -1, 0.1,
            -8, -5
          ],
          3
        )
      ),
      new THREE.LineBasicMaterial({ color: "#3bff9e", transparent: true, opacity: 0.65 })
    )
    slice.add(track)
    // Batch geometry; architectural light rails retain their width at oblique angles.
    slice.updateMatrixWorld(true)
    const solids = [],
      lines = [],
      rails = [],
      remove = []
    slice.traverse((object) => {
      if (object.isMesh && object.material === dark) {
        solids.push(object.geometry.clone().applyMatrix4(object.matrixWorld))
        remove.push(object)
      } else if (object.isMesh) {
        const geometry = object.geometry.clone().applyMatrix4(object.matrixWorld)
        const colors = []
        for (let i = 0; i < geometry.attributes.position.count; i++)
          colors.push(...object.material.color.toArray())
        geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3))
        rails.push(geometry)
        remove.push(object)
      } else if (object.isLineSegments) {
        const geometry = object.geometry.clone().applyMatrix4(object.matrixWorld)
        const colors = []
        for (let i = 0; i < geometry.attributes.position.count; i++)
          colors.push(...object.material.color.clone().multiplyScalar(2.6).toArray())
        geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3))
        lines.push(geometry)
        remove.push(object)
      }
    })
    for (const object of remove) {
      object.removeFromParent()
      object.geometry.dispose()
    }
    slice.add(new THREE.Mesh(mergeGeometries(solids), dark))
    slice.add(
      new THREE.Mesh(
        mergeGeometries(rails),
        new THREE.MeshBasicMaterial({ vertexColors: true, toneMapped: false })
      )
    )
    slice.add(
      new THREE.LineSegments(
        mergeGeometries(lines),
        new THREE.LineBasicMaterial({
          vertexColors: true,
          transparent: true,
          opacity: 0.85,
          blending: THREE.AdditiveBlending
        })
      )
    )
    rails.forEach((g) => g.dispose())
    solids.forEach((g) => g.dispose())
    lines.forEach((g) => g.dispose())
    scene.add(slice)
    blocks.push(slice)
  }
  const moon = new THREE.Mesh(
    new THREE.CircleGeometry(9, 80),
    new THREE.MeshBasicMaterial({
      color: "#7a5cff",
      transparent: true,
      opacity: 0.25,
      fog: false,
      depthWrite: false
    })
  )
  moon.position.set(0, 23, -270)
  scene.add(moon)
  const halo = new THREE.Mesh(
    new THREE.PlaneGeometry(150, 100),
    new THREE.ShaderMaterial({
      transparent: true,
      depthWrite: false,
      uniforms: { tint: { value: new THREE.Color("#7a5cff") } },
      vertexShader:
        "varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}",
      fragmentShader: `varying vec2 vUv;uniform vec3 tint;void main(){float r=length((vUv-.5)*vec2(1.,1.25));gl_FragColor=vec4(tint,exp(-r*r*15.)*.3);
#include <colorspace_fragment>
}`
    })
  )
  halo.position.set(0, 14, -285)
  scene.add(halo)
  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(400, 600),
    new THREE.MeshBasicMaterial({ color: "#091114" })
  )
  ground.rotation.x = -Math.PI / 2
  ground.position.set(0, -8.2, -150)
  scene.add(ground)
  return (time) => {
    blocks.forEach((block, i) => (block.position.z = cityDepth(i, time)))
    camera.position.set(Math.sin(time * 0.13) * 1.8, -0.5 + Math.sin(time * 0.19) * 0.8, 8)
    camera.rotation.set(
      Math.sin(time * 0.08) * 0.025,
      Math.sin(time * 0.13) * 0.014,
      Math.sin(time * 0.1) * 0.015
    )
  }
}
