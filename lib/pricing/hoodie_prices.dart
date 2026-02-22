// lib/pricing/hoodie_prices.dart
// LIVE + TEST hoodie pricing catalog for Stripe Checkout wiring.
// Sizes: XS, S, M, L, XL, 2XL
// Fits: Relaxed, Slim
//
// Switch test mode at build/run time:
//   flutter run --dart-define=STRIPE_MODE=test
//   flutter build web --dart-define=STRIPE_MODE=test

// ---------- Environment switch ----------
const String _kStripeMode = String.fromEnvironment(
  'STRIPE_MODE',
  defaultValue: 'live',
);
bool get kStripeLive => _kStripeMode.toLowerCase() == 'live';

// ---------- Enums & helpers ----------
enum HoodieFit { relaxed, slim }

enum HoodieSize { xs, s, m, l, xl, twoXl }

extension HoodieFitX on HoodieFit {
  String get label => this == HoodieFit.relaxed ? 'Relaxed' : 'Slim';
  String get key => this == HoodieFit.relaxed ? 'relaxed' : 'slim';
}

extension HoodieSizeX on HoodieSize {
  String get label {
    switch (this) {
      case HoodieSize.xs:
        return 'XS';
      case HoodieSize.s:
        return 'S';
      case HoodieSize.m:
        return 'M';
      case HoodieSize.l:
        return 'L';
      case HoodieSize.xl:
        return 'XL';
      case HoodieSize.twoXl:
        return '2XL';
    }
  }

  String get key {
    switch (this) {
      case HoodieSize.xs:
        return 'xs';
      case HoodieSize.s:
        return 's';
      case HoodieSize.m:
        return 'm';
      case HoodieSize.l:
        return 'l';
      case HoodieSize.xl:
        return 'xl';
      case HoodieSize.twoXl:
        return '2xl';
    }
  }
}

// ---------- LIVE Stripe price IDs (UNCHANGED) ----------
const Map<HoodieFit, Map<HoodieSize, String>> _priceIdsLive = {
  HoodieFit.relaxed: {
    HoodieSize.xs: 'price_1SNlIQ7nP0fbhM6EvjSM5nWg',
    HoodieSize.s: 'price_1SNlI87nP0fbhM6E0OzAIl0Q',
    HoodieSize.m: 'price_1SNlHZ7nP0fbhM6E1jFYeJUz',
    HoodieSize.l: 'price_1SNlEK7nP0fbhM6EgV9I2EFR',
    HoodieSize.xl: 'price_1SNlNt7nP0fbhM6EhXMCsP7c',
    HoodieSize.twoXl: 'price_1SNlPn7nP0fbhM6EuMvGHgCT',
  },
  HoodieFit.slim: {
    HoodieSize.xs: 'price_1SNlNc7nP0fbhM6EStX7AjNX',
    HoodieSize.s: 'price_1SNlTC7nP0fbhM6EEyzR9aaL',
    HoodieSize.m: 'price_1SNlUJ7nP0fbhM6EjH0ZR8eV',
    HoodieSize.l: 'price_1SNlUY7nP0fbhM6E2RzcjBKv',
    HoodieSize.xl: 'price_1SNlam7nP0fbhM6EvNUwpyXw',
    HoodieSize.twoXl: 'price_1SNlUs7nP0fbhM6E48LaApO4',
  },
};

// ---------- TEST Stripe price IDs ----------
// For test we only care about two concrete variants:
// - Relaxed / M  => price_1SRMRP7nP0fbhM6ECcwrQ2YX
// - Slim / XS    => price_1SQnaK7nP0fbhM6E1fH0pUCh
// All other sizes map to the same IDs to keep the app working during tests.
final Map<HoodieFit, Map<HoodieSize, String>> _priceIdsTest = {
  HoodieFit.relaxed: {
    HoodieSize.m: 'price_1SRMRP7nP0fbhM6ECcwrQ2YX', // TEST: Relaxed / M
    // map remaining sizes to same test price (not used in test selection)
    HoodieSize.xs: 'price_1SRMRP7nP0fbhM6ECcwrQ2YX',
    HoodieSize.s: 'price_1SRMRP7nP0fbhM6ECcwrQ2YX',
    HoodieSize.l: 'price_1SRMRP7nP0fbhM6ECcwrQ2YX',
    HoodieSize.xl: 'price_1SRMRP7nP0fbhM6ECcwrQ2YX',
    HoodieSize.twoXl: 'price_1SRMRP7nP0fbhM6ECcwrQ2YX',
  },
  HoodieFit.slim: {
    HoodieSize.xs: 'price_1SQnaK7nP0fbhM6E1fH0pUCh', // TEST: Slim / XS
    // map remaining sizes to same test price (not used in test selection)
    HoodieSize.s: 'price_1SQnaK7nP0fbhM6E1fH0pUCh',
    HoodieSize.m: 'price_1SQnaK7nP0fbhM6E1fH0pUCh',
    HoodieSize.l: 'price_1SQnaK7nP0fbhM6E1fH0pUCh',
    HoodieSize.xl: 'price_1SQnaK7nP0fbhM6E1fH0pUCh',
    HoodieSize.twoXl: 'price_1SQnaK7nP0fbhM6E1fH0pUCh',
  },
};

