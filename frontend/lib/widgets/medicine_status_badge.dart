import 'package:flutter/material.dart';
import '../core/theme.dart';



class MedicineStatusBadge extends StatelessWidget {
  
  final MedicineStatus status;
  
  
  final String? text;
  
  
  final bool large;

  const MedicineStatusBadge({
    super.key,
    required this.status,
    this.text,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 16 : 12,
        vertical: large ? 8 : 5,
      ),
      decoration: BoxDecoration(
        color: _getColor().withOpacity(0.15),
        borderRadius: BorderRadius.circular(large ? 12 : 8),
        border: Border.all(
          color: _getColor().withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIcon(),
            size: large ? 22 : 16,
            color: _getColor(),
          ),
          const SizedBox(width: 6),
          Text(
            text ?? _getDefaultText(),
            style: TextStyle(
              fontSize: large ? 18 : 14,
              fontWeight: FontWeight.w600,
              color: _getColor(),
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor() {
    switch (status) {
      case MedicineStatus.taken:
        return ElderTheme.successColor;     
      case MedicineStatus.missed:
        return ElderTheme.errorColor;        
      case MedicineStatus.pending:
        return ElderTheme.infoColor;         
      case MedicineStatus.expiring:
        return ElderTheme.warningColor;      
      case MedicineStatus.expired:
        return ElderTheme.errorColor;        
      case MedicineStatus.normal:
        return ElderTheme.successColor;      
    }
  }

  IconData _getIcon() {
    switch (status) {
      case MedicineStatus.taken:
        return Icons.check_circle_rounded;
      case MedicineStatus.missed:
        return Icons.cancel_rounded;
      case MedicineStatus.pending:
        return Icons.schedule_rounded;
      case MedicineStatus.expiring:
        return Icons.warning_amber_rounded;
      case MedicineStatus.expired:
        return Icons.error_rounded;
      case MedicineStatus.normal:
        return Icons.verified_rounded;
    }
  }

  String _getDefaultText() {
    switch (status) {
      case MedicineStatus.taken:
        return '已服';
      case MedicineStatus.missed:
        return '漏服';
      case MedicineStatus.pending:
        return '待服';
      case MedicineStatus.expiring:
        return '临期';
      case MedicineStatus.expired:
        return '已过期';
      case MedicineStatus.normal:
        return '正常';
    }
  }
}


enum MedicineStatus {
  taken,     
  missed,    
  pending,   
  expiring,  
  expired,   
  normal,    
}


class MedicationDayCell extends StatelessWidget {
  final DateTime date;
  final DayStatus status; 
  final bool isToday;

  const MedicationDayCell({
    super.key,
    required this.date,
    required this.status,
    this.isToday = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 56,
      decoration: BoxDecoration(
        color: _getBgColor(),
        borderRadius: BorderRadius.circular(12),
        border: isToday
            ? Border.all(color: ElderTheme.primaryColor, width: 2.5)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _getWeekday(),
            style: TextStyle(
              fontSize: 12,
              color: isToday ? ElderTheme.primaryColor : ElderTheme.textSecondary,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _getTextColor(),
            ),
          ),
          const SizedBox(height: 2),
          Icon(
            _getIcon(),
            size: 16,
            color: _getIconColor(),
          ),
        ],
      ),
    );
  }

  Color _getBgColor() {
    switch (status) {
      case DayStatus.taken:
        return ElderTheme.successColor.withOpacity(0.12);
      case DayStatus.missed:
        return ElderTheme.errorColor.withOpacity(0.12);
      case DayStatus.pending:
        return ElderTheme.warningColor.withOpacity(0.12);
      case DayStatus.future:
        return ElderTheme.bgColor;
    }
  }

  Color _getTextColor() {
    switch (status) {
      case DayStatus.taken:
        return ElderTheme.successColor;
      case DayStatus.missed:
        return ElderTheme.errorColor;
      case DayStatus.pending:
        return ElderTheme.warningColor;
      case DayStatus.future:
        return ElderTheme.textSecondary;
    }
  }

  Color _getIconColor() {
    switch (status) {
      case DayStatus.taken:
        return ElderTheme.successColor;
      case DayStatus.missed:
        return ElderTheme.errorColor;
      case DayStatus.pending:
        return ElderTheme.warningColor;
      case DayStatus.future:
        return Colors.transparent;
    }
  }

  IconData _getIcon() {
    switch (status) {
      case DayStatus.taken:
        return Icons.check_circle;
      case DayStatus.missed:
        return Icons.cancel;
      case DayStatus.pending:
        return Icons.schedule;
      case DayStatus.future:
        return Icons.circle_outlined;
    }
  }

  String _getWeekday() {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return weekdays[date.weekday - 1];
  }
}


enum DayStatus {
  taken,    
  missed,   
  pending,  
  future,   
}


class MedicationProgressRing extends StatelessWidget {
  final int taken;
  final int total;
  final double size;

  const MedicationProgressRing({
    super.key,
    required this.taken,
    required this.total,
    this.size = 200,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? taken / total : 0.0;
    final allTaken = taken == total && total > 0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 16,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(
                ElderTheme.dividerColor,
              ),
            ),
          ),
          
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 16,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(
                allTaken ? ElderTheme.successColor : ElderTheme.primaryColor,
              ),
              strokeCap: StrokeCap.round,
            ),
          ),
          
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                allTaken ? Icons.check_circle : Icons.medication_rounded,
                size: size * 0.2,
                color: allTaken ? ElderTheme.successColor : ElderTheme.primaryColor,
              ),
              const SizedBox(height: 8),
              Text(
                '$taken',
                style: TextStyle(
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.bold,
                  color: ElderTheme.textPrimary,
                ),
              ),
              Text(
                '/$total 次',
                style: TextStyle(
                  fontSize: size * 0.12,
                  color: ElderTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class ExpiringWarningBadge extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const ExpiringWarningBadge({
    super.key,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: ElderTheme.warningColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ElderTheme.warningColor.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 22,
              color: ElderTheme.warningColor,
            ),
            const SizedBox(width: 8),
            Text(
              '$count 种药品临期',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ElderTheme.warningColor,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: ElderTheme.warningColor,
            ),
          ],
        ),
      ),
    );
  }
}
