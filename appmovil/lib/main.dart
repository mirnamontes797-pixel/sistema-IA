import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/balance_screen.dart';
import 'screens/geofences_screen.dart';
import 'screens/home_screen.dart';
import 'screens/institutions_screen.dart';
import 'screens/login_screen.dart';
import 'screens/teams_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadSession();
  runApp(const PlaneacionApp());
}

class PlaneacionApp extends StatelessWidget {
  const PlaneacionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Planeación Académica',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: Api.token != null ? const MainShell() : const LoginScreen(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _tabs = [
    HomeScreen(),
    TeamsScreen(),
    BalanceScreen(),
    GeofencesScreen(),
    InstitutionsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Cursos'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Equipos'),
          NavigationDestination(icon: Icon(Icons.balance_outlined), label: 'Balance'),
          NavigationDestination(icon: Icon(Icons.place_outlined), label: 'Geocercas'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Mapa'),
        ],
      ),
    );
  }
}
