import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'state.dart';

String two(int n) => n.toString().padLeft(2, '0');
String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String fmtEv(int t) {
  final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
  return '${two(d.day)}/${two(d.month)} ${hm(d)}';
}

IconData netIcon(Net n) => n == Net.ap ? Icons.wifi_tethering : (n == Net.sta ? Icons.wifi : Icons.cloud_outlined);

class Panel extends StatelessWidget {
  final Widget child;
  final Color? color, border;
  final EdgeInsetsGeometry padding, margin;
  final VoidCallback? onTap;
  const Panel({
    super.key,
    required this.child,
    this.color,
    this.border,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? cs.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: border ?? cs.outlineVariant.withValues(alpha: .5),
            width: border == null ? 1 : 2,
          ),
        ),
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

Widget heading(BuildContext c, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(t, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    );

class ConnChip extends StatelessWidget {
  final AppState s;
  const ConnChip(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final col = s.connected ? Colors.green.shade600 : Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: col.withValues(alpha: .14), borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(netIcon(s.net), size: 16, color: col),
        const SizedBox(width: 6),
        Text(s.connected ? netNames[s.net]! : 'Offline',
            style: TextStyle(color: col, fontWeight: FontWeight.w600, fontSize: 12)),
      ]),
    );
  }
}

class Stat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color? color;
  const Stat(this.icon, this.label, this.value, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Panel(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}

class GaugePainter extends CustomPainter {
  final double v, mark;
  final Color track, fill, tick;
  GaugePainter(this.v, this.mark, this.track, this.fill, this.tick);

  @override
  void paint(Canvas c, Size s) {
    final r = s.shortestSide / 2 - 16;
    final ctr = s.center(Offset.zero);
    final rect = Rect.fromCircle(center: ctr, radius: r);
    const start = 2.356, sweep = 4.712;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    c.drawArc(rect, start, sweep, false, p..color = track);
    c.drawArc(rect, start, sweep * math.min(1.0, math.max(0.0, v)), false, p..color = fill);
    final a = start + sweep * mark;
    c.drawLine(
      ctr + Offset(math.cos(a), math.sin(a)) * (r - 16),
      ctr + Offset(math.cos(a), math.sin(a)) * (r + 16),
      Paint()
        ..color = tick
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(GaugePainter o) => true;
}

void _txt(Canvas c, String t, Offset o, Color col) {
  final tp = TextPainter(
    text: TextSpan(text: t, style: TextStyle(fontSize: 10, color: col)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, o);
}

class ChartPainter extends CustomPainter {
  final List<Sample> d;
  final double Function(Sample) val;
  final double lo, hi;
  final double? mark;
  final Color line, grid, text;
  ChartPainter(this.d, this.val, this.lo, this.hi, this.mark, this.line, this.grid, this.text);

  @override
  void paint(Canvas c, Size s) {
    const lp = 30.0;
    final w = s.width - lp, h = s.height - 16;
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = h * i / 4;
      c.drawLine(Offset(lp, y), Offset(s.width, y), gp);
      if (i % 2 == 0) _txt(c, (hi - (hi - lo) * i / 4).toStringAsFixed(0), Offset(0, y - 6), text);
    }
    if (d.length < 2) return;
    final t0 = d.first.t;
    final span = math.max(1, d.last.t - t0);
    double yv(double v) => h * (1 - ((v - lo) / (hi - lo)).clamp(0.0, 1.0));
    final p = Path(), f = Path();
    for (var i = 0; i < d.length; i++) {
      final x = lp + w * (d[i].t - t0) / span;
      final y = yv(val(d[i]));
      if (i == 0) {
        p.moveTo(x, y);
        f.moveTo(x, h);
        f.lineTo(x, y);
      } else {
        p.lineTo(x, y);
        f.lineTo(x, y);
      }
    }
    f.lineTo(lp + w, h);
    f.close();
    c.drawPath(f, Paint()..color = line.withValues(alpha: .15));
    c.drawPath(
      p,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    if (mark != null) {
      final y = yv(mark!);
      c.drawLine(Offset(lp, y), Offset(s.width, y), Paint()
        ..color = Colors.orange
        ..strokeWidth = 1.4);
    }
    _txt(c, hm(DateTime.fromMillisecondsSinceEpoch(d.first.t * 1000)), Offset(lp, h + 3), text);
    _txt(c, hm(DateTime.fromMillisecondsSinceEpoch(d.last.t * 1000)), Offset(s.width - 30, h + 3), text);
  }

  @override
  bool shouldRepaint(ChartPainter o) => true;
}
