import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mp_core/mp_core.dart';

import 'exercises.dart';
import 'overlays.dart';
import 'tracking_session.dart';

const Color _ink = Color(0xFF253B35);
const Color _green = Color(0xFF245A43);
const Color _lime = Color(0xFFDAF58A);
const Color _cream = Color(0xFFF7F5EA);
const Color _orange = Color(0xFFFF8969);

/// A playful, responsive showcase for pose tracking and face-local 3D meshes.
class MotionPlaygroundApp extends StatefulWidget {
  /// Creates the standalone example app.
  const MotionPlaygroundApp({super.key});

  @override
  State<MotionPlaygroundApp> createState() => _MotionPlaygroundAppState();
}

class _MotionPlaygroundAppState extends State<MotionPlaygroundApp> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Move! Motion playground',
    theme: ThemeData(
      useMaterial3: true,
      brightness: _dark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _green,
        brightness: _dark ? Brightness.dark : Brightness.light,
        primary: _dark ? _lime : _green,
      ),
      scaffoldBackgroundColor: _dark ? const Color(0xFF162822) : _cream,
      fontFamily: 'Avenir Next',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 44,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 22,
          fontWeight: FontWeight.w500,
          letterSpacing: -.5,
        ),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    home: _Playground(onTheme: () => setState(() => _dark = !_dark), dark: _dark),
  );
}

class _Playground extends StatefulWidget {
  const _Playground({required this.onTheme, required this.dark});
  final VoidCallback onTheme;
  final bool dark;

