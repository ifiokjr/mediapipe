import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mp_core/mp_core.dart';

/// Visual treatments for the landmark-driven character.
enum SkeletonStyle {
  /// Cream bones, ink outlines, ribs and a friendly skull.
  cartoon('Toon bones'),

  /// Glowing connected joints.
  neon('Neon noodle'),

  /// Rounded metal limbs and square joints.
  robot('Toy robot');

  const SkeletonStyle(this.label);

  /// Name shown in the style picker.
  final String label;
}

/// Face-local 3D accessories that can be layered independently.
enum FaceAccessory {
  /// Extruded round rims, translucent lenses, bridge and temples.
  glasses('Glasses'),

  /// A faceted five-point crown.
  crown('Crown'),

  /// Cuboid ear pieces and antennae.
  robotEars('Robot ears');

  const FaceAccessory(this.label);

  /// Name shown in the accessory picker.
  final String label;
}

/// Projects all overlays into the exact same fitted bounds as CameraPreview.
class TrackingOverlay extends CustomPainter {
  /// Creates a character or face overlay from upright normalized coordinates.
  TrackingOverlay({
    required this.pose,
    required this.face,
    required this.style,
    required this.accessories,
    required this.accent,
    required this.mirrored,
    required this.showPoints,
    required this.opacity,
  });

  /// Pose landmarks in upright image coordinates.
  final List<NormalizedLandmark> pose;

  /// Face landmarks in upright image coordinates.
  final List<NormalizedLandmark> face;

  /// Selected character appearance.
  final SkeletonStyle style;

  /// Enabled face-local meshes.
  final Set<FaceAccessory> accessories;

  /// Accent used for joints and accessories.
  final Color accent;

  /// Reflect overlays to match the front camera preview.
  final bool mirrored;

  /// Draw raw landmarks in addition to the styled overlay.
  final bool showPoints;

