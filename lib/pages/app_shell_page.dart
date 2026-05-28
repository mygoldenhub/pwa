import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShellPage extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShellPage({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey(navigationShell.currentIndex),
          child: navigationShell,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined, color: cs.onSurfaceVariant),
            selectedIcon: Icon(Icons.shopping_cart, color: cs.primary),
            label: 'Cart',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined, color: cs.onSurfaceVariant),
            selectedIcon: Icon(Icons.receipt_long, color: cs.primary),
            label: 'Invoice',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, color: cs.onSurfaceVariant),
            selectedIcon: Icon(Icons.person, color: cs.primary),
            label: 'Account',
          ),
        ],
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
        },
      ),
    );
  }
}
