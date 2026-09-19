import 'package:flutter/material.dart';
import 'theme.dart';

const softShadow = [
  BoxShadow(color: Color(0x14101828), blurRadius: 18, offset: Offset(0, 8)),
];

Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = Colors.white,
  });
  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class GradientHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const GradientHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 22),
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: brandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

// ---- Animatsiyali radar logo ----
class AnimatedLogo extends StatefulWidget {
  final double size;
  const AnimatedLogo({super.key, this.size = 96});
  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();
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
        builder: (_, __) => CustomPaint(painter: _LogoPainter(_c.value)),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double t;
  _LogoPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    for (int i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final r = maxR * (0.5 + p * 0.5);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withOpacity((1 - p) * 0.45);
      canvas.drawCircle(c, r, paint);
    }
    final badgeR = maxR * 0.52;
    final rect = Rect.fromCircle(center: c, radius: badgeR);
    final badge = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.white, Color(0xFFE6FFFB)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(badgeR * 0.52));
    canvas.drawRRect(rrect, badge);
    final tp = TextPainter(
      text: TextSpan(
        text: 'S',
        style: TextStyle(
          color: brand,
          fontSize: badgeR * 1.35,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.t != t;
}

class Wordmark extends StatelessWidget {
  final double size;
  final Color base;
  const Wordmark({super.key, this.size = 26, this.base = ink});
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Sales', style: style.copyWith(color: base)),
        ShaderMask(
          shaderCallback: (r) =>
              goGradient.createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
          child: Text('GO', style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}

/// Animatsiyali "SalesGO" — "Sales" yaxlit rang, "GO" to'q sariq + yugurib
/// o'tuvchi yorug'lik (shine). Saytdagi kabi. Ikonsiz.
class AnimatedWordmark extends StatefulWidget {
  final double size;
  final Color base;
  const AnimatedWordmark({super.key, this.size = 30, this.base = ink});
  @override
  State<AnimatedWordmark> createState() => _AnimatedWordmarkState();
}

class _AnimatedWordmarkState extends State<AnimatedWordmark>
    with SingleTickerProviderStateMixin {
  static const _orange = Color(0xFFF97316);
  static const _amber = Color(0xFFFFC24B);
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = TextStyle(
      fontSize: widget.size,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
      height: 1.0,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sales — yaxlit rang
        Text('Sales', style: st.copyWith(color: widget.base)),
        // GO — doim to'q sariq, ustidan oq shine yuguradi
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value;
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment(-1.0 + t * 2.4, 0),
                end: Alignment(-0.2 + t * 2.4, 0),
                colors: const [_orange, Colors.white, _amber, _orange],
                stops: const [0.0, 0.45, 0.6, 1.0],
                tileMode: TileMode.clamp,
              ).createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
              child: Text('GO', style: st.copyWith(color: Colors.white)),
            );
          },
        ),
      ],
    );
  }
}

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool busy;
  final IconData? icon;
  final Gradient gradient;
  final double height;
  const GradientButton({
    super.key,
    required this.text,
    this.onTap,
    this.busy = false,
    this.icon,
    this.gradient = brandGradient,
    this.height = 52,
  });
  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null || busy;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: disabled ? null : gradient,
            color: disabled ? const Color(0xFFCBD5E1) : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Container(
            height: height,
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(text,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final num value;
  final bool isMoney;
  final Color color;
  final VoidCallback? onTap;
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.isMoney = false,
    this.color = brand,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(
              isMoney ? shortMoney(v) : v.round().toString(),
              style: const TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w900, color: ink),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 44});
  @override
  Widget build(BuildContext context) {
    const palette = [brand, info, accent, violet, brand2, warn];
    final n = name.trim();
    final col = palette[(n.isEmpty ? 0 : n.codeUnitAt(0)) % palette.length];
    final parts = n.isEmpty
        ? ['?']
        : n.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.take(2).map((w) => w[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: col.withOpacity(0.15), shape: BoxShape.circle),
      child: Text(initials,
          style: TextStyle(
              color: col, fontWeight: FontWeight.w800, fontSize: size * 0.34)),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, this.color = brand, this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(
        children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, this.icon = Icons.inbox_outlined, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: muted.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class Shimmer extends StatefulWidget {
  final double height;
  final double width;
  final double radius;
  const Shimmer(
      {super.key, this.height = 64, this.width = double.infinity, this.radius = 14});
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1 + _c.value * 2, 0),
            end: Alignment(-0.4 + _c.value * 2, 0),
            colors: const [
              Color(0xFFECEFF3),
              Color(0xFFF7F9FC),
              Color(0xFFECEFF3),
            ],
          ),
        ),
      ),
    );
  }
}

class ListShimmer extends StatelessWidget {
  final int count;
  const ListShimmer({super.key, this.count = 6});
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const Shimmer(height: 72),
    );
  }
}
