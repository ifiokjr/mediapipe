import 'dart:math' as math;

import 'package:mp_core/mp_core.dart';

/// Ten camera-friendly movement patterns. Thresholds are illustrative, not a
/// clinical assessment; the camera guidance is part of each tracker contract.
enum Exercise {
  /// Bilateral knee flexion.
  squats(
    'Squats',
    'LOWER BODY',
    'Side view · keep hips, knees and ankles visible',
    'Bend your knees, then stand tall.',
  ),

  /// Single-leg knee flexion.
  lunges(
    'Lunges',
    'LOWER BODY',
    'Side view · step back far enough to see both legs',
    'Lower one knee, then return to standing.',
  ),

  /// Bilateral elbow flexion from a plank.
  pressUps(
    'Press-ups',
    'UPPER BODY',
    'Side view · place the camera near floor height',
    'Bend both elbows, then press away.',
  ),

  /// Deep bilateral elbow flexion while standing.
  curls(
    'Biceps curls',
    'UPPER BODY',
    'Front view · show shoulders, elbows and wrists',
    'Curl both hands toward your shoulders.',
  ),

  /// Ordered crouch, plank, jump and landing sequence.
  burpees(
    'Burpees',
    'FULL BODY',
    'Side view · keep your whole body and floor visible',
    'Crouch, plank, crouch, jump, then land.',
  ),

  /// Combined arm elevation and leg separation.
  starJumps(
    'Star jumps',
    'FULL BODY',
    'Front view · leave space above and beside you',
    'Open arms and legs together, then close.',
  ),

  /// Bilateral shoulder abduction.
  lateralRaises(
    'Lateral raises',
    'UPPER BODY',
    'Front view · keep your whole wingspan visible',
    'Raise both arms sideways to shoulder height.',
  ),

  /// Alternating hip flexion, one count per knee raise.
  highKnees(
    'High knees',
    'CARDIO',
    'Side view · keep your torso upright',
    'Lift a knee toward your chest, then lower.',
  ),

  /// Torso flexion from a supine starting position.
  sitUps(
    'Sit-ups',
    'CORE',
    'Side view · lie down with bent knees',
    'Lift your torso toward your knees, then lower.',
  ),

  /// Lateral torso displacement relative to the hips.
  sideBends(
    'Side bends',
    'CORE',
    'Front view · keep your hips still',
    'Lean sideways, then return to the center.',
  );

  const Exercise(this.label, this.group, this.cameraGuide, this.cue);

  /// Display name.
  final String label;

  /// Movement family.
  final String group;

  /// Required framing for the measurement.
  final String cameraGuide;

  /// One-cycle instruction.
  final String cue;

  /// Landmarks needed for reliable measurement, using MediaPipe pose indices.
  List<int> get joints => switch (this) {
    burpees => <int>[11, 12, 23, 24, 25, 26, 27, 28],
    squats || lunges => <int>[23, 24, 25, 26, 27, 28],
    pressUps || curls => <int>[11, 12, 13, 14, 15, 16, 23, 24],
    starJumps => <int>[11, 12, 15, 16, 23, 24, 27, 28],
    lateralRaises => <int>[11, 12, 13, 14, 23, 24],
    highKnees || sitUps => <int>[11, 12, 23, 24, 25, 26],
    sideBends => <int>[11, 12, 23, 24],
  };
}

