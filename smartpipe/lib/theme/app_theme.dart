import 'package:flutter/material.dart';

class AppTheme {
  // Primary colors - Enhanced for better contrast
  static const Color primaryColor = Color(
    0xFF1565C0,
  ); // Blue 800 - Darker for better contrast
  static const Color primaryColorLight = Color(
    0xFF42A5F5,
  ); // Blue 400 - For lighter elements
  static const Color primaryColorDark = Color(
    0xFF0D47A1,
  ); // Blue 900 - For emphasis
  static const Color secondaryColor = Color(
    0xFF00838F,
  ); // Cyan 700 - Darker for better readability
  static const Color accentColor = Color(
    0xFF388E3C,
  ); // Green 600 - Better contrast

  // Status colors - Improved for accessibility
  static const Color successColor = Color(
    0xFF2E7D32,
  ); // Green 800 - Higher contrast
  static const Color successColorLight = Color(
    0xFF4CAF50,
  ); // Green 500 - For backgrounds
  static const Color warningColor = Color(
    0xFFE65100,
  ); // Orange 900 - Better than amber for contrast
  static const Color warningColorLight = Color(
    0xFFFF9800,
  ); // Orange 500 - For backgrounds
  static const Color errorColor = Color(
    0xFFC62828,
  ); // Red 800 - Higher contrast
  static const Color errorColorLight = Color(
    0xFFE53935,
  ); // Red 600 - For backgrounds
  static const Color infoColor = Color(
    0xFF1565C0,
  ); // Blue 800 - Consistent with primary
  static const Color infoColorLight = Color(
    0xFF2196F3,
  ); // Blue 500 - For backgrounds

  // Background colors - Enhanced hierarchy
  static const Color scaffoldBackgroundColor = Color(
    0xFFFAFAFA,
  ); // Slightly warmer grey
  static const Color cardColor = Colors.white;
  static const Color surfaceColor = Color(0xFFF8F9FA); // Light surface color
  static const Color dividerColor = Color(0xFFE0E0E0); // Clear dividers

  // Text colors - Improved contrast ratios
  static const Color primaryTextColor = Color(
    0xFF1A1A1A,
  ); // Almost black for maximum contrast
  static const Color secondaryTextColor = Color(
    0xFF616161,
  ); // Grey 700 - Better contrast than 600
  static const Color tertiaryTextColor = Color(
    0xFF9E9E9E,
  ); // Grey 500 - For less important text
  static const Color disabledTextColor = Color(0xFFBDBDBD); // Grey 400
  static const Color onPrimaryTextColor =
      Colors.white; // Text on primary color backgrounds
  static const Color onSurfaceTextColor = Color(
    0xFF1A1A1A,
  ); // Text on surface backgrounds

  // Device-specific colors - Enhanced for better contrast and accessibility
  static Map<String, Color> deviceColors = {
    'device_01': const Color(
      0xFFF57F17,
    ), // Amber 800 - Better contrast than bright yellow
    'device_02': const Color(0xFF1565C0), // Blue 800 - Consistent with primary
    'device_03': const Color(0xFF2E7D32), // Green 800 - Better contrast
    'device_04': const Color(0xFFC62828), // Red 800 - Better contrast
    'device_05': const Color(0xFF4A148C), // Purple 900 - Better contrast
    'device_06': const Color(0xFF00695C), // Teal 800 - Better contrast
    'device_07': const Color(0xFFE65100), // Orange 900 - Better contrast
    'device_08': const Color(0xFFAD1457), // Pink 800 - Better contrast
  };

  // Get a color for a device, generating one if needed
  static Color getDeviceColor(String deviceId) {
    if (!deviceColors.containsKey(deviceId)) {
      // List of high-contrast colors to choose from
      final List<Color> accessibleColors = [
        const Color(0xFFF57F17), // Amber 800
        const Color(0xFF1565C0), // Blue 800
        const Color(0xFF2E7D32), // Green 800
        const Color(0xFFC62828), // Red 800
        const Color(0xFF4A148C), // Purple 900
        const Color(0xFF00695C), // Teal 800
        const Color(0xFFE65100), // Orange 900
        const Color(0xFFAD1457), // Pink 800
        const Color(0xFF283593), // Indigo 800
        const Color(0xFF00838F), // Cyan 700
        const Color(0xFF558B2F), // Light Green 800
        const Color(0xFFFF8F00), // Amber 700
        const Color(0xFF6A1B9A), // Purple 800
        const Color(0xFF0097A7), // Cyan 800
        const Color(0xFF689F38), // Light Green 700
        const Color(0xFFEF6C00), // Orange 800
      ];

      // Use the hash code to select a color from the list
      final int index = deviceId.hashCode.abs() % accessibleColors.length;
      deviceColors[deviceId] = accessibleColors[index];
    }

    return deviceColors[deviceId]!;
  }

  // Card decoration
  static BoxDecoration cardDecoration = BoxDecoration(
    color: cardColor,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withAlpha(13), // 0.05 opacity (13/255)
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  // Text styles - Enhanced typography hierarchy
  static const TextStyle headingStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: primaryTextColor,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const TextStyle subheadingStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: primaryTextColor,
    letterSpacing: -0.25,
    height: 1.3,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: 16,
    color: primaryTextColor,
    height: 1.4,
  );

  static const TextStyle bodyMediumStyle = TextStyle(
    fontSize: 14,
    color: primaryTextColor,
    height: 1.4,
  );

  static const TextStyle captionStyle = TextStyle(
    fontSize: 12,
    color: secondaryTextColor,
    height: 1.3,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: primaryTextColor,
    letterSpacing: 0.1,
  );

  // Status text styles
  static const TextStyle successTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: successColor,
  );

  static const TextStyle warningTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: warningColor,
  );

  static const TextStyle errorTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: errorColor,
  );

  // Button styles - Enhanced for better accessibility and contrast
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: onPrimaryTextColor,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    elevation: 2,
    shadowColor: primaryColor.withAlpha(50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );

  static ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primaryColor,
    side: BorderSide(color: primaryColor, width: 2),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );

  static ButtonStyle successButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: successColor,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    elevation: 2,
    shadowColor: successColor.withAlpha(50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  );

  static ButtonStyle warningButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: warningColor,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    elevation: 2,
    shadowColor: warningColor.withAlpha(50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  );

  static ButtonStyle dangerButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: errorColor,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    elevation: 2,
    shadowColor: errorColor.withAlpha(50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  );

  // App theme data
  static ThemeData lightTheme = ThemeData(
    primaryColor: primaryColor,
    scaffoldBackgroundColor: scaffoldBackgroundColor,
    cardColor: cardColor,
    colorScheme: ColorScheme.light(
      primary: primaryColor,
      primaryContainer: primaryColorLight,
      secondary: secondaryColor,
      surface: cardColor,
      surfaceContainerHighest: surfaceColor,
      error: errorColor,
      errorContainer: errorColorLight,
      onPrimary: onPrimaryTextColor,
      onSecondary: Colors.white,
      onSurface: onSurfaceTextColor,

      onError: Colors.white,
      outline: dividerColor,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: onPrimaryTextColor,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: onPrimaryTextColor,
        letterSpacing: 0.15,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButtonStyle),
    cardTheme: CardTheme(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    textTheme: const TextTheme(
      headlineMedium: headingStyle,
      titleLarge: subheadingStyle,
      bodyLarge: bodyStyle,
      bodyMedium: captionStyle,
    ),
  );
}
