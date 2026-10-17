import 'package:flutter/material.dart';

import '../features/ai/ai_hub_screen.dart';
import '../features/graph/graph_screen.dart';
import '../features/home/home_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/settings/settings_screen.dart';

enum AppDestination {
  home('Home', Icons.home_outlined, Icons.home),
  notes('Brain', Icons.description_outlined, Icons.description),
  graph('Graph', Icons.hub_outlined, Icons.hub),
  ai('AI Hub', Icons.auto_awesome_outlined, Icons.auto_awesome),
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const AppDestination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Top-level navigation. Uses a bottom [NavigationBar] on phones and a
/// [NavigationRail] on wide screens (tablets, landscape, foldables).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static const double railBreakpoint = 640;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppDestination _current = AppDestination.home;

  void _go(AppDestination d) => setState(() => _current = d);

  Widget _body() => switch (_current) {
    AppDestination.home => HomeScreen(onNavigate: _go),
    AppDestination.notes => const NotesScreen(),
    AppDestination.graph => const GraphScreen(),
    AppDestination.ai => const AiHubScreen(),
    AppDestination.settings => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= HomeShell.railBreakpoint;
    final body = KeyedSubtree(key: ValueKey(_current), child: _body());
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _current.index,
                onDestinationSelected: (i) => _go(AppDestination.values[i]),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in AppDestination.values)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _current.index,
        onDestinationSelected: (i) => _go(AppDestination.values[i]),
        destinations: [
          for (final d in AppDestination.values)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
