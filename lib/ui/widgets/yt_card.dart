import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/audio_handler.dart';
import '../screens/artist_screen.dart';
import '../screens/playlist_screen.dart';
import '../../theme.dart';
import 'artwork.dart';
import 'track_actions_sheet.dart';

/// Navigates to the right screen (or plays) for any YtItem.
void openYtItem(BuildContext context, YtItem item) {
  switch (item.kind) {
    case YtKind.song:
    case YtKind.video:
      final track = item.track;
      if (track != null) {
        context.read<MaheraiAudioHandler>().playSong(track);
      }
    case YtKind.album:
    case YtKind.playlist:
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlaylistScreen(browseId: item.id, title: item.title),
      ));
    case YtKind.artist:
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ArtistScreen(browseId: item.id),
      ));
  }
}

/// Square card used in horizontal carousels (home, artist shelves).
class YtCard extends StatelessWidget {
  final YtItem item;
  final double size;
  const YtCard({super.key, required this.item, this.size = 148});

  @override
  Widget build(BuildContext context) {
    final isArtist = item.kind == YtKind.artist;
    return InkWell(
      onTap: () => openYtItem(context, item),
      onLongPress: item.track == null
          ? null
          : () => showTrackActions(context, item.track!),
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Artwork(
              url: item.thumbUrl,
              size: size,
              radius: isArtist ? size / 2 : 16,
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: isArtist ? TextAlign.center : TextAlign.start,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (item.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isArtist ? TextAlign.center : TextAlign.start,
                style: TextStyle(fontSize: 12, color: MTheme.textLow),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A titled horizontal carousel of YtCards.
class YtCarousel extends StatelessWidget {
  final HomeSection section;
  const YtCarousel({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            section.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        SizedBox(
          height: 216,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: section.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => YtCard(item: section.items[i]),
          ),
        ),
      ],
    );
  }
}
