import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/placeholder_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      route: '/home',
      links: [
        PlaceholderLink('Go to Login', '/login'),
        PlaceholderLink('Go to Room', '/room/demo'),
      ],
    );
  }
}
