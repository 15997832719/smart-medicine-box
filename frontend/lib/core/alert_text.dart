import 'package:flutter/material.dart';

import '../models/medicine.dart';
import 'theme.dart';


class AlertText {
  const AlertText({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.medicine,
    this.canEditThreshold = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final Medicine? medicine;

  
  final bool canEditThreshold;
}


Medicine? findAlertMedicine(MedicineAlert alert, List<Medicine> medicines) {
  for (final medicine in medicines) {
    if (medicine.id == alert.yao_pin_bian_hao) return medicine;
  }
  return null;
}


AlertText describeAlert(MedicineAlert alert, List<Medicine> medicines) {
  final medicine = findAlertMedicine(alert, medicines);
  final name = medicine?.name ?? alert.yao_pin_ming_cheng;

  switch (alert.type) {
    case 'low_stock':
      final left = medicine?.stockCount;
      final limit = medicine?.lowStockThreshold;
      if (left == null || limit == null) {
        return AlertText(
          icon: Icons.inventory_2_outlined,
          color: ElderTheme.warningColor,
          title: '$name 快吃完了',
          detail: alert.message,
          medicine: medicine,
        );
      }
      return AlertText(
        icon: Icons.inventory_2_outlined,
        color: ElderTheme.warningColor,
        title: '$name 快吃完了',
        detail: '现在还剩 $left 片。少于 $limit 片就会提醒你。',
        medicine: medicine,
        canEditThreshold: true,
      );

    case 'expired':
      final valid = medicine?.you_xiao_ri_qi;
      return AlertText(
        icon: Icons.dangerous_outlined,
        color: ElderTheme.errorColor,
        title: '$name 已经过期',
        detail: valid == null
            ? alert.message
            : '有效期到 ${formatChineseDate(valid)}。过期的药不要再吃，请及时处理。',
        medicine: medicine,
      );

    case 'expiring':
      final valid = medicine?.you_xiao_ri_qi;
      if (valid == null) {
        return AlertText(
          icon: Icons.event_busy_outlined,
          color: ElderTheme.warningColor,
          title: '$name 快过期了',
          detail: alert.message,
          medicine: medicine,
        );
      }
      final days = valid.difference(DateTime.now()).inDays;
      return AlertText(
        icon: Icons.event_busy_outlined,
        color: ElderTheme.warningColor,
        title: '$name 快过期了',
        detail: '有效期到 ${formatChineseDate(valid)}，还有 $days 天。请尽快服用或换成新药。',
        medicine: medicine,
      );

    default:
      return AlertText(
        icon: Icons.info_outline,
        color: ElderTheme.infoColor,
        title: name,
        detail: alert.message,
        medicine: medicine,
      );
  }
}


String formatChineseDate(DateTime date) => '${date.year}年${date.month}月${date.day}日';