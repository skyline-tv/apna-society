import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// Google Play reviewer demo. Never points at production residents or money.
class DemoEnvironment {
  DemoEnvironment._();

  static const label = 'DEMO MODE — SAMPLE DATA';
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
    return ApiConfig.resolve(
      flavorName: 'demo',
      demoBaseUrl: demoBaseUrl,
    );
  }

  static Future<bool> restorePersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final on = prefs.getBool(_prefsKey) ?? false;
    active.value = on;
    return on;
  }

  static Future<void> persist(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    if (on) {
      await prefs.setBool(_prefsKey, true);
    } else {
      await prefs.remove(_prefsKey);
    }
    active.value = on;
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
