import 'package:flutter/material.dart';

import '../services/phone_verify_feature_flag.dart';

/// Inclui [child] no menu só quando a verificação por telefone está
/// habilitada ou a conta já tem o selo (para desvincular).
class PhoneVerifyMenuGate extends StatelessWidget {
  const PhoneVerifyMenuGate({
    super.key,
    required this.alreadyVerified,
    required this.child,
  });

  final bool alreadyVerified;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PhoneVerifyFeatureFlag.showMenuEntry(
      alreadyVerified: alreadyVerified,
    )) {
      return const SizedBox.shrink();
    }
    return child;
  }
}
