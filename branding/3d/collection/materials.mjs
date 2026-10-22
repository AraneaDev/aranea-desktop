// Small seamless material maps shared by the local WebGL screensavers.
const tau = Math.PI * 2
const clamp = (value) => Math.max(0, Math.min(1, value))
const wrap = (value, period) => ((value % period) + period) % period

function lattice(x, y, seed, period) {
  let value =
    Math.imul(wrap(x, period) + 1, 374761393) ^
    Math.imul(wrap(y, period) + 1, 668265263) ^
    Math.imul(seed + 1, 1274126177)
  value = Math.imul(value ^ (value >>> 13), 1274126177)
  return ((value ^ (value >>> 16)) >>> 0) / 4294967295
}
function noise(u, v, frequency, seed) {
  const x = u * frequency,
    y = v * frequency,
    ix = Math.floor(x),
    iy = Math.floor(y),
    fx = x - ix,
    fy = y - iy,
    sx = fx * fx * (3 - 2 * fx),
    sy = fy * fy * (3 - 2 * fy),
    a = lattice(ix, iy, seed, frequency),
    b = lattice(ix + 1, iy, seed, frequency),
    c = lattice(ix, iy + 1, seed, frequency),
    d = lattice(ix + 1, iy + 1, seed, frequency)
  return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
}

export function detailValue(kind, u, v, seed = 1) {
  u = wrap(u, 1)
  v = wrap(v, 1)
  const broad = noise(u, v, 8, seed),
    grain = noise(u, v, 64, seed + 13),
    fine = noise(u, v, 128, seed + 37)
  if (kind === "metal") {
    const brush = Math.sin(v * tau * 48 + Math.sin(u * tau * 4) * 0.3)
    return clamp(0.5 + broad * 0.23 + grain * 0.12 + brush * 0.075 + fine * 0.06)
  }
  if (kind === "silk") {
    const warp = Math.sin(u * tau * 40 + Math.sin(v * tau * 4) * 0.6),
      weft = Math.sin(v * tau * 40 + Math.sin(u * tau * 4) * 0.6)
    return clamp(0.55 + warp * weft * 0.17 + broad * 0.12 + grain * 0.1)
  }
  if (kind === "stone") {
    const vein = Math.abs(Math.sin((u * 4 + v * 3) * tau + broad * 5))
    return clamp(0.3 + broad * 0.3 + grain * 0.16 + fine * 0.08 + Math.pow(vein, 12) * 0.16)
  }
  if (kind === "crystal") {
    const facets = Math.abs(Math.sin(u * tau * 8 + broad * 2) * Math.cos(v * tau * 6 + broad * 2))
    return clamp(0.35 + facets * 0.38 + broad * 0.17 + fine * 0.07)
  }
  throw new RangeError(`Unknown material pattern: ${kind}`)
}

export function detailTexture(THREE, kind = "metal", seed = 1) {
  const size = 256,
    pixels = new Uint8Array(size * size * 4)
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++) {
      const offset = (y * size + x) * 4,
        value = Math.round(detailValue(kind, x / size, y / size, seed) * 255)
      pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = value
      pixels[offset + 3] = 255
    }
  const texture = new THREE.DataTexture(pixels, size, size, THREE.RGBAFormat)
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping
  texture.colorSpace = THREE.SRGBColorSpace
  texture.generateMipmaps = true
  texture.minFilter = THREE.LinearMipmapLinearFilter
  texture.magFilter = THREE.LinearFilter
  texture.needsUpdate = true
  return texture
}
