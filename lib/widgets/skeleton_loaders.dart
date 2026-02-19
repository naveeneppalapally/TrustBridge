import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.height = 96,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.margin = EdgeInsets.zero,
  });

  final double height;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: _SkeletonContainer(
        borderRadius: borderRadius,
        child: SizedBox(height: height),
      ),
    );
  }
}

class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({
    super.key,
    this.showTrailing = true,
  });

  final bool showTrailing;

  @override
  Widget build(BuildContext context) {
    return _SkeletonContainer(
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            const _SkeletonBlock(
              width: 36,
              height: 36,
              borderRadius: BorderRadius.all(Radius.circular(18)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SkeletonBlock(width: double.infinity, height: 12),
                  SizedBox(height: 8),
                  _SkeletonBlock(width: 140, height: 10),
                ],
              ),
            ),
            if (showTrailing) ...<Widget>[
              const SizedBox(width: 12),
              const _SkeletonBlock(width: 46, height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class SkeletonChildCard extends StatelessWidget {
  const SkeletonChildCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SkeletonContainer(
      borderRadius: BorderRadius.all(Radius.circular(18)),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _SkeletonBlock(
                  width: 48,
                  height: 48,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SkeletonBlock(width: 140, height: 13),
                      SizedBox(height: 8),
                      _SkeletonBlock(width: 180, height: 10),
                    ],
                  ),
                ),
                _SkeletonBlock(width: 54, height: 20),
              ],
            ),
            SizedBox(height: 12),
            _SkeletonBlock(width: double.infinity, height: 8),
            SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(child: _SkeletonBlock(height: 32)),
                SizedBox(width: 10),
                Expanded(child: _SkeletonBlock(height: 32)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SkeletonChart extends StatelessWidget {
  const SkeletonChart({
    super.key,
    this.height = 180,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    return _SkeletonContainer(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: SizedBox(
        height: height,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(12, 16, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _SkeletonChartBar(height: 58),
              SizedBox(width: 8),
              _SkeletonChartBar(height: 82),
              SizedBox(width: 8),
              _SkeletonChartBar(height: 74),
              SizedBox(width: 8),
              _SkeletonChartBar(height: 104),
              SizedBox(width: 8),
              _SkeletonChartBar(height: 126),
              SizedBox(width: 8),
              _SkeletonChartBar(height: 92),
              SizedBox(width: 8),
              _SkeletonChartBar(height: 112),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonChartBar extends StatelessWidget {
  const _SkeletonChartBar({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _SkeletonBlock(
          width: double.infinity,
          height: height,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }
}

class _SkeletonContainer extends StatelessWidget {
  const _SkeletonContainer({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius,
        ),
        child: child,
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    this.width = double.infinity,
    this.height = 12,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius,
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}
