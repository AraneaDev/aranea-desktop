import * as THREE from "three"
import { glyphPhase } from "./motion.mjs"
export async function createScene(scene, camera) {
  const font = new FontFace("AraneaKanji", "url(../../live/kanji.woff2)")
  await font.load()
  document.fonts.add(font)
  const glyphs = "夢光影夜空風流永深静星月雨森花海"
  const atlas = document.createElement("canvas")
  atlas.width = 1024
  atlas.height = 1024
  const context = atlas.getContext("2d", { willReadFrequently: true })
  context.shadowBlur = 10
  context.shadowColor = "white"
  context.fillStyle = "white"
  context.textAlign = "center"
  context.textBaseline = "middle"
  context.font = "190px AraneaKanji"
  for (let i = 0; i < 16; i++)
    context.fillText(glyphs[i], (i % 4) * 256 + 128, Math.floor(i / 4) * 256 + 132)
  const pixels = context.getImageData(0, 0, 1024, 1024).data
  const texture = new THREE.CanvasTexture(atlas)
  texture.colorSpace = THREE.SRGBColorSpace
  const cloud = new THREE.Group()
  scene.add(cloud)
  const layers = []
  for (let index = 0; index < 32; index++) {
    const glyph = index % 16,
      column = glyph % 4,
      row = Math.floor(glyph / 4)
    const color = new THREE.Color(
      index % 9 === 0 ? "#e6c98a" : index % 3 === 0 ? "#7a5cff" : "#3bff9e"
    )
    const uniforms = {
      atlas: { value: texture },
      cell: { value: new THREE.Vector2(column, row) },
      dissolve: { value: 0 },
      time: { value: 0 },
      tint: { value: color },
      fade: { value: 1 }
    }
    const ink = new THREE.ShaderMaterial({
      toneMapped: false,
      uniforms,
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending,
      vertexShader:
        "varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}",
      fragmentShader: `uniform sampler2D atlas;uniform vec2 cell;uniform float dissolve;uniform vec3 tint;uniform float fade;varying vec2 vUv;
      float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
      void main(){vec2 sampleUv=(vec2(cell.x,3.-cell.y)+vUv)/4.;float ink=texture2D(atlas,sampleUv).a;
      float mask=smoothstep(dissolve-.04,dissolve+.04,hash(floor(vUv*80.)));gl_FragColor=vec4(tint*1.25,ink*mask*fade*.72);
#include <tonemapping_fragment>
#include <colorspace_fragment>
}`
    })
    const group = new THREE.Group()
    const size = 5 + (index % 4) * 0.9
    group.add(new THREE.Mesh(new THREE.PlaneGeometry(size, size), ink))
    const positions = [],
      scatter = []
    for (let y = 12; y < 244; y += 5)
      for (let x = 12; x < 244; x += 5) {
        if (pixels[((row * 256 + y) * 1024 + column * 256 + x) * 4 + 3] < 100) continue
        positions.push((x / 256 - 0.5) * size, (0.5 - y / 256) * size, 0)
        const n = positions.length
        scatter.push(Math.sin(n * 127.1) * 8, 2 + Math.cos(n * 43.7) * 6, Math.cos(n * 73.1) * 7)
      }
    const geometry = new THREE.BufferGeometry()
      .setAttribute("position", new THREE.Float32BufferAttribute(positions, 3))
      .setAttribute("scatter", new THREE.Float32BufferAttribute(scatter, 3))
    const motes = new THREE.ShaderMaterial({
      toneMapped: false,
      uniforms,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      vertexShader: `attribute vec3 scatter;uniform float dissolve;uniform float time;varying float alpha;
      void main(){float d=dissolve;vec3 p=position+scatter*d*d; p.x+=sin(time*.5+position.y)*d*.4;
      vec4 mv=modelViewMatrix*vec4(p,1.);gl_Position=projectionMatrix*mv;gl_PointSize=min(5.,65./max(1.,-mv.z));alpha=sin(d*3.14159265);}`,
      fragmentShader: `uniform vec3 tint;uniform float fade;varying float alpha;void main(){float r=length(gl_PointCoord-.5);if(r>.5)discard;gl_FragColor=vec4(tint*1.5,(1.-r*2.)*alpha*fade);
#include <tonemapping_fragment>
#include <colorspace_fragment>
}`
    })
    group.add(new THREE.Points(geometry, motes))
    const depth = Math.floor(index / 8)
    const angle = index * 2.399963
    const radius = 5 + (index % 8) * 1.5
    group.position.set(Math.cos(angle) * radius, Math.sin(angle) * radius * 0.62, -depth * 13)
    group.rotation.z = Math.sin(index * 4.1) * 0.15
    cloud.add(group)
    layers.push({ group, uniforms, index, base: group.position.clone() })
  }
  const geometry = new THREE.BufferGeometry(),
    positions = []
  for (let i = 0; i < 1000; i++)
    positions.push(Math.sin(i * 122.7) * 38, Math.cos(i * 56.8) * 25, -(i % 100) * 0.8)
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3))
  scene.add(
    new THREE.Points(
      geometry,
      new THREE.PointsMaterial({
        color: "#7a5cff",
        size: 0.035,
        transparent: true,
        opacity: 0.5,
        depthWrite: false
      })
    )
  )
  return (time) => {
    for (const { group, uniforms, index, base } of layers) {
      const phase = glyphPhase(index, time)
      uniforms.dissolve.value = phase.dissolve
      uniforms.fade.value = Math.min(1, ((time + index * 1.71) % 12) * 0.75)
      uniforms.time.value = time
      group.position.x = base.x + Math.sin(time * 0.13 + index) * 1.4
      group.position.y = base.y + Math.sin(time * 0.09 + index * 3) * 1.5
      group.rotation.y = Math.sin(time * 0.12 + index) * 0.25
    }
    camera.position.set(
      Math.sin(time * 0.045) * 3,
      Math.cos(time * 0.06) * 1.5,
      27 + Math.sin(time * 0.07) * 2
    )
    camera.lookAt(0, 0, -14)
    cloud.rotation.z = Math.sin(time * 0.035) * 0.045
  }
}