  /// User-controlled overlay opacity.
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );

    if (mirrored) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    if (pose.length >= 33) _drawSkeleton(canvas, size);

    if (face.length >= 468) _drawFace(canvas, size);

    if (showPoints) {
      for (final NormalizedLandmark p in <NormalizedLandmark>[
        ...pose,
        ...face,
      ]) {
        canvas.drawCircle(
          Offset(p.x * size.width, p.y * size.height),
          1.7,
          Paint()..color = accent,
        );
      }
    }

    canvas.restore();
  }

  void _drawSkeleton(Canvas canvas, Size size) {
    Offset p(int i) => Offset(pose[i].x * size.width, pose[i].y * size.height);
    bool visible(int i) => (pose[i].visibility ?? 0) >= .6;
    final double width = ((p(11) - p(12)).distance * .075).clamp(4.0, 18.0);
    const Color ink = Color(0xFF222E2D);

    final Color fill = switch (style) {
      SkeletonStyle.cartoon => const Color(0xFFFFF7DB),
      SkeletonStyle.neon => accent,
      SkeletonStyle.robot => const Color(0xFFB9D5D0),
    };

    final List<(int, int)> bones = <(int, int)>[
      (11, 12),
      (11, 13),
      (13, 15),
      (12, 14),
      (14, 16),
      (11, 23),
      (12, 24),
      (23, 24),
      (23, 25),
      (25, 27),
      (24, 26),
      (26, 28),
      (27, 31),
      (28, 32),
    ];

    for (final (int a, int b) in bones) {
      if (!visible(a) || !visible(b)) continue;
      final Paint outline = Paint()
        ..color = ink
        ..strokeWidth = width + 5
        ..strokeCap = StrokeCap.round;

      if (style == SkeletonStyle.neon) {
        canvas.drawLine(
          p(a),
          p(b),
          Paint()
            ..color = accent.withValues(alpha: .35)
            ..strokeWidth = width * 3
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
      }

      canvas.drawLine(p(a), p(b), outline);
      canvas.drawLine(
        p(a),
        p(b),
        Paint()
          ..color = fill
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    for (final int i in <int>[11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]) {
      if (!visible(i)) continue;
      final Rect rect = Rect.fromCircle(center: p(i), radius: width * .8);

      if (style == SkeletonStyle.robot) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(4)),
          Paint()..color = ink,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = accent,
        );
      } else {
        canvas.drawCircle(p(i), width * .85 + 2, Paint()..color = ink);
        canvas.drawCircle(p(i), width * .85, Paint()..color = accent);
        canvas.drawCircle(
          p(i) - Offset(width * .2, width * .2),
          width * .22,
          Paint()..color = Colors.white,
        );
      }
    }

    if (style != SkeletonStyle.cartoon ||
        !visible(11) ||
        !visible(12) ||
        !visible(23) ||
        !visible(24)) {
      return;
    }
    final Offset shoulder = (p(11) + p(12)) / 2;
    final Offset hip = (p(23) + p(24)) / 2;
    final Offset side = (p(12) - p(11)) * .38;

    if (visible(0)) {
      canvas.drawLine(
        p(0),
        shoulder,
        Paint()
          ..color = ink
          ..strokeWidth = width + 5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        p(0),
        shoulder,
        Paint()
          ..color = fill
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    for (int i = 1; i <= 4; i++) {
      final Offset center = Offset.lerp(shoulder, hip, i * .14)!;
      final Path rib = Path()
        ..moveTo((center - side).dx, (center - side).dy)
        ..quadraticBezierTo(
          center.dx,
          center.dy + width * 2,
          (center + side).dx,
          (center + side).dy,
        );
      canvas.drawPath(
        rib,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * .65 + 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        rib,
        Paint()
          ..color = fill
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * .65
          ..strokeCap = StrokeCap.round,
      );
    }

    if (!visible(0)) return;
    final Offset head = p(0);
    final double radius = (p(11) - p(12)).distance * .28;
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(math.atan2((p(8) - p(7)).dy, (p(8) - p(7)).dx));
    final RRect skull = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 1.7,
        height: radius * 1.9,
      ),
      Radius.circular(radius * .7),
    );
    canvas.drawRRect(skull.inflate(3), Paint()..color = ink);

    canvas.drawRRect(skull, Paint()..color = fill);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-radius * .35, -radius * .12),
        width: radius * .36,
        height: radius * .5,
      ),
      Paint()..color = ink,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(radius * .35, -radius * .12),
        width: radius * .36,
        height: radius * .5,
      ),
      Paint()..color = ink,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(0, radius * .25),
        width: radius * .7,
        height: radius * .45,
      ),
      0,
      math.pi,
      false,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.restore();
  }

  /// Uses the face's eye and forehead/chin axes in three dimensions. Mesh
  /// vertices retain depth; back-to-front polygon sorting provides occlusion
  /// between accessory surfaces and diffuse lighting makes rotation readable.
  void _drawFace(Canvas canvas, Size size) {
    _V3 landmark(int i) => _V3(
      face[i].x * size.width,
      face[i].y * size.height,
      face[i].z * size.width,
    );
    final _V3 left = landmark(33);
    final _V3 right = landmark(263);
    final _V3 origin = (left + right) * .5;
    final double scale = (right - left).length;

    if (scale < 2) return;
    final _V3 xAxis = (right - left).unit;
    final _V3 down = (landmark(152) - landmark(10)).unit;
    final _V3 zAxis = xAxis.cross(down).unit;
    final _V3 yAxis = zAxis.cross(xAxis).unit;
    final List<_Surface> surfaces = <_Surface>[];

    void polygon(List<_V3> vertices, Color color) {
      surfaces.add(
        _Surface(
          vertices
              .map(
                (_V3 v) =>
                    origin + (xAxis * v.x + yAxis * v.y + zAxis * v.z) * scale,
              )
              .toList(),
          color,
        ),
      );
    }

    void box(
      double x,
      double y,
      double z,
      double w,
      double h,
      double d,
      Color color,
    ) {
      final List<_V3> v = <_V3>[
        _V3(x, y, z),
        _V3(x + w, y, z),
        _V3(x + w, y + h, z),
        _V3(x, y + h, z),
        _V3(x, y, z + d),
        _V3(x + w, y, z + d),
        _V3(x + w, y + h, z + d),
        _V3(x, y + h, z + d),
      ];

      for (final List<int> indices in <List<int>>[
        <int>[0, 1, 2, 3],
        <int>[4, 7, 6, 5],
        <int>[0, 4, 5, 1],
        <int>[3, 2, 6, 7],
        <int>[0, 3, 7, 4],
        <int>[1, 5, 6, 2],
      ]) {
        polygon(indices.map((int i) => v[i]).toList(), color);
      }
    }

    if (accessories.contains(FaceAccessory.glasses)) {
      for (final double center in <double>[-.27, .27]) {
        const int segments = 24;
        final List<_V3> lens = <_V3>[];

        for (int i = 0; i < segments; i++) {
          final double a = i * math.pi * 2 / segments;
          final double b = (i + 1) * math.pi * 2 / segments;
          _V3 rim(double angle, double radius, double z) => _V3(
            center + math.cos(angle) * radius,
            math.sin(angle) * radius * .83,
            z,
          );
          polygon(<_V3>[
            rim(a, .245, -.12),
            rim(b, .245, -.12),
            rim(b, .2, -.12),
            rim(a, .2, -.12),
          ], accent);
          polygon(<_V3>[
            rim(a, .245, -.12),
            rim(a, .245, -.04),
            rim(b, .245, -.04),
            rim(b, .245, -.12),
          ], accent);
          lens.add(rim(a, .2, -.08));
        }

        polygon(lens, const Color(0x99327F91));
      }

      box(-.07, -.025, -.12, .14, .05, .07, accent);
      box(-.55, -.025, -.06, .05, .06, .45, accent);
      box(.50, -.025, -.06, .05, .06, .45, accent);
    }

    if (accessories.contains(FaceAccessory.crown)) {
      const Color gold = Color(0xFFFFCB55);
      box(-.52, -.64, -.02, 1.04, .16, .24, gold);

      for (int i = 0; i < 5; i++) {
        final double x = -.52 + i * .208;
        polygon(<_V3>[
          _V3(x, -.64, -.02),
          _V3(x + .104, -.98 - (i == 2 ? .12 : 0), .06),
          _V3(x + .208, -.64, -.02),
        ], gold);
        polygon(<_V3>[
          _V3(x + .208, -.64, -.02),
          _V3(x + .104, -.98 - (i == 2 ? .12 : 0), .06),
          _V3(x + .208, -.64, .22),
        ], const Color(0xFFE69C35));
      }
    }

    if (accessories.contains(FaceAccessory.robotEars)) {
      for (final double x in <double>[-.78, .6]) {
        box(x, -.14, .02, .18, .38, .24, accent);
        box(x + .06, -.46, .12, .05, .35, .06, const Color(0xFFEDF5DD));
        box(x + .02, -.52, .08, .13, .1, .13, const Color(0xFFFF8269));
      }
    }

    surfaces.sort((_Surface a, _Surface b) => b.depth.compareTo(a.depth));

    for (final _Surface surface in surfaces) {
      final Path path = Path()
        ..addPolygon(
          surface.vertices.map((_V3 v) => Offset(v.x, v.y)).toList(),
          true,
        );
      final _V3 normal = (surface.vertices[1] - surface.vertices[0])
          .cross(surface.vertices[2] - surface.vertices[0])
          .unit;
      final double light =
          .64 + .36 * normal.dot(const _V3(-.3, -.5, -.8).unit).abs();
      final Color color = surface.color;
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.from(
            alpha: color.a,
            red: color.r * light,
            green: color.g * light,
            blue: color.b * light,
          ),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0x66222E2D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TrackingOverlay oldDelegate) => true;
}

