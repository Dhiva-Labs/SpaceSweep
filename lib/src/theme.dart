import 'package:flutter/material.dart';

/// "Lilac night": ink-black and lavender-white surfaces, a lilac primary and
/// pink, lime and peach accents. Hand-picked rather than seed-generated.
class SweepColors extends ThemeExtension<SweepColors> {
  const SweepColors({
    required this.hero,
    required this.onHero,
    required this.onHeroMuted,
    required this.heroTrack,
    required this.lilac,
    required this.pink,
    required this.lime,
    required this.peach,
  });

  /// The dark signature card used for headline numbers on every screen.
  final Color hero;
  final Color onHero;
  final Color onHeroMuted;

  /// Unfilled part of the storage ring on the hero card.
  final Color heroTrack;

  final Color lilac;
  final Color pink;
  final Color lime;
  final Color peach;

  List<Color> get accents => [lilac, pink, lime, peach];

  static const light = SweepColors(
    hero: Color(0xFF1F1B2E),
    onHero: Color(0xFFF3F1FA),
    onHeroMuted: Color(0xFFA9A4C0),
    heroTrack: Color(0xFF3A3550),
    lilac: Color(0xFF7A5CF0),
    pink: Color(0xFFE0558A),
    lime: Color(0xFF6E9C1E),
    peach: Color(0xFFE0882F),
  );

  static const dark = SweepColors(
    hero: Color(0xFF1F1B2E),
    onHero: Color(0xFFF3F1FA),
    onHeroMuted: Color(0xFFA9A4C0),
    heroTrack: Color(0xFF353048),
    lilac: Color(0xFFB79CFF),
    pink: Color(0xFFFF8FB8),
    lime: Color(0xFFC8F07A),
    peach: Color(0xFFFFB27A),
  );

  static SweepColors of(BuildContext context) =>
      Theme.of(context).extension<SweepColors>()!;

  @override
  SweepColors copyWith() => this;

  @override
  SweepColors lerp(SweepColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return SweepColors(
      hero: mix(hero, other.hero),
      onHero: mix(onHero, other.onHero),
      onHeroMuted: mix(onHeroMuted, other.onHeroMuted),
      heroTrack: mix(heroTrack, other.heroTrack),
      lilac: mix(lilac, other.lilac),
      pink: mix(pink, other.pink),
      lime: mix(lime, other.lime),
      peach: mix(peach, other.peach),
    );
  }
}

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF7A5CF0),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFE9E2FF),
  onPrimaryContainer: Color(0xFF2A1A6E),
  secondary: Color(0xFFE0558A),
  onSecondary: Color(0xFFFFFFFF),
  // Tonal buttons and selected chips use this: a lilac-tinted neutral keeps
  // them calm, while `secondary` stays the pink accent.
  secondaryContainer: Color(0xFFECE6FF),
  onSecondaryContainer: Color(0xFF2A1A6E),
  tertiary: Color(0xFF6E9C1E),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFE3F4C4),
  onTertiaryContainer: Color(0xFF263A05),
  error: Color(0xFFC62F3E),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD8),
  onErrorContainer: Color(0xFF5E0B14),
  surface: Color(0xFFF5F3FB),
  onSurface: Color(0xFF191726),
  onSurfaceVariant: Color(0xFF6C6880),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFEFECF7),
  surfaceContainerHigh: Color(0xFFE9E6F3),
  surfaceContainerHighest: Color(0xFFE3DFEE),
  outline: Color(0xFF8E8AA3),
  outlineVariant: Color(0xFFDAD6E6),
  inverseSurface: Color(0xFF2A2738),
  onInverseSurface: Color(0xFFF3F1FA),
  inversePrimary: Color(0xFFB79CFF),
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFB79CFF),
  onPrimary: Color(0xFF24124F),
  primaryContainer: Color(0xFF3A2E66),
  onPrimaryContainer: Color(0xFFE9E2FF),
  secondary: Color(0xFFFF8FB8),
  onSecondary: Color(0xFF4A0F2A),
  secondaryContainer: Color(0xFF2E2747),
  onSecondaryContainer: Color(0xFFE9E2FF),
  tertiary: Color(0xFFC8F07A),
  onTertiary: Color(0xFF213300),
  tertiaryContainer: Color(0xFF34460F),
  onTertiaryContainer: Color(0xFFDDF8A8),
  error: Color(0xFFFF8A8F),
  onError: Color(0xFF4F0A12),
  errorContainer: Color(0xFF6E1A24),
  onErrorContainer: Color(0xFFFFDAD8),
  surface: Color(0xFF0E0D13),
  onSurface: Color(0xFFF3F1FA),
  onSurfaceVariant: Color(0xFF9D99B0),
  surfaceContainerLowest: Color(0xFF0A090E),
  surfaceContainerLow: Color(0xFF191722),
  surfaceContainer: Color(0xFF1E1B28),
  surfaceContainerHigh: Color(0xFF25222F),
  surfaceContainerHighest: Color(0xFF2E2A3A),
  outline: Color(0xFF6E6A82),
  outlineVariant: Color(0xFF353048),
  inverseSurface: Color(0xFFF3F1FA),
  onInverseSurface: Color(0xFF191726),
  inversePrimary: Color(0xFF6B4FE0),
);

ThemeData sweepTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme : _lightScheme;
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'SpaceGrotesk',
    scaffoldBackgroundColor: scheme.surface,
    extensions: [dark ? SweepColors.dark : SweepColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'SpaceGrotesk',
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
