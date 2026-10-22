import * as THREE from "three"
import { detailTexture } from "../materials.mjs"
import { ribbonPoint, silkBurst } from "./motion.mjs"
export function createScene(scene, camera) {
  camera.position.set(0, 3, 43)
  const ribbons = []
  const weave = detailTexture(THREE, "silk", 43)
  for (let layer = 0; layer < 7; layer++) {
    const geometry = new THREE.PlaneGeometry(1, 1, 180, 14)
    const material = new THREE.ShaderMaterial({
      toneMapped: false,
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending,
      uniforms: {
        time: { value: 0 },
        weave: { value: weave },
        burst: { value: 0 },
        tint: {
          value: new THREE.Color(layer % 3 === 0 ? "#7a5cff" : layer === 5 ? "#e6c98a" : "#3bff9e")
        },
        layer: { value: layer }
      },
      vertexShader:
        "varying vec2 vUv; void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}",
      fragmentShader: `uniform sampler2D weave;uniform float burst;uniform vec3 tint;uniform float time;uniform float layer;varying vec2 vUv;
      void main(){float edge=pow(sin(vUv.y*3.14159265),.7);float ends=pow(sin(vUv.x*3.14159265),.4);
      float folds=.4+.6*pow(.5+.5*sin(vUv.y*75.+sin(vUv.x*12.+time*.2)*3.),5.);
      float threads=pow(.5+.5*sin(vUv.y*390.+vUv.x*14.+layer),18.);
      float fiber=texture2D(weave,vUv*vec2(5.,2.)).r;
      float glints=pow(.5+.5*sin(vUv.x*130.-time*1.1+vUv.y*21.),35.)*threads;
      float light=(.09+folds*.42+threads*.24+glints*(.25+burst*.4))*edge*ends*(.6+fiber*.6);
      gl_FragColor=vec4(mix(tint,vec3(.8,1.,.91),glints*.35)*(1.15+folds*1.5),light);
#include <tonemapping_fragment>
#include <colorspace_fragment>
}`
    })
    const mesh = new THREE.Mesh(geometry, material)
    mesh.frustumCulled = false
    scene.add(mesh)
    ribbons.push({ geometry, material, layer })
  }
  const points = new Float32Array(1000 * 3)
  for (let i = 0; i < 1000; i++) {
    points[i * 3] = Math.sin(i * 127.1) * 65
    points[i * 3 + 1] = Math.cos(i * 311.7) * 30
    points[i * 3 + 2] = -20 - (i % 100) * 0.5
  }
  const dust = new THREE.Points(
    new THREE.BufferGeometry().setAttribute("position", new THREE.BufferAttribute(points, 3)),
    new THREE.PointsMaterial({
      color: "#7a5cff",
      size: 0.045,
      transparent: true,
      opacity: 0.5,
      depthWrite: false,
      blending: THREE.AdditiveBlending
    })
  )
  scene.add(dust)
  const edgePositions = new Float32Array(7 * 2 * 96 * 2 * 3)
  const edges = new THREE.LineSegments(
    new THREE.BufferGeometry().setAttribute(
      "position",
      new THREE.BufferAttribute(edgePositions, 3)
    ),
    new THREE.LineBasicMaterial({
      color: "#b3ffdc",
      transparent: true,
      opacity: 0.21,
      depthWrite: false,
      blending: THREE.AdditiveBlending
    })
  )
  edges.frustumCulled = false
  scene.add(edges)
  const pearls = new THREE.InstancedMesh(
    new THREE.IcosahedronGeometry(0.11, 1),
    new THREE.MeshBasicMaterial({ color: "#b3ffdc", toneMapped: false }),
    96
  )
  pearls.instanceMatrix.setUsage(THREE.DynamicDrawUsage)
  pearls.frustumCulled = false
  scene.add(pearls)
  const pose = new THREE.Object3D()
  return (time) => {
    const burst = silkBurst(time)
    let edgeIndex = 0
    for (let layer = 0; layer < 7; layer++)
      for (const v of [-0.5, 0.5])
        for (let segment = 0; segment < 96; segment++)
          for (const u of [segment / 96, (segment + 1) / 96]) {
            const p = ribbonPoint(u, v, time, layer)
            edgePositions.set(p, edgeIndex)
            edgeIndex += 3
          }
    edges.geometry.attributes.position.needsUpdate = true
    edges.material.opacity = 0.16 + burst * 0.18
    for (let i = 0; i < 96; i++) {
      const u = (i / 96 + time * 0.018) % 1
      pose.position.set(...ribbonPoint(u, Math.sin(i * 12.7) * 0.45, time, i % 7))
      pose.scale.setScalar(Math.sin(u * Math.PI) * (0.45 + burst * 0.9))
      pose.updateMatrix()
      pearls.setMatrixAt(i, pose.matrix)
    }
    pearls.instanceMatrix.needsUpdate = true

    for (const { geometry, material, layer } of ribbons) {
      const positions = geometry.attributes.position,
        uv = geometry.attributes.uv
      for (let i = 0; i < positions.count; i++)
        positions.setXYZ(i, ...ribbonPoint(uv.getX(i), uv.getY(i) - 0.5, time, layer))
      positions.needsUpdate = true
      material.uniforms.time.value = time
      material.uniforms.burst.value = burst
    }
    camera.position.x = Math.sin(time * 0.055) * 4
    camera.position.y = 3 + Math.sin(time * 0.08) * 2
    camera.lookAt(0, 0, -16)
    dust.rotation.z = Math.sin(time * 0.03) * 0.08
  }
}
