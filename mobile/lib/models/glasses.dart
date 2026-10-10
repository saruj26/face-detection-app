/// How to place a transparent overlay PNG on detected eye landmarks.
///
/// Coordinates are normalised to the overlay image (0..1, origin top-left).
class FitMetadata {
  const FitMetadata({
    required this.imageWidth,
    required this.imageHeight,
    required this.eyeSpanRatio,
    this.anchorX = 0.5,
    this.anchorY = 0.5,
    this.defaultScale = 1.0,
  });

  /// Overlay PNG size in pixels (used for the aspect ratio).
  final int imageWidth;
  final int imageHeight;

  /// Fraction of the PNG width covered by the distance between the pupils.
  final double eyeSpanRatio;

  /// Point of the PNG placed at the midpoint between the eyes.
  final double anchorX;
  final double anchorY;

  /// Extra multiplier for the rendered width.
  final double defaultScale;

  double get aspectRatio => imageWidth / imageHeight;

  factory FitMetadata.fromJson(Map<String, dynamic> json) {
    final ratio = (json['eye_span_ratio'] as num?)?.toDouble() ?? 0.3;
    return FitMetadata(
      imageWidth: (json['image_width'] as num?)?.toInt() ?? 1000,
      imageHeight: (json['image_height'] as num?)?.toInt() ?? 440,
      // Guard against corrupt metadata producing absurd sizes.
      eyeSpanRatio: ratio.clamp(0.1, 0.9).toDouble(),
      anchorX: (json['anchor_x'] as num?)?.toDouble() ?? 0.5,
      anchorY: (json['anchor_y'] as num?)?.toDouble() ?? 0.5,
      defaultScale: (json['default_scale'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class Glasses {
  const Glasses({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.currency,
    required this.catalogueImageUrl,
    required this.overlayImageUrl,
    required this.fit,
    this.description,
  });

  final int id;
  final String name;
  final String category;
  final String? description;
  final double price;
  final String currency;

  /// Either an absolute http(s) URL or a bundled asset path (`assets/...`).
  final String catalogueImageUrl;
  final String overlayImageUrl;
  final FitMetadata fit;

  factory Glasses.fromJson(Map<String, dynamic> json) {
    return Glasses(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      category: json['category'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num).toDouble(),
      currency: (json['currency'] as String?) ?? 'USD',
      catalogueImageUrl: json['catalogue_image_url'] as String,
      overlayImageUrl: json['transparent_overlay_url'] as String,
      fit: FitMetadata.fromJson(
        (json['fit_metadata'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  /// Builds an item from the bundled `catalogue.json` (offline demo data),
  /// mapping backend `/static/glasses/x.png` paths to bundled asset paths.
  factory Glasses.fromBundledJson(Map<String, dynamic> json, int id) {
    String asset(String path) => 'assets/glasses/${path.split('/').last}';
    return Glasses.fromJson({
      ...json,
      'id': id,
      'catalogue_image_url': asset(json['catalogue_image_url'] as String),
      'transparent_overlay_url': asset(json['transparent_overlay_url'] as String),
    });
  }

  String get formattedPrice => formatPrice(price, currency);

  @override
  bool operator ==(Object other) => other is Glasses && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

String formatPrice(double price, String currency) {
  const symbols = {'USD': r'$', 'EUR': '€', 'GBP': '£', 'INR': '₹', 'LKR': 'Rs '};
  final symbol = symbols[currency.toUpperCase()];
  final amount = price.toStringAsFixed(2);
  return symbol != null ? '$symbol$amount' : '$amount $currency';
}
