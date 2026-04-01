import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum FreshStatus { fresh, warning, danger, unknown }

FreshStatus getFreshStatus(String consumeByDate) {
  final daysLeft = getDaysLeft(consumeByDate);
  if (daysLeft == -999) return FreshStatus.unknown;

  if (daysLeft <= 0) return FreshStatus.danger;
  if (daysLeft <= 3) return FreshStatus.warning;
  return FreshStatus.fresh;
}

int getDaysLeft(String consumeByDate) {
  if (consumeByDate.isEmpty) return -999;

  final expiry = DateTime.tryParse(consumeByDate);
  if (expiry == null) return -999;

  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final expiryDate = DateTime(expiry.year, expiry.month, expiry.day);

  return expiryDate.difference(todayDate).inDays;
}

Color getStatusColor(FreshStatus status) {
  switch (status) {
    case FreshStatus.fresh:   return AppColors.fresh;
    case FreshStatus.warning: return AppColors.warning;
    case FreshStatus.danger:  return AppColors.danger;
    case FreshStatus.unknown: return Colors.grey;
  }
}

Color getStatusBgColor(FreshStatus status) {
  switch (status) {
    case FreshStatus.fresh:   return AppColors.freshBg;
    case FreshStatus.warning: return AppColors.warningBg;
    case FreshStatus.danger:  return AppColors.dangerBg;
    case FreshStatus.unknown: return Colors.grey[100]!;
  }
}

String getDdayText(String consumeByDate) {
  final daysLeft = getDaysLeft(consumeByDate);
  if (daysLeft == -999) return '-';

  if (daysLeft < 0) return 'D+${-daysLeft}';
  if (daysLeft == 0) return 'D-day';
  return 'D-$daysLeft';
}