import 'package:flutter/material.dart';
import 'home.dart';
import 'pages.dart';
import 'settings.dart';
import 'state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final s = AppState();
  await s.init();
  runApp(AkarSiagaApp(s));
}

class AkarSiagaApp extends StatelessWidget {
  final AppState s;
  const AkarSiagaApp(this.s, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final p = palettes[s.paletteIdx % palettes.length];
          return MaterialApp(
            title: 'Akar Siaga',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(p, Brightness.light),
            darkTheme: buildTheme(p, Brightness.dark),
            themeMode: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark][s.themeIdx % 3],
            home: Shell(s),
          );
        },
      );
}

class Shell extends StatefulWidget {
  final AppState s;
  const Shell(this.s, {super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _i = 0;
  AppState get s => widget.s;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clip();
      if (s.hasPaired) s.connect(); // otomatis tersambung saat aplikasi dibuka
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _clip();
  }

  /// Kode sambung di clipboard terdeteksi otomatis (mis. baru disalin dari log server).
  Future<void> _clip() async {
    final code = await s.clipboardCode();
    if (code == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Kode sambung terdeteksi'),
        content: const Text('Pakai kode dari clipboard untuk menghubungkan aplikasi ke server kamu?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abaikan')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Pakai')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = s.applyPairCode(code);
    final pick = err ?? await s.autoSelectDevice();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pick ?? 'Server terhubung. Alat: ${s.devId}')));
    if (err == null && s.devId.isNotEmpty) s.connect();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) => Scaffold(
          body: SafeArea(
            child: IndexedStack(index: _i, children: [
              HomePage(s, () => setState(() => _i = 3)),
              SchedulePage(s),
              HistoryPage(s),
              SettingsPage(s),
            ]),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _i,
            onDestinationSelected: (v) => setState(() => _i = v),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Beranda'),
              NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule), label: 'Jadwal'),
              NavigationDestination(icon: Icon(Icons.show_chart), selectedIcon: Icon(Icons.show_chart), label: 'Riwayat'),
              NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Setelan'),
            ],
          ),
        ),
      );
}
