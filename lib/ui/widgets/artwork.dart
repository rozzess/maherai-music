import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';

/// Rounded, cached artwork with a graceful placeholder.
class Artwork extends StatelessWidget {
  final String url;
  final double size;
  final double radius;
  final BoxFit fit;

  const Artwork({
    super.key,
    required this.url,
    this.size = 56,
    this.radius = 10,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: MTheme.surfaceHigh,
      child: Icon(Icons.music_note_rounded,
          color: Colors.white.withValues(alpha: 0.25), size: size * 0.4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: fit,
              memCacheWidth: (size * 3).round(),
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}
