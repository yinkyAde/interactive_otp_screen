import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const OtpVerifyDemo(),
    );
  }
}

class OtpVerifyDemo extends StatefulWidget {
  const OtpVerifyDemo({super.key});
  @override
  State<OtpVerifyDemo> createState() => _OtpVerifyDemoState();
}

class _OtpVerifyDemoState extends State<OtpVerifyDemo>
    with TickerProviderStateMixin {
  static const int digitsCount = 4;
  static const Color accent = Color(0xFFFF5A2C);

  // Visual constants (field == morph tile size)
  static const double boxSize = 72.0;
  static const double boxRadius = 16.0;
  static const double borderStroke = 2.4;

  final List<String> _digits = List.filled(digitsCount, '');
  final FocusNode _focus = FocusNode();
  final TextEditingController _text = TextEditingController();

  int _selected = -1;
  bool _done = false;

  // typing pulse
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  // master timeline (runs AFTER last digit is entered)
  late final AnimationController _master = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2900),
  );

  // success tile sweep (loops after success)
  late final AnimationController _checkSweepCtrl =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  // post-morph “exhale”
  late final AnimationController _exhaleCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  bool _glowRunning = false;
  bool _exhaleStarted = false;

  // phases on master
  late final Animation<double> _sweep;        // global sweep around all 4 boxes (only after 4th entry)
  late final Animation<double> _collapse;     // fields converge
  late final Animation<double> _boxesFade;    // fields fade after full overlap
  late final Animation<double> _morphFadeIn;  // morph tile fades in after overlap
  late final Animation<double> _checkReveal;  // check fades in last

  // header cross-fade
  late final Animation<double> _verifyTitleOpacity;
  late final Animation<double> _successTitleOpacity;
  late final Animation<double> _verifySubtitleOpacity;

  bool get _isSuccessPhase => _checkReveal.value > 0.02 || _done;

  double _smooth(double t) => (t * t * (3 - 2 * t)).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();

    // Sweep should start IMMEDIATELY once the 4th digit is entered.
    _sweep = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.00, 0.44, curve: Curves.easeInOutCubic),
    );

    // Merge: long and smooth; completes before morph/check appear.
    _collapse = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.44, 0.90, curve: Curves.easeInOutCubicEmphasized),
    );

    // Keep fields fully visible until overlap is complete, then fade them.
    _boxesFade = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.92, 0.98, curve: Curves.easeOut),
    );

    // Morph tile starts only AFTER full merge
    _morphFadeIn = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.94, 1.00, curve: Curves.easeInOut),
    );

    // Check icon appears last
    _checkReveal = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.96, 1.00, curve: Curves.easeOutCubic),
    );

    // silky header crossfade
    _verifyTitleOpacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.70, 0.995, curve: Curves.easeInOutSine),
      ),
    );
    _successTitleOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.72, 0.998, curve: Curves.easeInOutSine),
      ),
    );
    _verifySubtitleOpacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.72, 0.995, curve: Curves.easeInOutSine),
      ),
    );

    // Start sweep + exhale triggers (success tile)
    _master.addListener(() {
      if (_checkReveal.value > 0.02 && !_glowRunning) {
        _checkSweepCtrl.repeat();
        _glowRunning = true;
      }
      if (_checkReveal.value > 0.85 && !_exhaleStarted) {
        _exhaleCtrl
          ..reset()
          ..forward();
        _exhaleStarted = true;
      }
    });

    _master.addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _master.dispose();
    _checkSweepCtrl.dispose();
    _exhaleCtrl.dispose();
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _handleInput(String value) {
    final clean = value.replaceAll(RegExp(r'\D'), '');
    _text.value = TextEditingValue(
      text: clean,
      selection: TextSelection.collapsed(offset: clean.length),
    );

    for (int i = 0; i < digitsCount; i++) {
      _digits[i] = i < clean.length ? clean[i] : '';
    }

    final len = _text.text.length;
    setState(() => _selected = len < digitsCount ? len : digitsCount - 1);

    // IMPORTANT:
    // - For lengths 1..3, no global sweep. Just show per-box "entered" border (handled in _OtpBox).
    // - On the 4th entry (len == 4), we start the master timeline which triggers the global sweep across ALL fields.
    if (len == digitsCount) {
      _focus.unfocus();
      if (!_master.isAnimating && _master.value == 0) {
        _master.forward(); // starts sweep immediately (Interval 0.00→0.44)
      }
    } else {
      setState(() => _done = false);
      // If the user deletes, stop the master so sweep doesn't run.
      if (_master.isAnimating || _master.value > 0) {
        _master.stop();
        _master.reset();
        _checkSweepCtrl.stop();
        _checkSweepCtrl.reset();
        _exhaleCtrl.reset();
        _glowRunning = false;
        _exhaleStarted = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final w = media.size.width;
    final scale = media.textScaleFactor.clamp(1.0, 1.6);
    const spacing = 16.0;

    // header geometry
    final double headerHeight = 136 * (scale <= 1.2 ? 1.0 : 1.1);
    const double headerTopPad = 24;
    const double subtitleGap = 8;
    final double subtitleBlockHeight = 44 * (scale <= 1.1 ? 1.0 : 1.15);

    const TextStyle titleStyle =
    TextStyle(fontSize: 26, fontWeight: FontWeight.w700);
    final TextStyle subStyle = TextStyle(
      height: 1.25,
      color: Colors.white.withOpacity(.65),
    );

    // Exhale bell-curve (0→1→0)
    final exhaleUp = CurvedAnimation(
      parent: _exhaleCtrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );
    final exhaleDown = CurvedAnimation(
      parent: _exhaleCtrl,
      curve: const Interval(0.55, 1.0, curve: Curves.easeInCubic),
    );
    final exhaleT =
    _exhaleCtrl.value <= 0.55 ? exhaleUp.value : (1.0 - exhaleDown.value);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F10),
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: math.max(24.0, media.viewInsets.bottom),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(),

                      SizedBox(
                        height: headerHeight,
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.only(top: headerTopPad),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                alignment: Alignment.topCenter,
                                children: [
                                  FadeTransition(
                                    opacity: _verifyTitleOpacity,
                                    child: const Text("Let's verify your number",
                                        style: titleStyle),
                                  ),
                                  FadeTransition(
                                    opacity: _successTitleOpacity,
                                    child: const Text('Verified successfully',
                                        style: titleStyle),
                                  ),
                                ],
                              ),
                              const SizedBox(height: subtitleGap),
                              SizedBox(
                                height: subtitleBlockHeight,
                                child: FadeTransition(
                                  opacity: _verifySubtitleOpacity,
                                  child: Text(
                                    "We've sent a 4-digit code to your phone.\nIt’ll auto-verify once entered.",
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: subStyle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      AnimatedBuilder(
                        animation: Listenable.merge([_pulseCtrl, _master, _exhaleCtrl]),
                        builder: (context, _) {
                          final rowWidth =
                              digitsCount * boxSize + (digitsCount - 1) * spacing;
                          final startX = (w - rowWidth) / 2;
                          final centerX = w / 2 - boxSize / 2;
                          final currentLen = _text.text.length;

                          final mergedT = _smooth(_collapse.value);
                          final fieldsOpacity = (1.0 - _boxesFade.value).clamp(0.0, 1.0);
                          final morphOpacity  = _morphFadeIn.value.clamp(0.0, 1.0);

                          // Tilt tied to merge: rises then settles to 0 before morph.
                          double riseFall(double t, double a, double b) {
                            final x = ((t - a) / (b - a)).clamp(0.0, 1.0);
                            final s = x * x * (3 - 2 * x);
                            return 1.0 - (2.0 * (s - 0.5)).abs();
                          }
                          final tiltFactor = riseFall(_master.value, 0.50, 0.86);

                          // Max tilt angles & slight inward shifts
                          const tiltDeg  = [-14.0, -8.0, 8.0, 14.0]; // Z fan
                          const pitchDeg = [12.0, 9.0, 9.0, 12.0];   // X bottoms out
                          const shiftInDx = [14.0, 6.0, -6.0, -14.0];

                          // Are we in the sweeping phase (only after 4th entry)?
                          final sweepingNow = _master.value > 0 || currentLen == digitsCount;
                          final sweepValue = sweepingNow ? _sweep.value : 0.0;

                          return SizedBox(
                            height: 220,
                            width: w,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // OTP fields — for 1..3 entries: show orange border on entered fields (no sweep).
                                // On the 4th entry: start ONE sweep that runs on ALL fields.
                                Opacity(
                                  opacity: fieldsOpacity,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      for (int i = 0; i < digitsCount; i++)
                                        _OtpBox(
                                          index: i,
                                          char: _digits[i],
                                          startLeft: startX + i * (boxSize + spacing),
                                          endLeft: centerX,
                                          top: 40.0,
                                          size: boxSize,
                                          radius: boxRadius,
                                          borderStroke: borderStroke,
                                          collapseT: mergedT,
                                          pulseT: _pulseCtrl.value,
                                          sweepProgress: sweepValue, // same sweep for all 4 only after last digit
                                          // Style rules:
                                          // - Before last digit: show orange border if this field is filled OR active.
                                          // - On/after last digit: do NOT force orange border; the sweep paints the border.
                                          showEnteredBorder: currentLen < digitsCount
                                              ? (_digits[i].isNotEmpty || _selected == i)
                                              : false,
                                          tiltRadians: (tiltDeg[i] * tiltFactor) * math.pi / 180,
                                          tiltPitchRadians: (pitchDeg[i] * tiltFactor) * math.pi / 180,
                                          inwardDx: shiftInDx[i] * tiltFactor,
                                          inwardDy: 0.0,
                                          active: !_done && _selected == i && currentLen < digitsCount,
                                          onTap: () {
                                            if (_done) return;
                                            setState(() => _selected = i);
                                            FocusScope.of(context).requestFocus(_focus);
                                          },
                                          colorOpacityClamp: (d) => d.clamp(0.0, 1.0),
                                        ),
                                    ],
                                  ),
                                ),

                                // MORPH TILE — appears only AFTER full merge (tiny cross-fade, no cut)
                                if (morphOpacity > 0.0)
                                  Positioned(
                                    top: 40.0,
                                    left: w / 2 - boxSize / 2,
                                    child: Opacity(
                                      opacity: morphOpacity,
                                      child: Transform.scale(
                                        scale: (0.985 + 0.015 * _checkReveal.value) *
                                            (1.0 + 0.04 * (_exhaleCtrl.isAnimating ? exhaleT : 0.0)),
                                        child: SizedBox(
                                          height: boxSize,
                                          width: boxSize,
                                          child: AnimatedBuilder(
                                            animation: _checkSweepCtrl,
                                            builder: (_, __) => CustomPaint(
                                              painter: _CheckGlowPainter(
                                                progress: _checkSweepCtrl.value,
                                                radius: boxRadius - 2,
                                                strokeWidth: 2.0,
                                                accent: accent,
                                                fillColor: const Color(0x22121212),
                                                shadowOpacity: ((0.30 * _checkReveal.value) *
                                                    (1.0 + 0.35 * (_exhaleCtrl.isAnimating ? exhaleT : 0.0)))
                                                    .clamp(0.0, 1.0),
                                                bandBoost: (1.0 + 0.35 * (_exhaleCtrl.isAnimating ? exhaleT : 0.0)),
                                              ),
                                              child: Center(
                                                child: Opacity(
                                                  opacity: _checkReveal.value.clamp(0.0, 1.0),
                                                  child: const Icon(Icons.check_rounded, size: 38, color: Colors.white),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 8),

                      // Hidden TextField (only before success)
                      if (!_isSuccessPhase)
                        Opacity(
                          opacity: 0,
                          child: SizedBox(
                            width: 1,
                            height: 1,
                            child: TextField(
                              autofocus: true,
                              focusNode: _focus,
                              controller: _text,
                              keyboardType: TextInputType.number,
                              maxLength: digitsCount,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: _handleInput,
                              decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                            ),
                          ),
                        ),

                      const SizedBox(height: 18),

                      // Resend (only before success)
                      if (!_isSuccessPhase)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Didn't receive the code? ",
                                style: TextStyle(color: Colors.white.withOpacity(.55))),
                            TextButton(
                              onPressed: () {
                                _text.clear();
                                for (var i = 0; i < digitsCount; i++) {
                                  _digits[i] = '';
                                }
                                setState(() {
                                  _done = false;
                                  _selected = -1;
                                });
                                _master.reset();
                                _checkSweepCtrl.stop();
                                _checkSweepCtrl.reset();
                                _exhaleCtrl.reset();
                                _glowRunning = false;
                                _exhaleStarted = false;
                                FocusScope.of(context).requestFocus(_focus);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.deepOrange,
                                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              child: const Text('Resend'),
                            ),
                          ],
                        ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.index,
    required this.char,
    required this.startLeft,
    required this.endLeft,
    required this.top,
    required this.size,
    required this.radius,
    required this.borderStroke,
    required this.collapseT,
    required this.pulseT,
    required this.sweepProgress,
    required this.showEnteredBorder,
    required this.tiltRadians,
    required this.tiltPitchRadians,
    required this.inwardDx,
    required this.inwardDy,
    required this.active,
    required this.onTap,
    required this.colorOpacityClamp,
  });

  final int index;
  final String char;
  final double startLeft;
  final double endLeft;
  final double top;
  final double size;
  final double radius;
  final double borderStroke;
  final double collapseT;
  final double pulseT;
  final double sweepProgress;      // 0..1, only after last digit
  final bool showEnteredBorder;    // before last digit: show orange border if true
  final double tiltRadians;        // Z rotation (fan)
  final double tiltPitchRadians;   // +X rotation → bottoms OUT
  final double inwardDx;
  final double inwardDy;
  final bool active;
  final VoidCallback? onTap;
  final double Function(double) colorOpacityClamp;

  static const Color accent = Color(0xFFFF5A2C);

  @override
  Widget build(BuildContext context) {
    final left = Tween<double>(begin: startLeft, end: endLeft).transform(collapseT);

    // Before last digit: orange border for entered/active fields, tiny glow if active.
    final typingGlow = active ? (0.22 + 0.28 * pulseT) : 0.0;

    Widget box = Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: (showEnteredBorder ? accent : const Color(0xFF2E2E2F))
              .withOpacity(showEnteredBorder ? 1 : .7),
          width: showEnteredBorder ? 2.0 : 1.2,
        ),
        boxShadow: [
          if (showEnteredBorder && active)
            BoxShadow(
              color: accent.withOpacity(colorOpacityClamp(typingGlow * 0.9)),
              blurRadius: 14,
              spreadRadius: 0.6,
            ),
        ],
      ),
      child: Text(
        char.isEmpty ? '' : char,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );

    // After last digit: draw ONE sweep over every box (no static orange border logic).
    if (sweepProgress > 0) {
      box = Stack(
        alignment: Alignment.center,
        children: [
          box,
          IgnorePointer(
            child: CustomPaint(
              size: Size.square(size + 6),
              painter: _ProgressBorderPainter(
                progress: sweepProgress,
                radius: radius,
                baseWidth: borderStroke,
                tracerWidth: borderStroke + 0.4,
                accent: accent,
              ),
            ),
          ),
        ],
      );
    }

    // 3D tilt (bottom edges out, top in)
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0020)
      ..rotateX(tiltPitchRadians)
      ..rotateZ(tiltRadians);

    box = Transform(
      alignment: Alignment.topCenter,
      transform: m,
      child: box,
    );

    box = Transform.translate(offset: Offset(inwardDx, inwardDy), child: box);

    return Positioned(top: top, left: left, child: GestureDetector(onTap: onTap, child: box));
  }
}

/// Border that builds from 12 o’clock with bright tracer + glow.
class _ProgressBorderPainter extends CustomPainter {
  _ProgressBorderPainter({
    required this.progress,   // 0..1
    required this.radius,
    required this.baseWidth,
    required this.tracerWidth,
    required this.accent,
  });

  final double progress;
  final double radius;
  final double baseWidth;
  final double tracerWidth;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(4),
      Radius.circular(radius),
    );

    final p = progress.clamp(0.0, 1.0);
    const eps = 0.001;

    // Build orange border up to p (12 o'clock)
    final fillShader = SweepGradient(
      colors: [accent, accent, Colors.transparent, Colors.transparent],
      stops: [0.0, (p - eps).clamp(0.0, 1.0), p.clamp(0.0, 1.0), 1.0],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);

    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseWidth
      ..shader = fillShader;

    canvas.drawRRect(rrect, fillPaint);

    // Bright tracer centered at progress
    double a(num v) => v.clamp(0.0, 1.0).toDouble();
    const leadWidth = 0.06; // ~22°
    final leadStart = a(p - leadWidth / 2);
    final leadEnd = a(p + leadWidth / 2);

    final whiteTracer = SweepGradient(
      colors: const [Colors.transparent, Colors.white, Colors.transparent],
      stops: [leadStart, p, leadEnd],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);

    final orangeTracer = SweepGradient(
      colors: [Colors.transparent, accent, Colors.transparent],
      stops: [leadStart, p, leadEnd],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);

    // halo behind tracer
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tracerWidth + 6
      ..color = accent.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(rrect, glowPaint);

    final tracerWhitePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tracerWidth + 0.5
      ..shader = whiteTracer;

    final tracerOrangePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tracerWidth
      ..shader = orangeTracer;

    canvas.drawRRect(rrect, tracerWhitePaint);
    canvas.drawRRect(rrect, tracerOrangePaint);
  }

  @override
  bool shouldRepaint(covariant _ProgressBorderPainter old) =>
      old.progress != progress || old.accent != accent;
}

/// Success tile painter (pulsating tracer loop + halo).
class _CheckGlowPainter extends CustomPainter {
  _CheckGlowPainter({
    required this.progress,     // 0..1 loop
    required this.radius,
    required this.strokeWidth,
    required this.accent,
    required this.fillColor,
    required this.shadowOpacity,
    this.bandBoost = 1.0,       // extra intensity during exhale
  });

  final double progress;
  final double radius;
  final double strokeWidth;
  final Color accent;
  final Color fillColor;
  final double shadowOpacity;   // 0..1
  final double bandBoost;

  @override
  void paint(Canvas canvas, Size size) {
    double a(num v) => v.clamp(0.0, 1.0).toDouble();

    final rect = Offset.zero & size;

    // border path centered on edge
    final borderRRect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(math.max(0.0, radius - strokeWidth / 2)),
    );

    // background + soft shadow
    final rrectFill = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final shadowColor = accent.withOpacity(a(shadowOpacity));
    if (shadowOpacity > 0) {
      final shadowPaint = Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
      canvas.drawRRect(rrectFill.inflate(1.0), shadowPaint);
    }
    final fillPaint = Paint()..color = fillColor;
    canvas.drawRRect(rrectFill, fillPaint);

    // base border
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = accent.withOpacity(a(0.65));
    canvas.drawRRect(borderRRect, base);

    // pulsating band (12 o'clock start)
    final t = (progress % 1.0);
    final rawAmp = (0.6 + 0.4 * math.sin(2 * math.pi * t)) * bandBoost;
    final amp = a(rawAmp);

    const span = 0.14; // ~50°
    final start = a(t - span / 2);
    final end = a(t + span / 2);

    final bandShader = SweepGradient(
      colors: [
        Colors.transparent,
        accent.withOpacity(a(0.95 * amp)),
        Colors.transparent,
      ],
      stops: [start, t, end],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);

    final bandPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 0.8
      ..shader = bandShader;
    canvas.drawRRect(borderRRect, bandPaint);

    // tight halo around band
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 6
      ..color = accent.withValues(alpha:a(0.26 * amp))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(borderRRect, halo);
  }

  @override
  bool shouldRepaint(covariant _CheckGlowPainter old) =>
      old.progress != progress ||
          old.radius != radius ||
          old.strokeWidth != strokeWidth ||
          old.accent != accent ||
          old.fillColor != fillColor ||
          old.shadowOpacity != shadowOpacity ||
          old.bandBoost != bandBoost;
}
