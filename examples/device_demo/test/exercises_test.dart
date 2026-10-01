import 'package:flutter_test/flutter_test.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_device_demo/playground/exercises.dart';

void main() {
  test('ten distinct exercises include the five requested movements', () {
    expect(Exercise.values, hasLength(10));
    expect(
      Exercise.values,
      containsAll(<Exercise>[
        Exercise.squats,
        Exercise.pressUps,
        Exercise.sitUps,
        Exercise.starJumps,
        Exercise.burpees,
      ]),
    );
  });

  for (final Exercise exercise in Exercise.values.where((Exercise e) => e != Exercise.burpees)) {
    test('${exercise.label} counts a complete landmark-driven cycle', () {
      final List<NormalizedLandmark> rest = _rest(exercise);
      final List<NormalizedLandmark> active = _active(exercise);
      final double? low = movementDepth(exercise, rest, 1);
      final double? high = movementDepth(exercise, active, 1);
      expect(low, lessThan(.2));
      expect(high, greaterThan(.8));
      final RepCounter counter = RepCounter();

      for (final (int timestamp, List<NormalizedLandmark> pose)
          in <(int, List<NormalizedLandmark>)>[
            (0, rest),
            (200, rest),
            (500, active),
            (700, active),
            (1000, rest),
            (1200, rest),
          ]) {
        counter.update(movementDepth(exercise, pose, 1), timestamp);
      }

      expect(counter.reps, 1);
      counter.update(low, 1400);
      expect(counter.reps, 1, reason: 'Holding rest cannot increment twice');
    });
  }

  test('jitter, missing joints, and stale frames never manufacture a rep', () {
    final RepCounter counter = RepCounter();
    counter.update(0, 0);
    counter.update(0, 200);
    counter.update(1, 500);
    counter.update(0, 550);
    counter.update(0, 750);
    expect(counter.reps, 0);
    counter.update(1, 1000);
    counter.update(1, 1200);
    counter.update(null, 1400);
    counter.update(0, 1600);
    counter.update(0, 1800);
    expect(counter.reps, 0);
    counter.update(1, 1900);
    counter.update(1, 2100);
    counter.update(0, 4000);
    counter.update(0, 4200);
    expect(counter.reps, 0);
    counter.update(1, 100);
    expect(counter.depth, 0);
  });

  test('a tracker must see a starting pose before counting', () {
    final RepCounter counter = RepCounter();
    counter.update(1, 0);
    counter.update(1, 200);
    counter.update(0, 800);
    counter.update(0, 1000);
    expect(counter.reps, 0);
  });

  test('occluded, out-of-frame, degenerate and nonfinite joints are rejected', () {
    for (final Exercise exercise in Exercise.values) {
      final List<NormalizedLandmark> pose = _rest(exercise);
      final int index = exercise.joints.first;
      final NormalizedLandmark original = pose[index];
      pose[index] = NormalizedLandmark(x: original.x, y: original.y, z: 0, visibility: .1);
      expect(movementDepth(exercise, pose, 1), isNull);
      pose[index] = const NormalizedLandmark(x: double.nan, y: .5, z: 0, visibility: 1);
      expect(movementDepth(exercise, pose, 1), isNull);
      pose[index] = const NormalizedLandmark(x: 1.2, y: .5, z: 0, visibility: 1);
      expect(movementDepth(exercise, pose, 1), isNull);
    }

    expect(movementDepth(Exercise.squats, <NormalizedLandmark>[], 1), isNull);
    expect(movementDepth(Exercise.squats, _rest(Exercise.squats), 0), isNull);
  });

  test('portrait scaling preserves joint angles', () {
    final List<NormalizedLandmark> square = _active(Exercise.squats);
    final List<NormalizedLandmark> portrait = square
        .map(
          (NormalizedLandmark p) =>
              NormalizedLandmark(x: (p.x - .5) / .75 + .5, y: p.y, z: p.z, visibility: 1),
        )
        .toList();
    expect(
      movementDepth(Exercise.squats, portrait, .75),
      closeTo(movementDepth(Exercise.squats, square, 1)!, .0001),
    );
  });

  test('burpees require plank, return crouch, jump and landing', () {
    final BurpeeCounter counter = BurpeeCounter();
    final List<NormalizedLandmark> stand = _rest(Exercise.burpees);
    final List<NormalizedLandmark> crouch = _active(Exercise.squats);
    final List<NormalizedLandmark> plank = _rest(Exercise.burpees);
    for (final int side in <int>[0, 1]) {
      _set(plank, 11 + side, .2, .5);
      _set(plank, 23 + side, .45, .5);
      _set(plank, 25 + side, .65, .5);
      _set(plank, 27 + side, .85, .5);
    }

    final List<NormalizedLandmark> jump = stand
        .map(
          (NormalizedLandmark p) => NormalizedLandmark(x: p.x, y: p.y - .08, z: 0, visibility: 1),
        )
        .toList();
    counter.update(stand, 1, 0);
    counter.update(crouch, 1, 300);
    counter.update(stand, 1, 600);
    expect(counter.reps, 0);
    expect(counter.stage, BurpeeStage.plank);
    counter.update(plank, 1, 900);
    counter.update(crouch, 1, 1200);
    counter.update(jump, 1, 1500);
    expect(counter.reps, 0);
    counter.update(stand, 1, 1800);
    expect(counter.reps, 1);
    counter.update(crouch, 1, 2000);
    counter.update(<NormalizedLandmark>[], 1, 2200);
    expect(counter.stage, BurpeeStage.ready);
    expect(counter.reps, 1);
  });
}

