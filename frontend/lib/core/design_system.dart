import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const ink = Color(0xFF0A2547);
  static const ink2 = Color(0xFF1A436C);
  static const muted = Color(0xFF5B7692);
  static const muted2 = Color(0xFF8297A9);
  static const blue = Color(0xFF3A91F5);
  static const blueDeep = Color(0xFF1763D8);
  static const cyan = Color(0xFF58D8F5);
  static const mint = Color(0xFF4ED6B2);
  static const mintDeep = Color(0xFF1BA98B);
  static const lavender = Color(0xFFA78BFA);
  static const peach = Color(0xFFFFB27A);
  static const coral = Color(0xFFFF7A84);
  static const red = Color(0xFFE14D56);
  static const white = Colors.white;
  static const line = Color(0x2E73A1CE);
  static const blueTint = Color(0xFFE8F6FF);
  static const mintTint = Color(0xFFE3FBF3);
  static const peachTint = Color(0xFFFFF1E7);
  static const lavenderTint = Color(0xFFF1EDFF);
  static const redTint = Color(0xFFFFF0F1);
}

class AppGradients {
  AppGradients._();

  static const background = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFBFDFF), Color(0xFFF1FAFF), Color(0xFFE3F3FF)],
    stops: [0.0, 0.48, 1.0],
  );

  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF69D8F3), Color(0xFF4399F4), Color(0xFF2E76DE)],
    stops: [0.0, 0.52, 1.0],
  );

  static const heroSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF75DAF0), Color(0xFF4CA3F3), Color(0xFF3A7FE2)],
  );

  static const primaryButton = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF55D4F3), Color(0xFF3D91F6), Color(0xFF256DE1)],
  );

  static const mintButton = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF72E8C7), Color(0xFF38BBA2)],
  );

  static const redButton = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFF9B9B), Color(0xFFE95562)],
  );

  static const glass = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xE6FFFFFF), Color(0xB8FFFFFF)],
  );

  static const glassSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xCFFFFFFF), Color(0x96FFFFFF)],
  );
}

class AppShadows {
  AppShadows._();

  static const card = [BoxShadow(color: Color(0x1F216BAA), blurRadius: 30, offset: Offset(0, 14))];

  static const soft = [BoxShadow(color: Color(0x14216BAA), blurRadius: 18, offset: Offset(0, 8))];

  static const blue = [BoxShadow(color: Color(0x483388EE), blurRadius: 26, offset: Offset(0, 13))];
}

class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.child, this.gradient});

  final Widget child;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient ?? AppGradients.background),
      child: child,
    );
  }
}

class AppGlassCard extends StatelessWidget {
  const AppGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.radius = 24,
    this.color,
    this.border,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;
  final Border? border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        gradient: color == null ? AppGradients.glass : null,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.96)),
        boxShadow: shadow ? AppShadows.card : null,
      ),
      child: child,
    );

    if (onTap == null) return Padding(padding: margin, child: content);
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(radius), child: content),
      ),
    );
  }
}

class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    this.size = 54,
    this.iconSize = 27,
    this.gradient,
    this.color,
    this.background,
    this.radius,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Gradient? gradient;
  final Color? color;
  final Color? background;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        color: background,
        borderRadius: BorderRadius.circular(radius ?? size * 0.33),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: const [
          BoxShadow(color: Color(0x12215E96), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Icon(icon, size: iconSize, color: color ?? AppColors.blue),
    );
  }
}

class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.icon,
    this.background = AppColors.blueTint,
    this.foreground = const Color(0xFF2676C9),
    this.borderColor,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
  });

  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 3, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class AppGradientButton extends StatelessWidget {
  const AppGradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.gradient = AppGradients.primaryButton,
    this.height = 62,
    this.fontSize = 21,
    this.foreground = Colors.white,
    this.loading = false,
    this.shadow = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Gradient gradient;
  final double height;
  final double fontSize;
  final Color foreground;
  final bool loading;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.56,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(21),
          boxShadow: shadow ? AppShadows.blue : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(21),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: foreground),
                    )
                  else if (icon != null)
                    Icon(icon, size: 24, color: foreground),
                  if (loading || icon != null) const SizedBox(width: 9),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 56,
    this.fontSize = 18,
    this.foreground = const Color(0xFF2869B3),
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final double fontSize;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 22),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: Colors.white.withValues(alpha: 0.64),
          side: BorderSide(color: foreground.withValues(alpha: 0.28), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle({super.key, required this.title, this.trailing, this.padding});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(2, 16, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.ink2,
                height: 1.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.background = const Color(0xB8EBF9FF),
    this.foreground = const Color(0xFF537594),
    this.iconColor = const Color(0xFF3F91D9),
  });

  final String text;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: iconColor),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: foreground,
                fontSize: 17,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppMenuTile extends StatelessWidget {
  const AppMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor = AppColors.blue,
    this.iconBackground = AppColors.blueTint,
    this.onTap,
    this.trailing,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color iconColor;
  final Color iconBackground;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: [
            AppIconTile(
              icon: icon,
              size: 46,
              iconSize: 24,
              background: danger ? AppColors.redTint : iconBackground,
              color: danger ? AppColors.red : iconColor,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: danger ? AppColors.red : AppColors.ink,
                      height: 1.25,
                    ),
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, color: AppColors.muted2, height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ?? const Icon(Icons.chevron_right_rounded, color: Color(0xFF9BAEBD), size: 23),
          ],
        ),
      ),
    );
  }
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.icon = Icons.elderly_rounded,
    this.size = 76,
    this.tint = AppColors.blueTint,
    this.imageUrl,
  });

  final IconData icon;
  final double size;
  final Color tint;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(icon, size: size * 0.48, color: AppColors.blue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x1F2A6FB0), blurRadius: 22, offset: Offset(0, 10)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null || imageUrl!.isEmpty
          ? fallback
          : Image.network(
              imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}

class AppCircleButton extends StatelessWidget {
  const AppCircleButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.filled = false,
    this.size = 46,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: filled ? AppGradients.primaryButton : null,
        color: filled ? null : Colors.white.withValues(alpha: 0.72),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: const [
          BoxShadow(color: Color(0x18215E96), blurRadius: 16, offset: Offset(0, 7)),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        color: filled ? Colors.white : const Color(0xFF1F4E7E),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
      ),
    );
    return button;
  }
}

class AppFloatingNavBar extends StatelessWidget {
  const AppFloatingNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.largeText = false,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool largeText;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Container(
        height: largeText ? 80 : 74,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: Colors.white),
          boxShadow: const [
            BoxShadow(color: Color(0x2E266AA6), blurRadius: 28, offset: Offset(0, 14)),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final item = items[index];
            final selected = currentIndex == index;
            return Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onTap(index),
                  borderRadius: BorderRadius.circular(19),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.blueTint : Colors.transparent,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selected ? item.selectedIcon : item.icon,
                          size: largeText ? 29 : 26,
                          color: selected ? const Color(0xFF176AC5) : const Color(0xFF788EA5),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: largeText ? 19 : 13,
                            fontWeight: FontWeight.w700,
                            color: selected ? const Color(0xFF176AC5) : const Color(0xFF788EA5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class AppNavItem {
  const AppNavItem({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
