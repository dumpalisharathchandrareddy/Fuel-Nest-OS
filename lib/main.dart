import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/utils/ist_time.dart';
import 'core/constants/app_constants.dart';
import 'core/services/discord_service.dart';
import 'shared/theme/app_theme.dart';

void main() async {
  print('BOOT: 🏁 main() started');
  WidgetsFlutterBinding.ensureInitialized();
  print('BOOT: 🔧 WidgetsFlutterBinding initialized');

  // India time — must init before any date ops
  print('BOOT: 🕒 Initializing IstTime...');
  IstTime.init();
  print('BOOT: ✅ IstTime initialized');

  // Orientations
  print('BOOT: 📱 Setting orientations...');
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  print('BOOT: ✅ Orientations set');

  // System UI style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F1117),
    ),
  );

  print('BOOT: 🔌 Initializing Supabase Registry (with 10s safety timeout)...');
  // Init central registry Supabase
  try {
    print('BOOT: 🔍 Attempting Supabase.initialize...');
    
    // Race Supabase.initialize against a 10s timeout
    await Future.any([
      Supabase.initialize(
        url: AppConstants.hasRegistry ? AppConstants.registrySupabaseUrl : 'https://demo.supabase.co',
        anonKey: AppConstants.hasRegistry ? AppConstants.registryAnonKey : 'demo-anon-key',
        debug: true,
      ),
      Future.delayed(const Duration(seconds: 10)).then((_) => throw 'Supabase Init Timeout'),
    ]);
    
    print('BOOT: ✅ Supabase Registry Initialized successfully.');
  } catch (e) {
    print('BOOT: ⚠️ Supabase.initialize ended/timed out with: $e');
  }

  // Load Discord config
  print('BOOT: 📜 Loading Discord config...');
  await DiscordService.instance.loadConfig();
  print('BOOT: ✅ Discord Config Loaded.');

  print('BOOT: 🚀 Running App...');
  runApp(
    const ProviderScope(
      child: FuelOSApp(),
    ),
  );
}

class FuelOSApp extends ConsumerWidget {
  const FuelOSApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    print('BUILD: 🏗️ FuelOSApp.build() started');
    final router = ref.watch(routerProvider);
    print('BUILD: 🏗️ FuelOSApp using router instance: ${router.hashCode}');

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
