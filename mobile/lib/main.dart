import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'providers/test_provider.dart';
import 'features/ttfb_test/presentation/ttfb_test_screen.dart';
import 'features/dns_test/presentation/dns_test_screen.dart';
import 'features/ping_test/presentation/ping_test_screen.dart';
import 'features/settings/presentation/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.secondaryDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const NocTuneApp());
}

class NocTuneApp extends StatelessWidget {
  const NocTuneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TestProvider()..init()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const TtfbTestScreen(),
    const PingTestScreen(),
    const DnsTestScreen(),
    const SettingsScreen(),
  ];

  final List<String> _titles = [
    'TTFB Test',
    'Ping Test',
    'DNS Lookup',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }
    context.read<TestProvider>().handleAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TestProvider>(
      builder: (context, provider, child) {
        if (provider.isInitializing) {
          return _StartupLoadingScreen(provider: provider);
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speed, color: AppTheme.accentBlue),
                const SizedBox(width: 8),
                Text(_titles[_currentIndex]),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: Icon(
                    provider.networkInfo?.connectionType != 'No Connection'
                        ? Icons.wifi
                        : Icons.wifi_off,
                    size: 16,
                    color:
                        provider.networkInfo?.connectionType != 'No Connection'
                        ? AppTheme.accentGreen
                        : AppTheme.accentRed,
                  ),
                  label: Text(
                    provider.networkInfo?.connectionType ?? 'Unknown',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: AppTheme.cardDark,
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (provider.showKeepAppOpenNotice)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: provider.hasPausedTest
                        ? AppTheme.accentRed.withOpacity(0.12)
                        : AppTheme.accentBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: provider.hasPausedTest
                          ? AppTheme.accentRed.withOpacity(0.3)
                          : AppTheme.accentBlue.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        provider.hasPausedTest
                            ? Icons.pause_circle
                            : Icons.warning_amber_rounded,
                        color: provider.hasPausedTest
                            ? AppTheme.accentRed
                            : AppTheme.accentBlue,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.hasPausedTest
                                  ? 'Tes Dipause'
                                  : 'Jangan Tutup App',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              provider.keepAppOpenNotice,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (provider.hasPausedTest)
                        TextButton(
                          onPressed: provider.resumePausedTest,
                          child: const Text('Resume'),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: IndexedStack(index: _currentIndex, children: _screens),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            backgroundColor: AppTheme.secondaryDark,
            indicatorColor: AppTheme.accentBlue.withOpacity(0.2),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.speed_outlined),
                selectedIcon: Icon(Icons.speed, color: AppTheme.accentBlue),
                label: 'TTFB',
              ),
              NavigationDestination(
                icon: Icon(Icons.network_ping_outlined),
                selectedIcon: Icon(
                  Icons.network_ping,
                  color: AppTheme.accentBlue,
                ),
                label: 'Ping',
              ),
              NavigationDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns, color: AppTheme.accentBlue),
                label: 'DNS',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: AppTheme.accentBlue),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  final TestProvider provider;

  const _StartupLoadingScreen({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.primaryDark, AppTheme.secondaryDark],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.speed,
                              color: AppTheme.accentBlue,
                              size: 28,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'NOCTune',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          provider.initializationMessage,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: provider.initializationProgress,
                            minHeight: 10,
                            backgroundColor: AppTheme.secondaryDark,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppTheme.accentBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${(provider.initializationProgress * 100).round()}%',
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        if (provider.startupLogs.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Text(
                            'Startup Log',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryDark,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: provider.startupLogs
                                  .map(
                                    (log) => Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        log,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
