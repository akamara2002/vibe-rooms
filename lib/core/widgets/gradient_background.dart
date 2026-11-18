import 'package:material_ui/material_ui.dart';

/// Deep purple to near-black backdrop used by the signed-in/out screens.
class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B1B5A), Color(0xFF130B2B), Color(0xFF0A0712)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: child,
    );
  }
}
