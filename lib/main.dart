import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/home_screen.dart';
import 'screens/import_screen.dart';
import 'screens/layout_editor_screen.dart';
import 'screens/caption_editor_screen.dart';
import 'screens/audio_mixer_screen.dart';
import 'screens/highlight_picker_screen.dart';
import 'screens/export_screen.dart';

void main() {
  runApp(const ProviderScope(child: VerticalCraftApp()));
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/import', builder: (_, __) => const ImportScreen()),
    GoRoute(path: '/layout', builder: (_, s) => LayoutEditorScreen(clipId: s.uri.queryParameters['clipId'] ?? '')),
    GoRoute(
      path: '/captions',
      builder: (_, s) => CaptionEditorScreen(
        clipId: s.uri.queryParameters['clipId'] ?? '',
        faceClipId: s.uri.queryParameters['faceClipId'],
        layoutType: s.uri.queryParameters['layoutType'] ?? 'normal',
        faceRatio: double.tryParse(s.uri.queryParameters['faceRatio'] ?? '0.38') ?? 0.38,
      ),
    ),
    GoRoute(path: '/audio', builder: (_, s) => AudioMixerScreen(clipId: s.uri.queryParameters['clipId'] ?? '')),
    GoRoute(path: '/highlights', builder: (_, s) => HighlightPickerScreen(clipId: s.uri.queryParameters['clipId'] ?? '')),
    GoRoute(path: '/export', builder: (_, s) => ExportScreen(clipId: s.uri.queryParameters['clipId'] ?? '')),
  ],
);

class VerticalCraftApp extends StatelessWidget {
  const VerticalCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'VerticalCraft',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF1A1A2E),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      routerConfig: _router,
    );
  }
}
