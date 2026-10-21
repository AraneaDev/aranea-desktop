"""Author the independent Silk Chamber geometry, lights and portrait camera."""

import math

import bpy
from mathutils import Vector


def _cylinder(collection, name, radius, depth, z, mat):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=128, radius=radius, depth=depth, location=(0, 0, z)
    )
    obj = bpy.context.object
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    collection.objects.link(obj)
    obj.name = name
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new("Soft stone edges", "BEVEL")
    bevel.width, bevel.segments = 0.035, 3
    obj.modifiers.new("Stone normals", "WEIGHTED_NORMAL")
    return obj


def _thread(collection, name, points, radius, mat):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, xyzv in zip(spline.points, points):
        point.co = (*xyzv, 1)
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def aim(obj, point):
    obj.rotation_euler = (
        (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()
    )


def _area(collection, name, position, color, energy, size, target=(0, 0, 0)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.shape, data.size = energy, color, "DISK", size
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.location = position
    aim(obj, target)
    return obj


def build_stage(collection, materials):
    """Populate the chamber collection and return its unanimated camera."""
    slate, silk, violet = (materials[name] for name in ("slate", "silk", "violet"))
    # Independent scene: concentric black stone, suspended silk and a violet rim.
    _cylinder(collection, "Basalt dais", 3.30, 0.24, -0.19, slate)
    _cylinder(collection, "Dark horizon", 200, 0.15, -0.40, slate)
    for radius in (2.65, 2.76, 3.12):
        _thread(
            collection,
            "Engraved circuit",
            [
                (
                    radius * math.cos(t * math.tau / 256),
                    radius * math.sin(t * math.tau / 256),
                    -0.058,
                )
                for t in range(257)
            ],
            0.007,
            silk,
        )
    _thread(
        collection,
        "Violet rim",
        [
            (
                3.25 * math.cos(t * math.tau / 256),
                3.25 * math.sin(t * math.tau / 256),
                -0.08,
            )
            for t in range(257)
        ],
        0.012,
        violet,
    )
    # A quiet radial silk lattice behind the character, with deliberately sagging strands.
    for i in range(16):
        theta = i * math.tau / 16
        _thread(
            collection,
            "Radial silk",
            [
                (r * math.cos(theta), r * math.sin(theta), -0.055)
                for r in (2.8, 3.3, 4.3)
            ],
            0.0035,
            silk,
        )
    for radius in (3.55, 4.15):
        points = []
        for i in range(16):
            a, b = (
                Vector(
                    (
                        radius * math.cos(i * math.tau / 16),
                        radius * math.sin(i * math.tau / 16),
                        0.0,
                    )
                ),
                Vector(
                    (
                        radius * math.cos((i + 1) * math.tau / 16),
                        radius * math.sin((i + 1) * math.tau / 16),
                        0.0,
                    )
                ),
            )
            for j in range(9):
                t = j / 8
                pt = a.lerp(b, t)
                pt.z = -0.05 - 0.07 * math.sin(t * math.pi)
                points.append(pt)
        points.append(points[0])
        _thread(collection, "Spun perimeter", points, 0.004, silk)
    _area(collection, "Soft silver key", (1, 1, 6), (0.72, 0.86, 1), 650, 5)
    _area(collection, "Mint rim", (-4, 1, 3), (0.16, 1, 0.67), 700, 4)
    _area(collection, "Violet fill", (3, -2, 2.5), (0.46, 0.22, 1), 500, 3)
    _area(collection, "Front softbox", (0, -5, 4), (0.7, 0.88, 0.96), 250, 4)
    camera_data = bpy.data.cameras.new("Portrait camera")
    camera = bpy.data.objects.new("Portrait camera", camera_data)
    collection.objects.link(camera)
    camera.location = (3.5, -6.8, 8.6)
    aim(camera, (0, 0, 0.20))
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 10.7
    return camera
