import 'package:flutter/material.dart';
import '../core/theme.dart';



class ElderButton extends StatelessWidget {
  
  final String text;
  
  
  final IconData? icon;
  
  
  final VoidCallback? onPressed;
  
  
  final ElderButtonType type;
  
  
  final bool isLoading;
  
  
  final Color? color;
  
  
  final bool fullWidth;

  const ElderButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
    this.type = ElderButtonType.primary,
    this.isLoading = false,
    this.color,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: ElderTheme.buttonHeight,
      child: _buildButton(context),
    );
  }

  Widget _buildButton(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: ElderTheme.iconSize),
                const SizedBox(width: 12),
              ],
              Text(
                text,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );

    switch (type) {
      case ElderButtonType.primary:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? ElderTheme.primaryColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: ElderTheme.primaryColor.withOpacity(0.6),
          ),
          child: child,
        );

      case ElderButtonType.success:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? ElderTheme.successColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: ElderTheme.successColor.withOpacity(0.6),
          ),
          child: child,
        );

      case ElderButtonType.warning:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? ElderTheme.warningColor,
            foregroundColor: ElderTheme.textPrimary,
            disabledBackgroundColor: ElderTheme.warningColor.withOpacity(0.6),
          ),
          child: child,
        );

      case ElderButtonType.danger:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? ElderTheme.elderAccent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: ElderTheme.elderAccent.withOpacity(0.6),
          ),
          child: child,
        );

      case ElderButtonType.outline:
        return OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: color ?? ElderTheme.primaryColor,
            side: BorderSide(
              color: color ?? ElderTheme.primaryColor,
              width: 2.5,
            ),
          ),
          child: child,
        );

      case ElderButtonType.text:
        return TextButton(
          onPressed: isLoading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: color ?? ElderTheme.primaryColor,
          ),
          child: child,
        );
    }
  }
}


class ElderBigButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  final bool isLoading;

  const ElderBigButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
    this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: ElderTheme.bigButtonHeight,
      decoration: BoxDecoration(
        color: color ?? ElderTheme.successColor,
        borderRadius: BorderRadius.circular(ElderTheme.cardRadius),
        boxShadow: [
          BoxShadow(
            color: (color ?? ElderTheme.successColor).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(ElderTheme.cardRadius),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: ElderTheme.largeIconSize,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 16),
                      ],
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}


enum ElderButtonType {
  primary,   
  success,   
  warning,   
  danger,    
  outline,   
  text,      
}


class ElderIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? backgroundColor;
  final double? size;

  const ElderIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
    this.backgroundColor,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size ?? 160,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: backgroundColor ?? ElderTheme.cardColor,
          borderRadius: BorderRadius.circular(ElderTheme.cardRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: (iconColor ?? ElderTheme.primaryColor).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                size: ElderTheme.largeIconSize,
                color: iconColor ?? ElderTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ElderTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
