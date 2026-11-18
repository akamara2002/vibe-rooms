import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'config_banner.dart';

/// A route to jump to from a placeholder screen.
class PlaceholderLink {
  const PlaceholderLink(this.label, this.location);

  final String label;
  final String location;
}

/// Temporary screen: shows its route name and buttons to the other routes.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.route,
    required this.links,
  });

  final String route;
  final List<PlaceholderLink> links;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(route)),
      body: Column(
        children: [
          const ConfigBanner(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  for (final link in links)
                    FilledButton(
                      onPressed: () => context.go(link.location),
                      child: Text(link.label),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
