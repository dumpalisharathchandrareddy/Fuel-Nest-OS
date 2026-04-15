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
  WidgetsFlutterBinding.ensureInitialized();

  // India time — must init before any date ops
  IstTime.init();

  // Orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // System UI style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F1117),
    ),
  );

  // Init central registry Supabase
  await Supabase.initialize(
    url: AppConstants.hasRegistry ? AppConstants.registrySupabaseUrl : 'https://demo.supabase.co',
    anonKey: AppConstants.hasRegistry ? AppConstants.registryAnonKey : 'demo-anon-key',
    debug: false,
  );

  // Load Discord config
  await DiscordService.instance.loadConfig();

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
    debugPrint('Building FuelOSApp... [STABILITY CHECK]');
    final router = ref.watch(routerProvider);
    debugPrint('FuelOSApp using router instance: ${router.hashCode}');

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
