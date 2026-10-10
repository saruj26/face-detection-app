import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/glasses.dart';
import 'glasses_api.dart';

typedef AssetStringLoader = Future<String> Function(String path);

/// Result of loading the catalogue: either live API data or the bundled demo
/// catalogue (with the reason the API could not be used).
class CatalogueResult {
  const CatalogueResult({required this.items, required this.isOffline, this.offlineReason});

  final List<Glasses> items;
  final bool isOffline;
  final String? offlineReason;
}

class GlassesRepository {
  GlassesRepository(this._api, {AssetStringLoader? loadAsset})
      : _loadAsset = loadAsset ?? rootBundle.loadString;

  static const bundledCataloguePath = 'assets/glasses/catalogue.json';

  final GlassesApi _api;
  final AssetStringLoader _loadAsset;

  /// Loads frames from the API; falls back to the bundled demo catalogue so
  /// the app stays usable without a running backend. With no backend
  /// configured, the bundled catalogue is used directly (no warning).
  Future<CatalogueResult> loadCatalogue() async {
    if (_api.baseUrl.isEmpty) {
      return CatalogueResult(items: await loadBundledCatalogue(), isOffline: true);
    }
    try {
      final items = await _api.fetchGlasses();
      return CatalogueResult(items: items, isOffline: false);
    } on ApiException catch (e) {
      final items = await loadBundledCatalogue();
      return CatalogueResult(items: items, isOffline: true, offlineReason: e.message);
    }
  }

  Future<Glasses> loadById(int id, {List<Glasses> fallback = const []}) async {
    try {
      return await _api.fetchGlassesById(id);
    } on ApiException catch (e) {
      if (e.isNotFound) rethrow;
      for (final g in fallback) {
        if (g.id == id) return g;
      }
      rethrow;
    }
  }

  Future<List<Glasses>> loadBundledCatalogue() async {
    final raw = jsonDecode(await _loadAsset(bundledCataloguePath)) as List;
    return [
      for (var i = 0; i < raw.length; i++)
        Glasses.fromBundledJson((raw[i] as Map).cast<String, dynamic>(), i + 1),
    ];
  }
}
