/// Who is signed in, persisted on-device.
///
/// Backed by the `swat/account` platform channel (SharedPreferences on
/// Android, written by MainActivity). Demo-honest: this is a local
/// account for the hackathon build — no password, no server, nothing
/// leaves the phone. The shape (load / signIn / signOut + a change
/// stream) is what a real auth provider would slot into.
///
/// Where the channel doesn't exist at all (widget tests, desktop), the
/// store falls back to a demo account so the app still opens — on a real
/// Android phone the channel always answers, and no stored account
/// means the login screen.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../models/account.dart';

class AccountStore {
  AccountStore._();

  static const MethodChannel _channel = MethodChannel('swat/account');

  static UserAccount? _account;
  static bool _loaded = false;

  static UserAccount? get account => _account;
  static bool get isLoaded => _loaded;

  /// Name to address the user by; "You" before sign-in resolves.
  static String get displayName => _account?.displayName ?? 'You';
  static String get firstName => _account?.firstName ?? 'You';

  static final StreamController<void> _changes =
      StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;

  static Future<UserAccount?> load() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getAccount');
      if (raw is Map) _account = UserAccount.fromMap(raw);
    } on MissingPluginException {
      // No platform side (tests/desktop) — don't wall off the app.
      _account ??= const UserAccount(
        name: 'Demo User',
        email: 'demo@swat.app',
      );
    } on PlatformException {
      // Channel present but failed — treat as signed out.
    }
    _loaded = true;
    return _account;
  }

  static Future<void> signIn(UserAccount account) async {
    _account = account;
    _loaded = true;
    try {
      await _channel.invokeMethod<void>('saveAccount', account.toMap());
    } on MissingPluginException {
      // In-memory only on channel-less platforms.
    } on PlatformException {
      // In-memory only; the session still works.
    }
    _changes.add(null);
  }

  static Future<void> signOut() async {
    _account = null;
    try {
      await _channel.invokeMethod<void>('clearAccount');
    } on MissingPluginException {
      // Nothing persisted there anyway.
    } on PlatformException {
      // Nothing more to do.
    }
    _changes.add(null);
  }
}