/// Normalized movement depth; null means the required joints are not visible.
/// Aspect compensation prevents portrait images distorting joint angles.
double? movementDepth(
  Exercise exercise,
  List<NormalizedLandmark> pose,
  double aspectRatio,
) {
  if (pose.length < 33 || !aspectRatio.isFinite || aspectRatio <= 0)
    return null;

  for (final int index in exercise.joints) {
    final NormalizedLandmark p = pose[index];

    if (!p.x.isFinite ||
        !p.y.isFinite ||
        (p.visibility ?? 0) < .6 ||
        (p.presence ?? 1) < .6 ||
        p.x < 0 ||
        p.x > 1 ||
        p.y < 0 ||
        p.y > 1) {
      return null;
    }
  }

  double angle(int a, int b, int c) {
    final double ax = (pose[a].x - pose[b].x) * aspectRatio;
    final double ay = pose[a].y - pose[b].y;
    final double cx = (pose[c].x - pose[b].x) * aspectRatio;
    final double cy = pose[c].y - pose[b].y;
    final double length = math.sqrt((ax * ax + ay * ay) * (cx * cx + cy * cy));

    if (length < .00001) return double.nan;

    return math.acos(((ax * cx + ay * cy) / length).clamp(-1.0, 1.0)) *
        180 /
        math.pi;
  }

  final double knees = (angle(23, 25, 27) + angle(24, 26, 28)) / 2;
  final double elbows = (angle(11, 13, 15) + angle(12, 14, 16)) / 2;
  final double torso =
      ((pose[11].y + pose[12].y) - (pose[23].y + pose[24].y)).abs() / 2;
  final double torsoX =
      ((pose[11].x + pose[12].x - pose[23].x - pose[24].x) * aspectRatio / 2)
          .abs();

  if (exercise == Exercise.pressUps && torso > torsoX * .6) return null;

  if (exercise == Exercise.curls && torso < torsoX) return null;

  final double depth = switch (exercise) {
    Exercise.squats => (170 - knees) / 75,
    Exercise.lunges =>
      (165 - math.min(angle(23, 25, 27), angle(24, 26, 28))) / 70,
    Exercise.pressUps => (170 - elbows) / 80,
    Exercise.curls => (165 - elbows) / 110,
    Exercise.burpees => (170 - knees) / 75,
    Exercise.lateralRaises =>
      ((angle(23, 11, 13) + angle(24, 12, 14)) / 2 - 15) / 70,
    Exercise.highKnees =>
      (170 - math.min(angle(11, 23, 25), angle(12, 24, 26))) / 85,
    Exercise.sitUps => (115 - (angle(11, 23, 25) + angle(12, 24, 26)) / 2) / 45,
    Exercise.sideBends =>
      (((pose[11].x + pose[12].x - pose[23].x - pose[24].x) / 2 * aspectRatio)
                      .abs() /
                  math.max(torso, .01) -
              .08) /
          .4,
    Exercise.starJumps => math.min(
      ((pose[11].y + pose[12].y - pose[15].y - pose[16].y) /
                  2 /
                  math.max(torso, .01) +
              .4) /
          .9,
      ((pose[27].x - pose[28].x).abs() /
                  math.max((pose[11].x - pose[12].x).abs(), .01) -
              1) /
          .9,
    ),
  };

  return depth.isFinite ? depth.clamp(0.0, 1.0) : null;
}

/// Counts stable rest → extension → rest cycles, rejecting jitter, short pulses,
/// stale timestamps, and interrupted tracking. Losing tracking discards a cycle.
final class RepCounter {
  /// Starts an empty set.
  RepCounter();

  /// Completed cycles.
  int reps = 0;

  /// Current measured movement depth.
  double depth = 0;

  /// Whether joints were visible in the latest sample.
  bool tracking = false;
  bool _armed = false;
  bool _extended = false;
  int? _candidateSince;
  int? _cycleSince;
  int? _lastTimestamp;
  int _candidate = -1;

  /// Human-readable state for live feedback.
  String get instruction => !tracking
      ? 'Step into frame'
      : !_armed
      ? 'Find your starting pose'
      : _extended
      ? 'Return to start'
      : 'Make your move';

  /// Resets the current set and its temporal state.
  void reset() {
    reps = 0;
    _lastTimestamp = null;
    _loseTracking();
  }

  /// Discards a partial movement while preserving completed reps.
  void interrupt() => _loseTracking();

  /// Consumes a sample measured from landmarks, or null on tracking loss.
  void update(double? value, int timestampMs) {
    final int? previous = _lastTimestamp;

    if (previous != null && timestampMs <= previous) return;
    _lastTimestamp = timestampMs;

    if (value == null ||
        !value.isFinite ||
        (previous != null && timestampMs - previous > 700)) {
      _loseTracking();

      return;
    }

    tracking = true;
    depth = value.clamp(0.0, 1.0);
    final int zone = depth < .2
        ? 0
        : depth > .8
        ? 1
        : -1;

    if (zone != _candidate) {
      _candidate = zone;
      _candidateSince = timestampMs;
    }

    if (zone == -1 || timestampMs - _candidateSince! < 150) return;

    if (zone == 0) {
      if (_armed && _extended && timestampMs - _cycleSince! >= 700) reps++;
      _armed = true;
      _extended = false;
      _cycleSince = timestampMs;
    } else if (_armed) {
      _extended = true;
    }
  }