final class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
  _V3 operator +(_V3 b) => _V3(x + b.x, y + b.y, z + b.z);
  _V3 operator -(_V3 b) => _V3(x - b.x, y - b.y, z - b.z);
  _V3 operator *(double s) => _V3(x * s, y * s, z * s);
  double get length => math.sqrt(x * x + y * y + z * z);
  _V3 get unit => length < .0001 ? const _V3(0, 0, 0) : this * (1 / length);
  _V3 cross(_V3 b) =>
      _V3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
  double dot(_V3 b) => x * b.x + y * b.y + z * b.z;
}

final class _Surface {
  const _Surface(this.vertices, this.color);
  final List<_V3> vertices;
  final Color color;
  double get depth =>
      vertices.fold<double>(0, (double sum, _V3 v) => sum + v.z) /
      vertices.length;
}

/// Synthetic character for a clearly labeled preview. Never feeds rep counters.
List<NormalizedLandmark> demoPose(double phase) {
  final double wave = math.sin(phase * math.pi * 2) * .035;
  final List<(double, double)> points = List<(double, double)>.filled(33, (
    .5,
    .2,
  ));
  points[0] = (.5, .18 + wave * .3);
  points[7] = (.45, .18);
  points[8] = (.55, .18);
  points[11] = (.36, .32);
  points[12] = (.64, .32);
  points[13] = (.23, .43 + wave);

  points[14] = (.77, .43 - wave);
  points[15] = (.18, .29 + wave * 2);
  points[16] = (.82, .29 - wave * 2);
  points[23] = (.42, .57 + wave);
  points[24] = (.58, .57 + wave);
  points[25] = (.32, .73);
  points[26] = (.68, .73);
  points[27] = (.3, .9);

  points[28] = (.7, .9);
  points[31] = (.24, .92);
  points[32] = (.76, .92);

  return points
      .map(
        ((double, double) p) => NormalizedLandmark(
          x: p.$1,
          y: p.$2,
          z: 0,
          visibility: 1,
          presence: 1,
        ),
      )
      .toList();
}

/// Rotating synthetic face used solely to preview accessory meshes.
List<NormalizedLandmark> demoFace(double phase) {
  final double yaw = math.sin(phase * math.pi * 2) * .5;
  NormalizedLandmark point(double x, double y, [double z = 0]) =>
      NormalizedLandmark(
        x: .5 + x * math.cos(yaw) + z * math.sin(yaw),
        y: y,
        z: -x * math.sin(yaw) + z * math.cos(yaw),
      );
  final List<NormalizedLandmark> points = List<NormalizedLandmark>.generate(
    478,
    (int i) {
      final double a = i * math.pi * 2 / 478;

      return point(math.cos(a) * .24, .5 + math.sin(a) * .3);
    },
  );
  points[33] = point(-.17, .43);
  points[263] = point(.17, .43);
  points[10] = point(0, .22);
  points[152] = point(0, .8);

  return points;
}
