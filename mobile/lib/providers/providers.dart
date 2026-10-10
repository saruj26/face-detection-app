import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_config.dart';
import '../models/fit_adjustment.dart';
import '../models/glasses.dart';
import '../services/glasses_api.dart';
import '../services/glasses_repository.dart';

/// Overridden in main() with the instance loaded at start-up.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

// ---------------------------------------------------------------- API config

class ApiBaseUrlNotifier extends Notifier<String> {
  static const _key = 'api_base_url';

  @override
  String build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_key);
    return (saved != null && saved.isNotEmpty) ? saved : ApiConfig.defaultBaseUrl;
  }

  Future<void> set(String url) async {
    if (url.trim().isEmpty) return resetToDefault();
    final normalized = ApiConfig.normalize(url);
    await ref.read(sharedPreferencesProvider).setString(_key, normalized);
    state = normalized;
  }

  Future<void> resetToDefault() async {
    await ref.read(sharedPreferencesProvider).remove(_key);
    state = ApiConfig.defaultBaseUrl;
  }
}

final apiBaseUrlProvider = NotifierProvider<ApiBaseUrlNotifier, String>(ApiBaseUrlNotifier.new);

final dioProvider = Provider<Dio>((ref) {
  final dio = GlassesApi.createDio(ref.watch(apiBaseUrlProvider));
  ref.onDispose(dio.close);
  return dio;
});

final glassesApiProvider = Provider<GlassesApi>((ref) => GlassesApi(ref.watch(dioProvider)));

final glassesRepositoryProvider =
    Provider<GlassesRepository>((ref) => GlassesRepository(ref.watch(glassesApiProvider)));

// ----------------------------------------------------------------- catalogue

final catalogueProvider = FutureProvider<CatalogueResult>(
  (ref) => ref.watch(glassesRepositoryProvider).loadCatalogue(),
);

/// GET /glasses/{id}, falling back to the already-loaded catalogue item.
final glassesDetailProvider = FutureProvider.autoDispose.family<Glasses, int>((ref, id) async {
  final catalogue = await ref.watch(catalogueProvider.future);
  if (catalogue.isOffline) {
    return catalogue.items.firstWhere((g) => g.id == id);
  }
  return ref.watch(glassesRepositoryProvider).loadById(id, fallback: catalogue.items);
});

// ----------------------------------------------------------------- favorites

/// Favorite frame ids, stored locally (no account needed).
class FavoritesNotifier extends Notifier<Set<int>> {
  static const _key = 'favorite_glasses_ids';

  @override
  Set<int> build() {
    final raw = ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [];
    return raw.map(int.tryParse).whereType<int>().toSet();
  }

  bool isFavorite(int id) => state.contains(id);

  Future<void> toggle(int id) async {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(_key, next.map((e) => e.toString()).toList());
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, Set<int>>(FavoritesNotifier.new);

// ------------------------------------------------------------------- try-on

class SelectedGlassesNotifier extends Notifier<Glasses?> {
  @override
  Glasses? build() => null;

  void select(Glasses glasses) => state = glasses;
}

final selectedGlassesProvider =
    NotifierProvider<SelectedGlassesNotifier, Glasses?>(SelectedGlassesNotifier.new);

class FitAdjustmentNotifier extends Notifier<FitAdjustment> {
  @override
  FitAdjustment build() => FitAdjustment.identity;

  void update(FitAdjustment value) => state = value;

  void reset() => state = FitAdjustment.identity;
}

final fitAdjustmentProvider =
    NotifierProvider<FitAdjustmentNotifier, FitAdjustment>(FitAdjustmentNotifier.new);

/// Decoded overlay PNG for painting. Network overlays fall back to the bundled
/// copy with the same file name when the download fails.
final overlayImageProvider = FutureProvider.family<ui.Image, String>((ref, source) async {
  Future<Uint8List> fromAsset(String path) async =>
      (await rootBundle.load(path)).buffer.asUint8List();

  Uint8List bytes;
  if (source.startsWith('http://') || source.startsWith('https://')) {
    try {
      final res = await ref
          .read(dioProvider)
          .get<List<int>>(source, options: Options(responseType: ResponseType.bytes));
      bytes = Uint8List.fromList(res.data!);
    } on DioException {
      bytes = await fromAsset('assets/glasses/${Uri.parse(source).pathSegments.last}');
    }
  } else {
    bytes = await fromAsset(source);
  }
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
});

// --------------------------------------------------------------- navigation

enum AppTab { home, catalogue, tryOn, favorites }

/// What the Try-On screen should do when it opens.
enum TryOnLaunch { live, pickPhoto }

class NavigationNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  void go(AppTab tab) => state = tab;
}

final navigationProvider = NotifierProvider<NavigationNotifier, AppTab>(NavigationNotifier.new);

class TryOnLaunchNotifier extends Notifier<TryOnLaunch> {
  @override
  TryOnLaunch build() => TryOnLaunch.live;

  void set(TryOnLaunch value) => state = value;
}

final tryOnLaunchProvider =
    NotifierProvider<TryOnLaunchNotifier, TryOnLaunch>(TryOnLaunchNotifier.new);

/// Opens the Try-On tab with [glasses] selected.
void openTryOn(WidgetRef ref, {Glasses? glasses, TryOnLaunch launch = TryOnLaunch.live}) {
  if (glasses != null) ref.read(selectedGlassesProvider.notifier).select(glasses);
  ref.read(tryOnLaunchProvider.notifier).set(launch);
  ref.read(navigationProvider.notifier).go(AppTab.tryOn);
}