  void _loseTracking() {
    tracking = false;
    depth = 0;
    _armed = false;
    _extended = false;
    _candidate = -1;
    _candidateSince = null;
    _cycleSince = null;
  }
}

/// Stages required for a complete burpee, including leaving and returning to
/// the standing ankle baseline. A squat alone can never count as a burpee.
enum BurpeeStage {
  /// Establish the floor baseline.
  ready,

  /// Drop into a crouch.
  crouch,

  /// Extend into a horizontal plank.
  plank,

  /// Bring the feet back under the body.
  returnCrouch,

  /// Leave the floor.
  jump,

  /// Return to the standing baseline.
  land;

  /// Plain-language next action.
  String get label => switch (this) {
    ready => 'stand tall',
    crouch => 'crouch down',
    plank => 'extend to plank',
    returnCrouch => 'bring feet forward',
    jump => 'jump up',
    land => 'land on your feet',
  };
}

/// Sequence-aware burpee tracker using the same visibility gate as other modes.
final class BurpeeCounter {
  /// Creates an empty set.
  BurpeeCounter();

  /// Completed full sequences.
  int reps = 0;

  /// Next required movement.
  BurpeeStage stage = BurpeeStage.ready;

  /// Whether the body is sufficiently visible.
  bool tracking = false;
  double? _floor;
  int? _lastTimestamp;
  int? _stageSince;

  /// Discards the current sequence and count.
  void reset() {
    reps = 0;
    _lastTimestamp = null;
    interrupt();
  }

  /// Discards only the incomplete sequence after tracking loss or pause.
  void interrupt() {
    stage = BurpeeStage.ready;
    _floor = null;
    _stageSince = null;
    tracking = false;
  }

  /// Advances only in sequence, with a minimum interval between transitions.
  void update(List<NormalizedLandmark> pose, double aspect, int timestamp) {
    if (_lastTimestamp != null && timestamp <= _lastTimestamp!) return;
    final bool gap =
        _lastTimestamp != null && timestamp - _lastTimestamp! > 700;
    _lastTimestamp = timestamp;
    final double? bend = movementDepth(Exercise.burpees, pose, aspect);
    tracking = bend != null && !gap;

    if (!tracking) {
      stage = BurpeeStage.ready;
      _floor = null;
      _stageSince = null;

      return;
    }

    final double shoulderY = (pose[11].y + pose[12].y) / 2;
    final double hipY = (pose[23].y + pose[24].y) / 2;
    final double ankleY = (pose[27].y + pose[28].y) / 2;
    final double torsoX =
        ((pose[11].x + pose[12].x - pose[23].x - pose[24].x) * aspect / 2)
            .abs();
    final bool upright = hipY - shoulderY > torsoX;
    final bool standing = upright && bend! < .2;
    final bool crouched = bend! > .8;
    final bool plank =
        !upright && (shoulderY - hipY).abs() < torsoX * .6 && bend < .25;

    if (_stageSince != null && timestamp - _stageSince! < 100) return;

    final bool advance = switch (stage) {
      BurpeeStage.ready => standing,
      BurpeeStage.crouch || BurpeeStage.returnCrouch => crouched,
      BurpeeStage.plank => plank,
      BurpeeStage.jump => standing && ankleY < _floor! - .045,
      BurpeeStage.land => standing && (ankleY - _floor!).abs() < .025,
    };

    if (!advance) return;

    if (stage == BurpeeStage.ready) _floor = ankleY;

    if (stage == BurpeeStage.land) {
      reps++;
      stage = BurpeeStage.crouch;
      _floor = ankleY;
    } else {
      stage = BurpeeStage.values[stage.index + 1];
    }

    _stageSince = timestamp;
  }
}
