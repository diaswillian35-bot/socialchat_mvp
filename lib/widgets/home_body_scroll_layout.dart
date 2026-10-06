import 'package:flutter/material.dart';

/// Home [ListView] insets and country-grid density.
///
/// Landscape keeps the same 3-column Meet People row but shortens tiles so
/// Discover can sit above the shell tab bar. Portrait keeps square tiles.
class HomeBodyScrollLayout {
  HomeBodyScrollLayout._();

  static const double listHorizontal = 16;
  static const double listTop = 8;
  static const double listBottom = 28;
  static const int countryCrossAxisCount = 3;
  static const double countryGridSpacing = 8;
  static const double portraitCountryAspect = 1.0;
  static const double landscapeCountryAspect = 2.2;

  /// iPad Air 11-inch (M4) logical points.
  static const Size ipadAir11Portrait = Size(820, 1180);
  static const Size ipadAir11Landscape = Size(1180, 820);

  static bool isLandscapeSize(Size size) => size.width > size.height;

  static double countryGridChildAspectRatio(Size viewport) {
    return isLandscapeSize(viewport)
        ? landscapeCountryAspect
        : portraitCountryAspect;
  }

  static EdgeInsets listPadding() {
    return const EdgeInsets.fromLTRB(
      listHorizontal,
      listTop,
      listHorizontal,
      listBottom,
    );
  }
}
