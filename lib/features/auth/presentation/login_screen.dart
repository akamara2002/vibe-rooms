import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/placeholder_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      route: '/login',
      links: [
        PlaceholderLink('Go to Home', '/home'),
        PlaceholderLink('Go to Room', '/room/demo'),
      ],
    );
  }
}
