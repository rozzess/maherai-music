import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Tiny animated equalizer bars shown on the currently playing row.
class PlayingBars extends StatefulWidget {
  final bool animate;
  final double size;
  const PlayingBars({super.key, this.animate = true, this.size = 18});

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _BarsPainter(_c.value, widget.animate),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final double t;
  final bool animate;
  _BarsPainter(this.t, this.animate);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MTheme.accent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width / 6;
    for (var i = 0; i < 3; i++) {
      final phase = t * 2 * pi + i * 2.1;
      final h = animate
          ? size.height * (0.35 + 0.32 * (1 + sin(phase)) / 2)
          : size.height * 0.3;
      final x = size.width * (0.2 + 0.3 * i);
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.t != t || old.animate != animate;
}
