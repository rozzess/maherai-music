import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../theme.dart';

Widget _box(double w, double h, [double r = 12]) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: MTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(r),
      ),
    );

Widget _shimmer(Widget child) => Shimmer.fromColors(
      baseColor: MTheme.surface,
      highlightColor: MTheme.surfaceHigh,
      child: child,
    );

/// Placeholder for a horizontal card carousel while the feed loads.
class ShimmerCarousel extends StatelessWidget {
  const ShimmerCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    return _shimmer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: _box(160, 22, 6),
          ),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _box(148, 148, 16),
                  const SizedBox(height: 8),
                  _box(120, 14, 4),
                  const SizedBox(height: 6),
                  _box(80, 12, 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder for a track list while results load.
class ShimmerTrackList extends StatelessWidget {
  final int count;
  const ShimmerTrackList({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return _shimmer(
      Column(
        children: List.generate(
          count,
          (_) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _box(52, 52, 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(double.infinity, 14, 4),
                      const SizedBox(height: 8),
                      _box(140, 12, 4),
                    ],
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
