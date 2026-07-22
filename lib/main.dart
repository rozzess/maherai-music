import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'services/audio_handler.dart';
import 'services/download_service.dart';
import 'services/innertube.dart';
import 'services/library_service.dart';
import 'services/lyrics_service.dart';
import 'services/stream_service.dart';
import 'theme.dart';
import 'ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox(LibraryService.favoritesBox),
    Hive.openBox(LibraryService.playlistsBox),
    Hive.openBox(LibraryService.recentsBox),
    Hive.openBox(LibraryService.historyBox),
    Hive.openBox(DownloadService.boxName),
  ]);

  final innertube = InnerTube();
  final streams = StreamService();
  final library = LibraryService();
  final downloads = DownloadService(streams);
  final lyrics = LyricsService(innertube);

  final audioHandler = await AudioService.init(
    builder: () => MaheraiAudioHandler(
      streams: streams,
      innertube: innertube,
      downloads: downloads,
      library: library,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.maherai.music.audio',
      androidNotificationChannelName: 'Maherai Music playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(MaheraiApp(
    innertube: innertube,
    library: library,
    downloads: downloads,
    lyrics: lyrics,
    audioHandler: audioHandler,
  ));
}

class MaheraiApp extends StatelessWidget {
  final InnerTube innertube;
  final LibraryService library;
  final DownloadService downloads;
  final LyricsService lyrics;
  final MaheraiAudioHandler audioHandler;

  const MaheraiApp({
    super.key,
    required this.innertube,
    required this.library,
    required this.downloads,
    required this.lyrics,
    required this.audioHandler,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: innertube),
        Provider.value(value: lyrics),
        Provider.value(value: audioHandler),
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: downloads),
      ],
      child: MaterialApp(
        title: 'Maherai Music',
        debugShowCheckedModeBanner: false,
        theme: MTheme.dark(),
        home: const RootShell(),
      ),
    );
  }
}
