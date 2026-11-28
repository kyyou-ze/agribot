import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'state.dart';

String two(int n) => n.toString().padLeft(2, '0');
String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String fmtEv(int t) {
  final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
  return '${two(d.day)}/${two(d.month)} ${hm(d)}';
}

IconData netIcon(Net n) => n == Net.lan ? Icons.wifi : Icons.cloud_outlined;

/// Kartu dasar: sudut besar, tanpa garis tepi, bayangan lembut. [gradient] untuk kartu utama.
class Panel extends StatelessWidget {
  final Widget child;
  final Color? color, border;
  final Gradient? gradient;
  final EdgeInsetsGeometry padding, margin;
  final VoidCallback? onTap;
  const Panel({
    super.key,
    required this.child,
    this.color,
    this.border,
    this.gradient,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.margin = const EdgeInsets.only(bottom: 14),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = color ?? (dark ? cs.surfaceContainerHigh : cs.surfaceContainerLowest);
    final radius = BorderRadius.circular(26);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: dark ? 0 : .06), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Material(
          color: gradient == null ? base : Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: border == null ? BorderSide.none : BorderSide(color: border!, width: 2),
          ),
          child: Ink(
            decoration: gradient == null ? null : BoxDecoration(gradient: gradient),
            child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
          ),
        ),
      ),
    );
  }
}

Widget heading(BuildContext c, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      child: Text(
        t.toUpperCase(),
        style: Theme.of(c).textTheme.labelLarge?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: Theme.of(c).colorScheme.onSurfaceVariant,
            ),
      ),
    );

/// Gaya kolom isian seragam (isi terang, tanpa garis tepi).
InputDecoration dec(BuildContext c, {String? label, String? hint, String? helper}) {
  final cs = Theme.of(c).colorScheme;
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    filled: true,
    fillColor: cs.surfaceContainerHighest.withValues(alpha: .55),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

class ConnChip extends StatelessWidget {
  final AppState s;
  const ConnChip(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = s.connected && s.online;
    final fg = ok ? cs.primary : (s.connected ? cs.error : cs.outline);
    final label = !s.connected ? 'Offline' : (!s.online ? 'Alat offline' : netNames[s.via]!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: fg.withValues(alpha: .12), borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(s.connected ? netIcon(s.via) : Icons.cloud_off_outlined, size: 16, color: fg),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

/// Angka kecil di kartu utama (suhu, udara, tangki).
class MiniStat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const MiniStat(this.icon, this.label, this.value, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: .85))),
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
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
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
