import 'package:flutter/material.dart';

import 'package:cipher_safety/data/repositories/listener_repository.dart';
import 'package:cipher_safety/presentation/subject_entry/subject_entry_page.dart';

class CipherSafetyApp extends StatelessWidget {
  const CipherSafetyApp({
    super.key,
    required this.listenerRepository,
    this.autoConnect = true,
    this.enableForegroundService = true,
  });

  final ListenerRepository listenerRepository;
  final bool autoConnect;
  final bool enableForegroundService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CIPHER Safety',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1F1F1F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5A5A5A),
          secondary: Color(0xFF7A7A7A),
          surface: Color(0xFF2A2A2A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF151515),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mediaQuery = MediaQuery.of(context);
        final double baseFontSize = mediaQuery.size.width * 0.03;
        final double textScaleFactor = baseFontSize / 14;
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: SubjectEntryPage(
        listenerRepository: listenerRepository,
        autoConnect: autoConnect,
        enableForegroundService: enableForegroundService,
      ),
    );
  }
}
