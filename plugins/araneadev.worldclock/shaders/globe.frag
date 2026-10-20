#version 440
// The World Clock globe's surface (Globe.qml's ShaderEffect): an
// orthographic view of the Earth centred on (centerLat, centerLon), lit by
// the sun along sunDir. Per fragment inside the disc: the inverse
// orthographic projection gives the latitude and longitude, the land mask
// (`source`, land.png, white land in alpha, repeating in x) says land or
// sea, and the sun's height there gives the day factor. Night is near-black
// sea and faint violet land, day deep-teal sea and muted green land, with a
// ceremony (gold) band where day is between 0 and 1, an accent rim tint
// toward the limb and faint 30 degree meridians. Every colour is mixed from
// the theme tokens passed in (the v3 mockup's globe() formula, in tokens).
// Rebuild globe.frag.qsb with tools/build-worldclock-globe.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // The view centre, degrees.
    float centerLon;
    float centerLat;
    // The disc radius, pixels.
    float radiusPx;
    // The item size, pixels (the disc is centred in it).
    vec2 viewSize;
    // Unit vector to the sun: x toward (0, 0), y toward (0, 90E), z north.
    vec3 sunDir;
    // Theme tokens.
    vec4 background;
    vec4 foreground;
    vec4 accent;
    vec4 violet;
    vec4 ceremony;
};

layout(binding = 1) uniform sampler2D source;

const float DEG = 0.017453292519943295;

void main()
{
    vec2 p = qt_TexCoord0 * viewSize - 0.5 * viewSize;
    vec2 d = vec2(p.x, -p.y) / radiusPx;
    float rr = dot(d, d);
    if (rr >= 1.0) {
        fragColor = vec4(0.0);
        return;
    }
    // One pixel of coverage antialiasing at the limb.
    float edge = 1.0 - smoothstep(1.0 - 1.0 / radiusPx, 1.0, sqrt(rr));
    float z = sqrt(1.0 - rr);

    float p0 = centerLat * DEG;
    float lat = asin(clamp(d.y * cos(p0) + z * sin(p0), -1.0, 1.0));
    float lon = centerLon * DEG + atan(d.x, z * cos(p0) - d.y * sin(p0));
    vec3 n = vec3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat));
    float day = smoothstep(-0.05, 0.07, dot(n, sunDir));

    // Continuous in x across the antimeridian: the texture repeats.
    vec2 uv = vec2((lon / DEG + 180.0) / 360.0, clamp((90.0 - lat / DEG) / 180.0, 0.0, 1.0));
    float land = texture(source, uv).a;

    vec3 bg = background.rgb;
    vec3 nightSea = mix(bg, violet.rgb, 0.04);
    vec3 nightLand = mix(bg, mix(foreground.rgb, violet.rgb, 0.5), 0.14);
    vec3 daySea = mix(bg, mix(accent.rgb, violet.rgb, 0.5), 0.17);
    vec3 dayLand = mix(bg, mix(accent.rgb, foreground.rgb, 0.12), 0.52);
    vec3 c = mix(mix(nightSea, daySea, day), mix(nightLand, dayLand, day), land);

    // The terminator band peaks halfway between night and day.
    float band = 1.0 - abs(day - 0.5) * 2.0;
    c += ceremony.rgb * 0.26 * band;

    float rim = pow(1.0 - z, 3.0);
    c += accent.rgb * 0.28 * rim;

    // Distance to the nearest 30 degree meridian along the parallel, pixels.
    float meridian = abs(fract(lon / DEG / 30.0 + 0.5) - 0.5) * 30.0 * DEG * cos(lat) * radiusPx;
    c = mix(c, accent.rgb, 0.10 * (1.0 - smoothstep(0.35, 1.0, meridian)));

    fragColor = vec4(min(c, vec3(1.0)), 1.0) * edge * qt_Opacity;
}
