import 'package:flutter/material.dart';

import 'guard_desk.dart';

/// Thin shell so auth routing can keep resolving to [GuardHome].
class GuardHome extends StatelessWidget {
  const GuardHome({super.key, required this.guard});
  final dynamic guard;

  @override
  Widget build(BuildContext context) => GuardDeskHome(guard: guard);
}
