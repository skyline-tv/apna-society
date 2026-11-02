import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// Google Play reviewer demo. Never points at production residents or money.
class DemoEnvironment {
  DemoEnvironment._();

  /// Compact overlay chip. Keep short — clients and reviewers see this on every screen.
  static const label = 'Sample';
  static const visitorOtp = '246810';
  static const loginOtp = '123456';

  static const developmentBaseUrl = 'http://192.168.1.130:4001';
  static const productionBaseUrl = 'https://demo-apiapnasociety.skylinetv.in';

  static const accounts = <DemoAccount>[
    DemoAccount(
      role: 'Admin',
      username: 'demo_admin',
      password: 'demo@12345',
    ),
    DemoAccount(
      role: 'Owner',
      username: 'demo_owner',
      password: 'demo@12345',
    ),
    DemoAccount(
      role: 'Tenant',
      username: 'demo_tenant',
      password: 'demo@12345',
    ),
    DemoAccount(
      role: 'Security Guard',
      username: 'demo_guard',
      password: 'demo@12345',
    ),
  ];

  static final ValueNotifier<bool> active = ValueNotifier(false);

  static const _prefsKey = 'play_review_demo_mode';

  static ApiConfig config({String demoBaseUrl = ''}) {
    const fromDefine = String.fromEnvironment('DEMO_API_URL');
    final resolved = demoBaseUrl.isNotEmpty
        ? demoBaseUrl
        : (fromDefine.isNotEmpty ? fromDefine : productionBaseUrl);
    return ApiConfig.resolve(
      flavorName: 'demo',
      demoBaseUrl: resolved,
    );
  }

  static bool isDemoUsername(String? username) {
    final value = username?.trim() ?? '';
    if (value.isEmpty) return false;
    return accounts.any((account) => account.username == value);
  }

  /// Sample mode is opt-in for this process only. Cold start always lands on
  /// the normal login, even if a previous run left the old sticky pref behind.
  static Future<bool> restorePersisted() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_prefsKey)) {
      await prefs.remove(_prefsKey);
    }
    active.value = false;
    return false;
  }

  static Future<void> persist(bool on) async {
    active.value = on;
    if (!on) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    }
  }
}

class DemoAccount {
  const DemoAccount({
    required this.role,
    required this.username,
    required this.password,
  });

  final String role;
  final String username;
  final String password;
}

class PublicEnvironment {
  const PublicEnvironment({
    required this.demoMode,
    this.label,
    this.simulatedPayments = false,
  });

  final bool demoMode;
  final String? label;
  final bool simulatedPayments;

  factory PublicEnvironment.fromJson(Object? json) {
    final map = (json as Map).cast<String, Object?>();
    return PublicEnvironment(
      demoMode: map['demoMode'] == true,
      label: map['label'] as String?,
      simulatedPayments: map['simulatedPayments'] == true,
    );
  }
}
