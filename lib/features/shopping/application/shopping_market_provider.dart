import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/shopping_market.dart';

final shoppingMarketProvider =
    StateNotifierProvider<ShoppingMarketController, ShoppingMarket>(
  (ref) => ShoppingMarketController(ref.watch(activeAccountIdProvider)),
);

class ShoppingMarketController extends StateNotifier<ShoppingMarket> {
  ShoppingMarketController(String? owner)
      : _key = 'shopping-market-v1:${owner ?? 'guest'}',
        super(const ShoppingMarket()) {
    _ready = _load();
  }
  final String _key;
  late final Future<void> _ready;
  bool _saving = false;
  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null || !mounted) return;
      state = ShoppingMarket.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      // A damaged preference must never damage shopping records.
    }
  }

  Future<bool> save(ShoppingMarket value) async {
    if (_saving) return false;
    _saving = true;
    try {
      await _ready;
      if (!mounted) return false;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return false;
      final saved = await prefs.setString(_key, jsonEncode(value.toJson()));
      if (!saved || !mounted) return false;
      state = value;
      return true;
    } catch (_) {
      return false;
    } finally {
      _saving = false;
    }
  }
}