List<NormalizedLandmark> _rest(Exercise exercise) {
  final List<NormalizedLandmark> pose = List<NormalizedLandmark>.filled(
    33,
    const NormalizedLandmark(x: .5, y: .2, z: 0, visibility: 1, presence: 1),
  );

  for (final int side in <int>[0, 1]) {
    final double x = .4 + .2 * side;
    _set(pose, 11 + side, x, .3);
    _set(pose, 13 + side, x, .42);
    _set(pose, 15 + side, x, .55);
    _set(pose, 23 + side, x, .5);
    _set(pose, 25 + side, x, .7);
    _set(pose, 27 + side, x, .9);

    if (exercise == Exercise.pressUps) {
      _set(pose, 11 + side, .2, .5);
      _set(pose, 13 + side, .2, .65);
      _set(pose, 15 + side, .2, .8);
      _set(pose, 23 + side, .5, .5);
    }

    if (exercise == Exercise.sitUps) {
      _set(pose, 11 + side, .2, .5);
      _set(pose, 23 + side, .4, .5);
      _set(pose, 25 + side, .65, .65);
    }
  }

  return pose;
}

List<NormalizedLandmark> _active(Exercise exercise) {
  final List<NormalizedLandmark> pose = _rest(exercise);

  for (final int side in <int>[0, 1]) {
    final double x = .4 + .2 * side;

    switch (exercise) {
      case Exercise.squats || Exercise.lunges || Exercise.burpees:
        _set(pose, 27 + side, x + .2, .7);
      case Exercise.pressUps:
        _set(pose, 15 + side, .35, .65);
      case Exercise.curls:
        _set(pose, 15 + side, x + .02, .31);
      case Exercise.lateralRaises:
        _set(pose, 13 + side, side == 0 ? .2 : .8, .3);
      case Exercise.highKnees:
        _set(pose, 25 + side, x + .2, .5);
      case Exercise.sitUps:
        _set(pose, 11 + side, .55, .35);
      case Exercise.sideBends:
        _set(pose, 11 + side, x + .13, .3);
      case Exercise.starJumps:
        _set(pose, 15 + side, x, .05);
        _set(pose, 27 + side, side == 0 ? .15 : .85, .9);
    }
  }

  return pose;
}

void _set(List<NormalizedLandmark> pose, int index, double x, double y) {
  pose[index] = NormalizedLandmark(x: x, y: y, z: 0, visibility: 1, presence: 1);
}
