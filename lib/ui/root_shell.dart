import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'mini_player.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'screens/videos_screen.dart';

/// App shell: three kept-alive tabs, a floating mini player, and a
/// glass bottom navigation bar.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _tab,
        children: const [
          HomeScreen(),
          SearchScreen(),
          VideosScreen(),
          LibraryScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  backgroundColor: MTheme.bg.withValues(alpha: 0.82),
                  indicatorColor: MTheme.accentSoft,
                  height: 64,
                  labelTextStyle: WidgetStatePropertyAll(TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: MTheme.textMid,
                  )),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return IconThemeData(
                      color: selected ? MTheme.accent : MTheme.textLow,
                    );
                  }),
                ),
                child: NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.search_rounded),
                      selectedIcon: Icon(Icons.search_rounded),
                      label: 'Search',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.smart_display_outlined),
                      selectedIcon: Icon(Icons.smart_display_rounded),
                      label: 'Videos',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music_rounded),
                      label: 'Library',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