  @override
  State<_Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<_Playground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TrackingSession _session = TrackingSession();
  final RepCounter _counter = RepCounter();
  final BurpeeCounter _burpees = BurpeeCounter();
  late final AnimationController _animation;
  Exercise _exercise = Exercise.squats;
  SkeletonStyle _style = SkeletonStyle.cartoon;
  Set<FaceAccessory> _accessories = <FaceAccessory>{FaceAccessory.glasses};
  Color _accent = _orange;
  bool _faceMode = false;
  bool _live = false;
  bool _front = true;
  bool _paused = false;
  bool _points = false;
  double _opacity = 1;
  int _lastTimestamp = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation = AnimationController(vsync: this, duration: const Duration(seconds: 5));
    unawaited(_animation.repeat());
    _session.addListener(_onTracking);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) &&
        _live) {
      setState(() => _live = false);
      _reset();
      unawaited(_session.configure(enabled: false, faceMode: _faceMode));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onTracking);
    _session.dispose();
    _animation.dispose();
    super.dispose();
  }

  void _onTracking() {
    if (!mounted) return;

    if (_session.pose.isEmpty) {
      _counter.interrupt();
      _burpees.interrupt();
    }

    if (_live && !_paused && !_faceMode && _session.timestampMs != _lastTimestamp) {
      _lastTimestamp = _session.timestampMs;
      _counter.update(
        movementDepth(_exercise, _session.pose, _session.aspectRatio),
        _session.timestampMs,
      );
      _burpees.update(_session.pose, _session.aspectRatio, _session.timestampMs);
    }

    setState(() {});
  }

  void _reset() {
    _counter.reset();
    _burpees.reset();
    _lastTimestamp = -1;
  }

  void _configure() {
    _reset();
    unawaited(_session.configure(enabled: _live, faceMode: _faceMode, front: _front));
  }

  int get _reps => _exercise == Exercise.burpees ? _burpees.reps : _counter.reps;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _header(context),
                const SizedBox(height: 30),
                Wrap(
                  spacing: 20,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _faceMode ? 'A little more character.' : 'Good moves. Great bones.',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _faceMode
                              ? 'Try something on. Make a face. Find your alter ego.'
                              : 'A motion playground that moves the way you do.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                    const _Badge(label: 'POWERED BY MEDIAPIPE', color: _lime),
                  ],
                ),
                const SizedBox(height: 26),
                SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.accessibility_new_rounded),
                      label: Text('Movement lab'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.face_retouching_natural),
                      label: Text('Face studio'),
                    ),
                  ],
                  selected: <bool>{_faceMode},
                  onSelectionChanged: (Set<bool> value) {
                    setState(() => _faceMode = value.first);
                    _configure();
                  },
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final Widget controls = _controls(context);
                    final Widget stage = _stage(context);

                    if (constraints.maxWidth < 900) {
                      return Column(
                        children: <Widget>[stage, const SizedBox(height: 20), controls],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 8, child: stage),
                        const SizedBox(width: 24),
                        Expanded(flex: 5, child: controls),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                Text(
                  'BUILT FOR PLAY  /  Camera frames stay on your device.  /  Demo reps are never counted.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.bubble_chart_rounded, color: _lime, size: 30),
      ),
      const SizedBox(width: 10),
      Text('move!', style: Theme.of(context).textTheme.headlineMedium),
      const Spacer(),
      if (MediaQuery.sizeOf(context).width >= 600)
        Text('THE MOTION PLAYGROUND', style: Theme.of(context).textTheme.labelSmall),
      IconButton(
        onPressed: widget.onTheme,
        tooltip: widget.dark ? 'Use light theme' : 'Use dark theme',
        icon: Icon(widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      ),
    ],
  );

  Widget _stage(BuildContext context) {
    final CameraController? camera = _session.camera;
    final bool previewReady = _live && camera != null && camera.value.isInitialized;
    final double aspect = previewReady ? _session.aspectRatio : 3 / 4;
    final bool burpees = _exercise == Exercise.burpees;
    final String feedback = !_live
        ? 'Meet your movement buddy.'
        : _paused
        ? 'Set paused'

        : _faceMode
        ? 'Make it your own.'
        : burpees
        ? 'Next: ${_burpees.stage.label}'
        : _counter.instruction;

    return Column(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: ColoredBox(
            color: const Color(0xFFE3EAD7),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).width < 600 ? 430 : 570,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const CustomPaint(painter: _StageBackdrop()),
                  Center(
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          if (previewReady) CameraPreview(camera),
                          if (!_live && _faceMode) const CustomPaint(painter: _DemoHead()),
                          AnimatedBuilder(
                            animation: _animation,
                            builder: (BuildContext context, Widget? child) {
                              final double phase = MediaQuery.disableAnimationsOf(context)
                                  ? .15
                                  : _animation.value;
                              final List<NormalizedLandmark> pose = _live
                                  ? _session.pose
                                  : _faceMode
                                  ? <NormalizedLandmark>[]
                                  : demoPose(phase);
                              final List<NormalizedLandmark> face = _live
                                  ? _session.face
                                  : _faceMode
                                  ? demoFace(phase)
                                  : <NormalizedLandmark>[];

                              return RepaintBoundary(
                                child: CustomPaint(
                                  painter: TrackingOverlay(
                                    pose: pose,
                                    face: face,
                                    style: _style,
                                    accessories: _accessories,
                                    accent: _accent,
                                    mirrored:
                                        previewReady &&
                                        camera.description.lensDirection ==
                                            CameraLensDirection.front,
                                    showPoints: _points,
                                    opacity: _opacity,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 18,
                    left: 18,
                    right: 18,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _Badge(
                          label: _live
                              ? (_session.loading
                                    ? 'LOADING MODEL'
                                    : previewReady
                                    ? '● LIVE CAMERA'
                                    : 'CAMERA UNAVAILABLE')
                              : '◌ ANIMATED DEMO',
                          color: _live ? _lime : Colors.white,
                        ),
                        _Badge(
                          label: _faceMode ? '3D FACE PLAY' : _exercise.label.toUpperCase(),
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                  if (_session.loading) const Center(child: CircularProgressIndicator()),
                  Positioned(
                    bottom: 22,
                    left: 20,
                    right: 20,
                    child: _Badge(label: feedback, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (!_faceMode) ...<Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(22)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$_reps'.padLeft(2, '0'),
                  style: const TextStyle(
                    color: _lime,
                    fontFamily: 'Fredoka',
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'REPS THIS SET',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () {
                setState(() => _live = !_live);
                _configure();
              },
              icon: Icon(_live ? Icons.videocam_off_outlined : Icons.videocam_outlined),
              label: Text(_live ? 'Use demo' : 'Start camera'),
            ),
            if (_live)
              OutlinedButton.icon(
                onPressed: _session.loading
                    ? null
                    : () {
                        setState(() => _front = !_front);
                        _configure();
                      },
                icon: const Icon(Icons.cameraswitch_outlined),
                label: const Text('Flip'),
              ),
            if (_live && !_faceMode)
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _paused = !_paused;
                    final int reps = _counter.reps;
                    final int burpeeReps = _burpees.reps;
                    _reset();
                    _counter.reps = reps;
                    _burpees.reps = burpeeReps;
                  });
                },
                icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                label: Text(_paused ? 'Resume' : 'Pause'),
              ),
            if (!_faceMode)
              OutlinedButton.icon(
                onPressed: () => setState(_reset),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset set'),
              ),
            if (_live && !previewReady && !_session.loading)
              OutlinedButton(onPressed: _configure, child: const Text('Retry camera')),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          child: Text(
            _live
                ? _session.status
                : 'Demo preview · switch on your camera to track real movement.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (_live && previewReady)
          Text('${_session.latencyMs} ms inference', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  Widget _controls(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _sectionTitle(
              context,
              _faceMode ? '01' : '01',
              _faceMode ? 'Your alter ego' : 'Pick your move',
            ),
            const SizedBox(height: 6),
            Text(
              _faceMode
                  ? 'Stack a few accessories. Turn your head.'
                  : '10 ways to get a little more animated.',
            ),
            const SizedBox(height: 18),
            if (_faceMode) ...<Widget>[
              for (final FaceAccessory accessory in FaceAccessory.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(accessory.label),
                  subtitle: Text(switch (accessory) {
                    FaceAccessory.glasses => 'Sculpted rims + tinted lenses',
                    FaceAccessory.crown => 'A little main-character energy',
                    FaceAccessory.robotEars => 'Tune in to your inner robot',
                  }),

                  value: _accessories.contains(accessory),
                  onChanged: (bool? enabled) => setState(() {
                    _accessories = <FaceAccessory>{..._accessories};
                    if (enabled ?? false) {
                      _accessories.add(accessory);
                    } else {
                      _accessories.remove(accessory);
                    }
                  }),
                ),
              const SizedBox(height: 10),
              const Text(
                '3D meshes follow eye spacing, head tilt and depth. Face studio tracks one face at a time.',
              ),
            ] else ...<Widget>[
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final Exercise exercise in Exercise.values)
                      SizedBox(
                        width: (constraints.maxWidth - 8) / 2,
                        child: _ExerciseTile(
                          exercise: exercise,
                          selected: _exercise == exercise,
                          onTap: () => setState(() {
                            _exercise = exercise;
                            _reset();
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(_exercise.cameraGuide, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(_exercise.cue),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _live
                      ? (_exercise == Exercise.burpees ? _burpees.stage.index / 5 : _counter.depth)
                      : 0,
                  minHeight: 8,
                  backgroundColor: _green.withValues(alpha: .1),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Movement depth · complete a full cycle to count',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _sectionTitle(context, '02', 'Make it look like you'),
            const SizedBox(height: 16),
            if (!_faceMode)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final SkeletonStyle style in SkeletonStyle.values)
                    ChoiceChip(
                      label: Text(style.label),
                      selected: style == _style,
                      onSelected: (_) => setState(() => _style = style),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text('Color pop', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                for (final (Color color, String name) in <(Color, String)>[
                  (_orange, 'Coral'),
                  (_lime, 'Lime'),
                  (const Color(0xFF7DCBE0), 'Sky'),
                  (const Color(0xFFCDA2E8), 'Lilac'),
                ])
                  Semantics(
                    label: '$name accent',
                    selected: _accent == color,
                    child: IconButton(
                      tooltip: '$name accent',
                      onPressed: () => setState(() => _accent = color),
                      icon: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _accent == color ? _ink : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Row(
              children: <Widget>[
                const Text('Overlay'),
                Expanded(
                  child: Slider(
                    value: _opacity,
                    min: .2,
                    label: '${(_opacity * 100).round()}%',
                    onChanged: (double value) => setState(() => _opacity = value),
                  ),
                ),
                Text('${(_opacity * 100).round()}%'),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show tracking points'),
              value: _points,
              onChanged: (bool value) => setState(() => _points = value),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _lime, borderRadius: BorderRadius.circular(22)),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.wb_sunny_outlined, color: _ink),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'A little room. A little light.\nKeep the joints for your move in frame. These example counters estimate motion; they do not assess exercise form.',
                style: TextStyle(color: _ink, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _sectionTitle(BuildContext context, String number, String title) => Row(
    children: <Widget>[
      Text(
        number,
        style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
      side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .12)),
    ),
    child: Padding(padding: const EdgeInsets.all(22), child: child),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(30)),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: _ink,
        fontWeight: FontWeight.w800,
        fontSize: 10,
        letterSpacing: .6,
      ),
    ),
  );
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.exercise, required this.selected, required this.onTap});
  final Exercise exercise;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: Material(
      color: selected ? _green : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    switch (exercise) {
                      Exercise.squats ||
                      Exercise.lunges => Icons.airline_seat_legroom_extra_rounded,
                      Exercise.pressUps || Exercise.curls => Icons.fitness_center_rounded,
                      Exercise.burpees || Exercise.starJumps => Icons.accessibility_new_rounded,
                      Exercise.lateralRaises => Icons.open_with_rounded,
                      Exercise.highKnees => Icons.directions_run_rounded,
                      Exercise.sitUps || Exercise.sideBends => Icons.self_improvement_rounded,
                    },
                    color: selected ? _lime : Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                  const Spacer(),
                  if (selected) const Icon(Icons.check_circle, color: _lime, size: 16),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                exercise.label,
                style: TextStyle(
                  color: selected ? Colors.white : null,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                exercise.group,
                style: TextStyle(
                  color: selected ? _lime : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 8,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StageBackdrop extends CustomPainter {
  const _StageBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dot = Paint()..color = _green.withValues(alpha: .12);

    for (double x = 18; x < size.width; x += 24) {
      for (double y = 18; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * .85),
        width: size.width * .65,
        height: 55,
      ),
      Paint()..color = _green.withValues(alpha: .09),
    );
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .44),
      math.min(size.width * .39, 205),
      Paint()..color = Colors.white.withValues(alpha: .22),
    );
  }

  @override
  bool shouldRepaint(covariant _StageBackdrop oldDelegate) => false;
}

class _DemoHead extends CustomPainter {
  const _DemoHead();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect face = Rect.fromLTRB(
      size.width * .25,
      size.height * .21,
      size.width * .75,
      size.height * .8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(face.inflate(3), const Radius.circular(100)),
      Paint()..color = _ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(face, const Radius.circular(100)),
      Paint()..color = const Color(0xFFF2BF92),
    );

    for (final double x in <double>[.41, .59]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(size.width * x, size.height * .44), width: 10, height: 16),
        Paint()..color = _ink,
      );
    }

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * .5, size.height * .61),
        width: size.width * .18,
        height: size.height * .08,
      ),
      0,
      math.pi,
      false,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(covariant _DemoHead oldDelegate) => false;
}