// ---------- Lookup key ----------
String hoodieLookupKey(HoodieFit fit, HoodieSize size) =>
    'hoodie_${size.key}_${fit.key}';

// ---------- Price resolution (mode-aware) ----------
String getHoodiePriceId({required HoodieFit fit, required HoodieSize size}) {
  final map = kStripeLive ? _priceIdsLive : _priceIdsTest;
  final id = map[fit]?[size];
  if (id == null || id.isEmpty) {
    throw StateError(
      'No Stripe price for ${fit.key}/${size.label} in ${kStripeLive ? 'LIVE' : 'TEST'} mode',
    );
  }
  return id;
}

// ---------- DTO ----------
class HoodieOption {
  final HoodieFit fit;
  final HoodieSize size;
  final String lookupKey; // e.g., hoodie_xl_relaxed
  final String priceId; // Stripe price_...
  final int amountCents; // 6900 by default
  final String currency; // 'usd' by default

  const HoodieOption({
    required this.fit,
    required this.size,
    required this.lookupKey,
    required this.priceId,
    this.amountCents = 6900,
    this.currency = 'usd',
  });

  String get displayLabel => '${size.label} – ${fit.label} fit';

  Map<String, dynamic> toJson() => {
    'fit': fit.key,
    'size': size.key,
    'lookupKey': lookupKey,
    'priceId': priceId,
    'amountCents': amountCents,
    'currency': currency,
  };

  factory HoodieOption.fromJson(Map<String, dynamic> j) {
    // Back-compat: legacy 'tailored' is treated as 'slim'
    final String fitRaw = (j['fit'] as String? ?? '').trim().toLowerCase();
    final HoodieFit fit =
        (fitRaw == 'slim' || fitRaw == 'tailored')
            ? HoodieFit.slim
            : HoodieFit.relaxed;

    final HoodieSize size;
    switch (j['size']) {
      case 'xs':
        size = HoodieSize.xs;
        break;
      case 's':
        size = HoodieSize.s;
        break;
      case 'm':
        size = HoodieSize.m;
        break;
      case 'l':
        size = HoodieSize.l;
        break;
      case 'xl':
        size = HoodieSize.xl;
        break;
      case '2xl':
        size = HoodieSize.twoXl;
        break;
      default:
        size = HoodieSize.m; // fallback
    }
    return HoodieOption(
      fit: fit,
      size: size,
      lookupKey: j['lookupKey'] as String,
      priceId: j['priceId'] as String,
      amountCents: (j['amountCents'] as num?)?.toInt() ?? 6900,
      currency: (j['currency'] as String?) ?? 'usd',
    );
  }
}

// ---------- Prebuilt option lists ----------
final List<HoodieOption> hoodieOptionsLive = [
  for (final entry in _priceIdsLive.entries)
    for (final sizeEntry in entry.value.entries)
      HoodieOption(
        fit: entry.key,
        size: sizeEntry.key,
        lookupKey: hoodieLookupKey(entry.key, sizeEntry.key),
        priceId: sizeEntry.value,
      ),
];

final List<HoodieOption> hoodieOptionsTest = [
  for (final entry in _priceIdsTest.entries)
    for (final sizeEntry in entry.value.entries)
      HoodieOption(
        fit: entry.key,
        size: sizeEntry.key,
        lookupKey: hoodieLookupKey(entry.key, sizeEntry.key),
        priceId: sizeEntry.value,
      ),
];

// Mode-aware getter (optional)
List<HoodieOption> get hoodieOptions =>
    kStripeLive ? hoodieOptionsLive : hoodieOptionsTest;

// ---------- Find by lookup key (mode-aware) ----------
HoodieOption? findHoodieByLookupKey(String key) {
  try {
    return hoodieOptions.firstWhere((o) => o.lookupKey == key);
  } catch (_) {
    // Back-compat: rescue legacy "_tailored" keys by mapping to "_slim"
    if (key.contains('_tailored')) {
      final k2 = key.replaceFirst('_tailored', '_slim');
      try {
        return hoodieOptions.firstWhere((o) => o.lookupKey == k2);
      } catch (_) {
        // fall through
      }
    }
    return null;
  }
}
