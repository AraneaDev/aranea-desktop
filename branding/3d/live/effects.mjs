import * as THREE from "three"
import { EventTimeline, EVENT_KINDS, GLYPHS } from "./events.mjs"
import { journey } from "./journey.mjs"
const clamp = (x) => Math.max(0, Math.min(1, x))
const smooth = (x) => {
  x = clamp(x)
  return x * x * (3 - 2 * x)
}

export class SceneEvents {
  constructor(scene, forced = null) {
    this.director = new EventTimeline()
    this.forced = EVENT_KINDS.includes(forced) ? forced : null
    this.scene = scene
    this.current = null
    this.glyphs = new Map()
    this.projectionMaterial = new THREE.ShaderMaterial({
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      side: THREE.DoubleSide,
      uniforms: { map: { value: null }, time: { value: 0 }, fade: { value: 0 } },
      vertexShader:
        "varying vec2 uvGlyph; void main(){uvGlyph=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}",
      fragmentShader: `uniform sampler2D map; uniform float time; uniform float fade; varying vec2 uvGlyph;
    void main(){vec2 p=uvGlyph;float band=floor(p.y*30.0);float glitch=step(.96,sin(band*71.7+floor(time*13.0))*0.5+0.5);
     p.x+=glitch*.012*sin(time*37.0);float a=texture2D(map,p).a;
     float scan=.83+.17*sin(p.y*850.0-time*22.0);vec3 color=mix(vec3(.12,1.0,.67),vec3(.46,.22,1.0),p.y*.65);
     gl_FragColor=vec4(color*1.4,a*fade*scan);}`
    })
    this.projection = new THREE.Mesh(new THREE.PlaneGeometry(6.5, 7), this.projectionMaterial)
    scene.add(this.projection)
    this.projection.visible = false
    this.particleGeometry = new THREE.BufferGeometry()
    this.particleMaterial = new THREE.PointsMaterial({
      color: 0x55ffc5,
      size: 0.033,
      transparent: true,
      opacity: 0,
      depthWrite: false,
      blending: THREE.AdditiveBlending
    })
    this.particleGlyph = new THREE.Points(this.particleGeometry, this.particleMaterial)
    scene.add(this.particleGlyph)
    this.particleGlyph.visible = false
    this.ring = new THREE.Mesh(
      new THREE.TorusGeometry(1, 0.012, 6, 96),
      new THREE.MeshBasicMaterial({
        color: 0x34ffd0,
        transparent: true,
        opacity: 0,
        depthWrite: false,
        blending: THREE.AdditiveBlending
      })
    )
    this.ring.rotation.x = -Math.PI / 2
    scene.add(this.ring)
    this.ring.visible = false
    this.swarmPositions = new Float32Array(220 * 3)
    this.swarmGeometry = new THREE.BufferGeometry()
    this.swarmGeometry.setAttribute("position", new THREE.BufferAttribute(this.swarmPositions, 3))
    this.swarmMaterial = new THREE.PointsMaterial({
      color: 0xa29dff,
      size: 0.045,
      transparent: true,
      opacity: 0,
      depthWrite: false,
      blending: THREE.AdditiveBlending
    })
    this.swarm = new THREE.Points(this.swarmGeometry, this.swarmMaterial)
    scene.add(this.swarm)
    this.swarm.visible = false
  }
  async load() {
    await document.fonts.load("330px AraneaKanji", "影光糸夢電")
    for (const glyph of GLYPHS) {
      const canvas = document.createElement("canvas")
      canvas.width = canvas.height = 512
      const ctx = canvas.getContext("2d")
      ctx.font = "330px AraneaKanji"
      ctx.textAlign = "center"
      ctx.textBaseline = "middle"
      ctx.fillStyle = "white"
      ctx.fillText(glyph, 256, 265)
      const image = ctx.getImageData(0, 0, 512, 512).data,
        points = []
      for (let y = 0; y < 512; y += 5)
        for (let x = 0; x < 512; x += 5)
          if (image[(y * 512 + x) * 4 + 3] > 140)
            points.push([((x - 256) / 512) * 4.8, ((256 - y) / 512) * 4.8, 0])
      if (points.length < 30) throw Error("Kanji font did not load")
      this.glyphs.set(glyph, { texture: new THREE.CanvasTexture(canvas), points })
    }
  }
  begin(event, state) {
    this.current = event
    this.projection.visible =
      this.particleGlyph.visible =
      this.ring.visible =
      this.swarm.visible =
        false
    if (!event) return
    const side = state.camera[0] > state.position[0] ? -1 : 1
    if (event.kind === "kanji-projection") {
      this.projection.visible = true
      this.projection.position.set(
        side * 11.8,
        state.position[1] + 2,
        Math.round(state.position[2] / 6) * 6
      )
      this.projection.rotation.y = side < 0 ? Math.PI / 2 : -Math.PI / 2
      this.projectionMaterial.uniforms.map.value = this.glyphs.get(event.glyph).texture
    } else if (event.kind === "kanji-particles") {
      this.particleGlyph.visible = true
      this.particleGlyph.position.set(
        state.position[0] + side * 3.6,
        state.position[1] + 2,
        state.position[2] - 1
      )
      this.targets = this.glyphs.get(event.glyph).points
      this.glyphPositions = new Float32Array(this.targets.length * 3)
      this.particleGeometry.setAttribute(
        "position",
        new THREE.BufferAttribute(this.glyphPositions, 3)
      )
    } else if (event.kind === "web-pulse") {
      this.ring.visible = true
      this.ring.position.set(...state.position)
      this.ring.position.y += 0.02
    } else this.swarm.visible = true
  }
  update(time, state, camera, webMaterial, light) {
    const event = this.forced
      ? { kind: this.forced, start: time - 4, duration: 10, glyph: "糸", seed: 0.2 }
      : this.director.sample(time)
    if (event !== this.current && (!this.forced || !this.current))
      this.begin(event, event && !this.forced ? journey(event.start) : state)
    if (!event) return
    const u = clamp((time - event.start) / event.duration)
    const envelope = smooth(u / 0.22) * smooth((1 - u) / 0.22)
    if (event.kind === "kanji-projection") {
      this.projectionMaterial.uniforms.time.value = time
      this.projectionMaterial.uniforms.fade.value = envelope * (0.2 + 0.025 * Math.sin(time * 8))
    } else if (event.kind === "kanji-particles") {
      this.particleGlyph.quaternion.copy(camera.quaternion)
      this.targets.forEach((p, i) => {
        const scatter = 1 - envelope
        this.glyphPositions[i * 3] = p[0] + scatter * 2 * Math.sin(i * 23.1 + time * 0.6)
        this.glyphPositions[i * 3 + 1] = p[1] + scatter * 2 * Math.cos(i * 17.9 + time * 0.4)
        this.glyphPositions[i * 3 + 2] =
          scatter * 2 * Math.sin(i * 33.7 + time * 0.5) + 0.025 * Math.sin(time * 1.1 + i)
      })
      this.particleGeometry.attributes.position.needsUpdate = true
      this.particleGeometry.computeBoundingSphere()
      this.particleMaterial.opacity = 0.5 * envelope
    } else if (event.kind === "web-pulse") {
      this.ring.scale.setScalar(0.3 + u * 22)
      this.ring.material.opacity = 0.28 * envelope
      webMaterial.opacity += 0.22 * envelope * (0.6 + 0.4 * Math.sin(time * 2))
      light.intensity += 25 * envelope
    } else {
      this.swarm.position.fromArray(state.position)
      for (let i = 0; i < 220; i++) {
        const a = i * 2.399 + time * 0.7,
          r = 1.8 + 0.8 * Math.sin(i * 7.1 + time * 0.35)
        this.swarmPositions[i * 3] = Math.cos(a) * r
        this.swarmPositions[i * 3 + 1] = 0.2 + (i / 220) * 4 + Math.sin(time + i) * 0.2
        this.swarmPositions[i * 3 + 2] = Math.sin(a) * r
      }
      this.swarmGeometry.attributes.position.needsUpdate = true
      this.swarmGeometry.computeBoundingSphere()
      this.swarmMaterial.opacity = 0.7 * envelope
    }
  }
  dispose() {
    for (const { texture } of this.glyphs.values()) texture.dispose()
    for (const obj of [this.projection, this.particleGlyph, this.ring, this.swarm]) {
      obj.geometry.dispose()
      obj.material.dispose()
      this.scene.remove(obj)
    }
  }
}
