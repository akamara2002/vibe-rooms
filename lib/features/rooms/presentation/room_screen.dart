import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/placeholder_screen.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      route: '/room/$id',
      links: const [PlaceholderLink('Back to home', '/home')],
    );
  }
}
