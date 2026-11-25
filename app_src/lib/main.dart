import 'package:flutter/material.dart';
import 'pages.dart';
import 'settings.dart';
import 'state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final s = AppState();
  await s.init();
  runApp(AgriApp(s));
}

ThemeData _theme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF1E8E5A),
      brightness: b,
      inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
    );

class AgriApp extends StatelessWidget {
  final AppState s;
  const AgriApp(this.s, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) => MaterialApp(
          title: 'AgriBot',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark][s.themeIdx],
          home: Shell(s),
        ),
      );
}

class Shell extends StatefulWidget {
  final AppState s;
  const Shell(this.s, {super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.s,
        builder: (context, _) {
          final s = widget.s;
          return Scaffold(
            body: SafeArea(
              child: IndexedStack(index: _i, children: [
                HomePage(s, () => setState(() => _i = 4)),
                PlantsPage(s),
                SchedulePage(s),
                HistoryPage(s),
                SettingsPage(s),
              ]),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _i,
              onDestinationSelected: (v) => setState(() => _i = v),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Beranda'),
                NavigationDestination(icon: Icon(Icons.eco_outlined), selectedIcon: Icon(Icons.eco), label: 'Tanaman'),
                NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule), label: 'Jadwal'),
                NavigationDestination(icon: Icon(Icons.show_chart), selectedIcon: Icon(Icons.show_chart), label: 'Riwayat'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Setelan'),
              ],
            ),
          );
        },
      );
}
