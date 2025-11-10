// lib/main.dart

// Dart imports:

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vad_example/bloc/translate_cubit.dart';

// Package imports:

// Project imports:
import 'package:vad_example/pages/home_page.dart';
import 'package:vad_example/ui/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TranslateCubit(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Realtime Video Call Translate',
        theme: AppTheme.getDarkTheme(),
        home: const HomePage(),
      ),
    );
  }
}
