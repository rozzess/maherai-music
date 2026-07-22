import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/audio_handler.dart';
import '../../services/download_service.dart';
import '../../theme.dart';
import '../../util/fmt.dart';
import 'artwork.dart';
import 'playing_bars.dart';
import 'track_actions_sheet.dart';

/// A song row. Shows animated bars when it's the playing track, a download
/// badge when cached offline, and opens the actions sheet on long press.
class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showDuration;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.trailing,
    this.showDuration = false,
  });

  @override
  Widget build(BuildContext context) {
    final handler = context.read<MaheraiAudioHandler>();
    final downloads = context.watch<DownloadService>();
    final downloaded = downloads.isDownloaded(track.id);
    final progress = downloads.active[track.id];

    return ValueListenableBuilder<Track?>(
      valueListenable: handler.current,
      builder: (context, cur, _) {
        final isCurrent = cur?.id == track.id;
        return InkWell(
          onTap: onTap,
          onLongPress: () => showTrackActions(context, track),
          borderRadius: BorderRadius.circular(MTheme.radiusTile),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Artwork(url: track.thumbUrl, size: 52, radius: 10),
                    if (isCurrent)
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: StreamBuilder<bool>(
                            stream: handler.player.playingStream,
                            builder: (_, snap) =>
                                PlayingBars(animate: snap.data ?? false),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isCurrent ? MTheme.accent : MTheme.textHigh,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (downloaded) ...[
                            const Icon(Icons.download_done_rounded,
                                size: 13, color: MTheme.accent),
                            const SizedBox(width: 4),
                          ] else if (progress != null) ...[
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 2,
                                color: MTheme.accent,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              [
                                track.artist,
                                if (showDuration && track.duration != null)
                                  fmtDuration(track.duration),
                              ].where((s) => s.isNotEmpty).join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, color: MTheme.textMid),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                trailing ??
                    IconButton(
                      icon: Icon(Icons.more_vert_rounded,
                          color: MTheme.textLow, size: 20),
                      onPressed: () => showTrackActions(context, track),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}
