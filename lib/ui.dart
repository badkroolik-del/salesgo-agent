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
/// Asl SalesGO logosi — rasm (1:1 piksel, qayta chizilmagan).
/// [onDark] — qorong'i fonda oq plitka ichida ko'rsatiladi (logo ranglari o'zgarmaydi).
class BrandLogo extends StatelessWidget {
  final double height;
  final bool onDark;
  final bool full;
  const BrandLogo({super.key, this.height = 28, this.onDark = false, this.full = false});
  @override
  Widget build(BuildContext context) {
    final img = Image.asset(full ? 'assets/brand/logo_full.png' : 'assets/brand/logo.png',
        height: height, filterQuality: FilterQuality.high, semanticLabel: 'SalesGO');
    if (!onDark) return img;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: height * 0.45, vertical: height * 0.30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(height * 0.6),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: img,
    );
  }
}

/// Faqat belgi (navy ❯ + yashil ▶) — aylanib turuvchi yumshoq halqalar bilan (splash/yuklanish).
class AnimatedLogo extends StatefulWidget {
  final double size;
  const AnimatedLogo({super.key, this.size = 96});
  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(size: Size(s, s), painter: _RingPainter(_c.value))),
        Image.asset('assets/brand/mark.png', width: s * 0.46, filterQuality: FilterQuality.high),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double t;
  _RingPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    for (int i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      canvas.drawCircle(
          c,
          maxR * (0.5 + p * 0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = brandGreen.withOpacity((1 - p) * 0.35));
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t;
}

/// Eski API bilan mos: [base] oq bo'lsa (qorong'i fon) — logo oq plitkada.
class Wordmark extends StatelessWidget {
  final double size;
  final Color base;
  const Wordmark({super.key, this.size = 26, this.base = ink});
  @override
  Widget build(BuildContext context) =>
      BrandLogo(height: size * 1.05, onDark: base.computeLuminance() > 0.6);
}

class AnimatedWordmark extends StatelessWidget {
  final double size;
  final Color base;
  const AnimatedWordmark({super.key, this.size = 30, this.base = ink});
  @override
  Widget build(BuildContext context) =>
      BrandLogo(height: size * 1.05, onDark: base.computeLuminance() > 0.6);
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
  final bool compact;
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.isMoney = false,
    this.color = brand,
    this.onTap,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final ip = compact ? 7.0 : 9.0;
    final isz = compact ? 17.0 : 20.0;
    final vf = compact ? 17.0 : 21.0;
    final lf = compact ? 10.5 : 12.0;
    return Panel(
      padding: EdgeInsets.all(compact ? 11 : 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(ip),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(compact ? 10 : 12)),
            child: Icon(icon, color: color, size: isz),
          ),
          SizedBox(height: compact ? 8 : 12),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(
              isMoney ? shortMoney(v) : v.round().toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: vf, fontWeight: FontWeight.w900, color: ink),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: lf, color: muted, fontWeight: FontWeight.w600)),
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
