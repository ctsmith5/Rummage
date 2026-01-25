import 'dart:async';

import 'package:flutter/material.dart';

import '../models/garage_sale.dart';
import '../theme/app_colors.dart';

enum SaleTimeStatus {
  upcoming,
  active,
  ended,
}

SaleTimeStatus saleTimeStatusFor(GarageSale sale, DateTime now) {
  if (now.isBefore(sale.startDate)) return SaleTimeStatus.upcoming;
  if (now.isAfter(sale.endDate)) return SaleTimeStatus.ended;
  return SaleTimeStatus.active;
}

DateTime? nextSaleStatusBoundary(GarageSale sale, DateTime now) {
  final status = saleTimeStatusFor(sale, now);
  switch (status) {
    case SaleTimeStatus.upcoming:
      return sale.startDate;
    case SaleTimeStatus.active:
      return sale.endDate;
    case SaleTimeStatus.ended:
      return null;
  }
}

/// A badge that updates itself when the sale transitions Upcoming -> Active -> Ended.
///
/// This avoids stale pills when the user is staring at the screen as the time passes.
class SaleStatusBadge extends StatefulWidget {
  final GarageSale sale;
  final bool compact;

  const SaleStatusBadge({
    super.key,
    required this.sale,
    this.compact = true,
  });

  @override
  State<SaleStatusBadge> createState() => _SaleStatusBadgeState();
}

class _SaleStatusBadgeState extends State<SaleStatusBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  @override
  void didUpdateWidget(covariant SaleStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sale.startDate != widget.sale.startDate ||
        oldWidget.sale.endDate != widget.sale.endDate) {
      _scheduleNext();
    }
  }

  void _scheduleNext() {
    _timer?.cancel();

    final now = DateTime.now();
    final boundary = nextSaleStatusBoundary(widget.sale, now);
    if (boundary == null) return;

    // Fire slightly after the boundary so we are guaranteed to be on the next side.
    final delay = boundary.difference(now) + const Duration(seconds: 1);
    if (delay.isNegative) {
      // Already crossed; rebuild and try again.
      if (mounted) setState(() {});
      return;
    }

    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = saleTimeStatusFor(widget.sale, DateTime.now());

    late final Color background;
    late final Color foreground;
    late final String text;

    switch (status) {
      case SaleTimeStatus.active:
        background = AppColors.success;
        foreground = Colors.white;
        text = widget.compact ? 'ACTIVE' : 'ACTIVE NOW';
        break;
      case SaleTimeStatus.upcoming:
        background = AppColors.primary.withAlpha((0.15 * 255).round());
        foreground = AppColors.primary;
        text = 'UPCOMING';
        break;
      case SaleTimeStatus.ended:
        background = AppColors.mapPinInactive.withAlpha((0.20 * 255).round());
        foreground = AppColors.mapPinInactive;
        text = 'ENDED';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 8 : 12,
        vertical: widget.compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(widget.compact ? 12 : 16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: widget.compact ? 10 : 12,
          fontWeight: FontWeight.bold,
          letterSpacing: widget.compact ? 0 : 0.2,
        ),
      ),
    );
  }
}
