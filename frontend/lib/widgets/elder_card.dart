import 'package:flutter/material.dart';
import '../core/theme.dart';


class ElderCard extends StatelessWidget {
  
  final Widget child;
  
  
  final VoidCallback? onTap;
  
  
  final EdgeInsetsGeometry? padding;
  
  
  final EdgeInsetsGeometry? margin;
  
  
  final Color? color;
  
  
  final bool hasShadow;
  
  
  final Border? border;

  const ElderCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.color,
    this.hasShadow = true,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color ?? ElderTheme.cardColor,
        borderRadius: BorderRadius.circular(ElderTheme.cardRadius),
        border: border,
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ElderTheme.cardRadius),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }
}


class ElderFuncCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;

  const ElderFuncCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElderCard(
      onTap: onTap,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (iconColor ?? ElderTheme.primaryColor).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 30,
              color: iconColor ?? ElderTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: ElderTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}


class MedicineCard extends StatelessWidget {
  final String name;
  final String? spec;
  final String? dosage;
  final DateTime? you_xiao_ri_qi;
  final String? status; 
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const MedicineCard({
    super.key,
    required this.name,
    this.spec,
    this.dosage,
    this.you_xiao_ri_qi,
    this.status = 'normal',
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ElderCard(
      onTap: onTap,
      child: Row(
        children: [
          
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _getStatusColor().withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.medication_rounded,
              size: 40,
              color: _getStatusColor(),
            ),
          ),
          const SizedBox(width: 16),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: ElderTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (spec != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    spec!,
                    style: const TextStyle(
                      fontSize: 18,
                      color: ElderTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (dosage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '用法：$dosage',
                    style: const TextStyle(
                      fontSize: 16,
                      color: ElderTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (you_xiao_ri_qi != null) ...[
                  const SizedBox(height: 6),
                  _buildValidDateBadge(),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 28, color: ElderTheme.errorColor),
              onPressed: onDelete,
            )
          else
            const Icon(
              Icons.chevron_right_rounded,
              size: 32,
              color: ElderTheme.textSecondary,
            ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case 'expired':
        return ElderTheme.errorColor;
      case 'expiring':
        return ElderTheme.warningColor;
      default:
        return ElderTheme.successColor;
    }
  }

  Widget _buildValidDateBadge() {
    final isExpired = you_xiao_ri_qi!.isBefore(DateTime.now());
    final isExpiring = !isExpired && 
        you_xiao_ri_qi!.difference(DateTime.now()).inDays <= 7;

    String text;
    Color color;

    if (isExpired) {
      text = '已过期';
      color = ElderTheme.errorColor;
    } else if (isExpiring) {
      text = '${you_xiao_ri_qi!.difference(DateTime.now()).inDays}天后过期';
      color = ElderTheme.warningColor;
    } else {
      text = '有效期至 ${you_xiao_ri_qi!.month}/${you_xiao_ri_qi!.day}';
      color = ElderTheme.successColor;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}


class ElderStatusCard extends StatelessWidget {
  final String elderName;
  final String? elderAvatar;
  final int takenCount;
  final int totalCount;
  final bool hasMissed;
  final VoidCallback? onTap;

  const ElderStatusCard({
    super.key,
    required this.elderName,
    this.elderAvatar,
    required this.takenCount,
    required this.totalCount,
    this.hasMissed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final allTaken = takenCount == totalCount && totalCount > 0;
    
    return ElderCard(
      onTap: onTap,
      border: hasMissed 
          ? Border.all(color: ElderTheme.errorColor.withOpacity(0.5), width: 2)
          : null,
      child: Row(
        children: [
          
          CircleAvatar(
            radius: 36,
            backgroundColor: ElderTheme.primaryColor.withOpacity(0.12),
            backgroundImage: elderAvatar != null ? NetworkImage(elderAvatar!) : null,
            child: elderAvatar == null
                ? const Icon(
                    Icons.person,
                    size: 40,
                    color: ElderTheme.primaryColor,
                  )
                : null,
          ),
          const SizedBox(width: 16),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  elderName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: ElderTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatusBadge(
                      text: '今日 $takenCount/$totalCount',
                      color: allTaken 
                          ? ElderTheme.successColor 
                          : (hasMissed ? ElderTheme.errorColor : ElderTheme.warningColor),
                    ),
                    if (hasMissed) ...[
                      const SizedBox(width: 8),
                      _buildStatusBadge(
                        text: '有漏服',
                        color: ElderTheme.errorColor,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 32,
            color: ElderTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
