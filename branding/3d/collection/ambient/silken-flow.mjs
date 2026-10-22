import * as THREE from "three"
import { ribbonPoint } from "./motion.mjs"
export function createScene(scene, camera) {
  camera.position.set(0, 3, 43)
  const ribbons = []
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
        tint: {
          value: new THREE.Color(layer % 3 === 0 ? "#7a5cff" : layer === 5 ? "#e6c98a" : "#3bff9e")
        },
        layer: { value: layer }
      },
      vertexShader:
        "varying vec2 vUv; void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}",
      fragmentShader: `uniform vec3 tint;uniform float time;uniform float layer;varying vec2 vUv;
      void main(){float edge=pow(sin(vUv.y*3.14159265),.7);float ends=pow(sin(vUv.x*3.14159265),.4);
      float folds=.4+.6*pow(.5+.5*sin(vUv.y*75.+sin(vUv.x*12.+time*.2)*3.),5.);
      float threads=pow(.5+.5*sin(vUv.y*390.+vUv.x*14.+layer),18.);
      float light=(.11+folds*.5+threads*.22)*edge*ends;
      gl_FragColor=vec4(tint*(1.15+folds*1.5),light);
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
  return (time) => {
    for (const { geometry, material, layer } of ribbons) {
      const positions = geometry.attributes.position,
        uv = geometry.attributes.uv
      for (let i = 0; i < positions.count; i++)
        positions.setXYZ(i, ...ribbonPoint(uv.getX(i), uv.getY(i) - 0.5, time, layer))
      positions.needsUpdate = true
      material.uniforms.time.value = time
    }
    camera.position.x = Math.sin(time * 0.055) * 4
    camera.position.y = 3 + Math.sin(time * 0.08) * 2
    camera.lookAt(0, 0, -16)
    dust.rotation.z = Math.sin(time * 0.03) * 0.08
  }
}
