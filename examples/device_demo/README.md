# Move! — the motion playground

A Flutter example that turns MediaPipe landmarks into a friendly cartoon
skeleton, movement counters, and face-following 3D accessories. Use it to learn
camera inference, build an exercise prototype, or experiment with augmented
characters.

## Try it

From the repository root:

```sh
devenv shell install
# Interactive visual preview; browser mode does not use the camera.
devenv shell -- bash -c 'cd examples/device_demo && repo-flutter run -d chrome'
```

The app opens in **Animated demo** mode. Its synthetic character never increments
exercise counters. Switch between Movement lab and Face studio, change colors,
select a skeleton, stack accessories, or adjust opacity and landmark visibility.
Light and dark themes and narrow phone layouts are supported. The bundled Fredoka
font is licensed under the SIL Open Font License (see `assets/fonts/OFL.txt`).

For live inference on Android, prepare the repository's native runtime and launch:

```sh
devenv shell native:build --target android-arm64
devenv shell native:verify --target android-arm64
devenv shell test:device-demo
```

Alternatively, extract the matching **checksum-verified** Android runtime archive
from this repository's `native-v1.0.0-1` release into `.mp-sdk/android-arm64/`.
The pinned archive URL and SHA-256 are in
`../../packages/mp_core/hook/native_artifacts.json`. Run `native:verify` after
extraction. No native binary or model is committed to this example.

Tap **Start camera** and grant camera permission. The selected model downloads
from Google's public asset bucket and is SHA-256 verified. Network access is
needed for model resolution; camera frames stay on the device. The front camera
is selected by default; **Flip** changes lenses. Pause, reset, change exercise,
or return to the demo at any time. Backgrounding the app closes the camera;
restart it explicitly when returning.

The native camera adapter handles Android and iOS frame formats, but the
repository currently publishes no iOS vision runtime. iOS live tracking requires
that runtime to be linked separately and is not verified here. Browser mode is a
visual preview only; it does not initialize the native camera pipeline.

## Ten exercise trackers

| Exercise       | Camera view | Measurement                                      |
| -------------- | ----------- | ------------------------------------------------ |
| Squats         | Side        | Average knee flexion                             |
| Press-ups      | Side, low   | Elbow flexion with horizontal torso gate         |
| Sit-ups        | Side, low   | Shoulder–hip–knee angle                          |
| Star jumps     | Front       | Arms overhead **and** legs apart                 |
| Burpees        | Side        | Stand → crouch → plank → crouch → jump → landing |
| Lunges         | Side        | Flexion of the more bent knee                    |
| Biceps curls   | Front       | Deep elbow flexion with upright torso gate       |
| Lateral raises | Front       | Shoulder abduction relative to the torso         |
| High knees     | Side        | Hip flexion; one count per completed knee raise  |
| Side bends     | Front       | Torso lean relative to the hip center            |

These are illustrative geometric counters, not exercise recognition or form
assessment. Select the exercise you are performing and follow its camera guide.
Thresholds assume the indicated view and good lighting; occlusion, perspective,
and individual range of motion can affect counts. A burpee's jump is measured
against its initial ankle-height baseline, so keep the camera stationary.

The nine cyclic counters require a stable starting pose, stable movement depth,
and a return to start. Hysteresis, minimum dwell time, and a minimum cycle duration
reject jitter. Missing or low-confidence joints and stale frames discard partial
cycles while retaining completed reps. Changing exercise, lens, or tracking mode
starts a new set. Burpees use an ordered sequence instead of an angle-only rep
counter.

## Visuals and implementation

- **Toon bones:** outlined cream bones, articulated ribs, colorful joints and a
  smiling skull. **Neon noodle:** glowing limbs. **Toy robot:** metal limbs with
  square joints. All follow the detected pose directly.
- **Face studio:** glasses with extruded rims, translucent lenses, bridge and
  temples; a faceted crown; and robot ears with antennae. Accessories can be
  combined and recolored.
- The lightweight software 3D renderer builds meshes in face-local coordinates,
  derives head axes from eye/forehead/chin landmarks (including depth), projects
  vertices onto the camera plane, shades surfaces, and sorts them by depth.
  It is an orthographic overlay renderer, with accessory-to-accessory occlusion;
  it does not implement a face depth mask, photorealistic fitting, or physical
  lens refraction.
- `tracking_session.dart` serializes startup, mode changes and disposal. It runs
  one task at a time in video mode through `LatestFrameScheduler`, keeping only
  the latest pending frame. Pixels are rotated upright before inference; preview
  and overlay share one fitted aspect ratio and front-camera mirroring.
- `exercises.dart` contains the independent measurement and counting logic;
  `overlays.dart` owns drawing and synthetic preview data;
  `playground_app.dart` composes the responsive interface.

The earlier face-detector and motion telemetry example remains available with
`repo-flutter run -t lib/device_telemetry.dart` from this directory. That entry
point reads motion sensors directly, so it needs a physical device; the
playground above also runs in the browser with its synthetic preview.

## Checks

```sh
devenv shell repo-flutter test examples/device_demo/test
devenv shell repo-dart analyze examples/device_demo
devenv shell -- bash -c 'cd examples/device_demo && repo-flutter build web'
# On a connected Android device with camera permission already granted:
devenv shell -- bash -c 'cd examples/device_demo && repo-flutter test integration_test/live_camera_test.dart -d SM02E4060324957'
```

Unit tests cover landmark-driven cycles, missing/invalid joints, temporal jitter,
interruption, aspect compensation, pixel rotation and the complete burpee
sequence. Widget tests exercise the real app's movement selection, visual
controls, face accessories, theme switching and phone layout. The device smoke
test opens the actual camera, obtains results from both real MediaPipe models,
and returns to demo mode; it does not validate real-human rep accuracy.
