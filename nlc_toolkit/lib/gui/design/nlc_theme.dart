import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nlc_toolkit/helpers/font.dart';

/// Couleurs de l'interface, reprises de l'ERP (palette Tailwind : ardoise, indigo et accents).
class Nlc {
  const Nlc._();

  // Fonds.
  static const canvas = Color(0xFF0B0F19); // fond de page de l'ERP
  static const pattern = Color(0xFF161C2C); // bleu nuit du motif
  static const page = Color(
    0xFF111626,
  ); // page ouverte par-dessus l'application

  // Ardoise.
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);

  // Accent principal.
  static const indigo300 = Color(0xFFA5B4FC);
  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo950 = Color(0xFF1E1B4B);
  static const blue400 = Color(0xFF60A5FA);
  static const blue500 = Color(0xFF3B82F6);
  static const blue600 = Color(0xFF2563EB);
  static const purple500 = Color(0xFFA855F7);

  // États.
  static const emerald300 = Color(0xFF6EE7B7);
  static const emerald400 = Color(0xFF34D399);
  static const emerald500 = Color(0xFF10B981);
  static const amber300 = Color(0xFFFCD34D);
  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const rose300 = Color(0xFFFDA4AF);
  static const rose400 = Color(0xFFFB7185);
  static const rose500 = Color(0xFFF43F5E);
  static const red400 = Color(0xFFF87171);
  static const red500 = Color(0xFFEF4444);
  static const violet200 = Color(0xFFDDD6FE);
  static const violet300 = Color(0xFFC4B5FD);
  static const violet400 = Color(0xFFA78BFA);
  static const violet500 = Color(0xFF8B5CF6);
  static const sky300 = Color(0xFF7DD3FC);
  static const sky400 = Color(0xFF38BDF8);
  static const sky500 = Color(0xFF0EA5E9);

  // Surfaces.
  /// Carte posée sur le motif : assez sombre pour le texte, assez claire pour laisser deviner le fond.
  static const card = Color(0x99020617);

  /// Encart à l'intérieur d'une carte.
  static const inset = Color(0xB30F172A);
  static const border = slate800;

  static const radiusSmall = 8.0;
  static const radius = 12.0;
  static const radiusCard = 16.0;
  static const radiusDialog = 24.0;

  /// Dégradé du nom de l'application, comme le titre de l'ERP.
  static const brandGradient = LinearGradient(colors: [blue400, indigo400]);

  /// Dégradé des boutons de validation de l'écran de sécurité.
  static const actionGradient = LinearGradient(colors: [blue600, indigo600]);

  /// Couleurs d'accent de l'établissement actif (`colorTheme` de l'ERP).
  static NlcAccent accentFor(String colorTheme) => switch (colorTheme) {
    'emerald' => const NlcAccent(
      Color(0xFF34D399),
      Color(0xFF10B981),
      Color(0xFF022C22),
    ),
    'blue' => const NlcAccent(
      Color(0xFF60A5FA),
      Color(0xFF3B82F6),
      Color(0xFF172554),
    ),
    'violet' => const NlcAccent(
      Color(0xFFA78BFA),
      Color(0xFF8B5CF6),
      Color(0xFF2E1065),
    ),
    'rose' => const NlcAccent(
      Color(0xFFFB7185),
      Color(0xFFF43F5E),
      Color(0xFF4C0519),
    ),
    _ => const NlcAccent(indigo400, indigo500, indigo950),
  };
}

/// Trois teintes d'un accent : texte, liseré et fond.
class NlcAccent {
  const NlcAccent(this.text, this.line, this.deep);

  final Color text;
  final Color line;
  final Color deep;

  /// Fond d'une entrée de menu active.
  Color get wash => deep.withValues(alpha: 0.5);
}

class NlcTheme {
  const NlcTheme._();

  /// Thème de l'application. L'interface est sombre, comme l'ERP.
  static ThemeData get dark => _theme;

  static final ThemeData _theme = _build();

  static ThemeData _build() {
    const brightness = Brightness.dark;
    final shape12 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Nlc.radius),
    );

    final colors =
        ColorScheme.fromSeed(
          seedColor: Nlc.indigo500,
          brightness: brightness,
        ).copyWith(
          primary: Nlc.indigo400,
          onPrimary: Nlc.slate950,
          primaryContainer: Nlc.indigo950,
          onPrimaryContainer: Nlc.indigo300,
          secondary: Nlc.blue400,
          onSecondary: Nlc.slate950,
          secondaryContainer: Nlc.slate800,
          onSecondaryContainer: Nlc.slate200,
          tertiary: Nlc.emerald400,
          onTertiary: Nlc.slate950,
          tertiaryContainer: const Color(0xFF064E3B),
          onTertiaryContainer: Nlc.emerald300,
          error: Nlc.rose400,
          onError: Nlc.slate950,
          errorContainer: const Color(0xFF4C0519),
          onErrorContainer: Nlc.rose300,
          surface: Nlc.slate900,
          onSurface: Nlc.slate100,
          onSurfaceVariant: Nlc.slate400,
          surfaceDim: Nlc.canvas,
          surfaceBright: Nlc.slate800,
          surfaceContainerLowest: Nlc.slate950,
          surfaceContainerLow: Nlc.card,
          surfaceContainer: Nlc.slate900,
          surfaceContainerHigh: Nlc.slate800,
          surfaceContainerHighest: Nlc.slate800,
          outline: Nlc.slate700,
          outlineVariant: Nlc.slate800,
          inverseSurface: Nlc.slate100,
          onInverseSurface: Nlc.slate900,
          inversePrimary: Nlc.indigo600,
          shadow: Colors.black,
          scrim: Nlc.slate950,
          surfaceTint: Colors.transparent,
        );

    const label = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );
    WidgetStateProperty<Color?> states({
      required Color normal,
      Color? hovered,
      Color? disabled,
    }) => WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) {
        return disabled ?? normal.withValues(alpha: 0.5);
      }
      if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) {
        return hovered ?? normal;
      }
      return normal;
    });

    // Bouton secondaire de l'ERP : fond ardoise, liseré, texte clair.
    final secondaryButton = ButtonStyle(
      backgroundColor: states(normal: Nlc.slate900, hovered: Nlc.slate800),
      foregroundColor: states(normal: Nlc.slate200, disabled: Nlc.slate500),
      iconColor: states(normal: Nlc.slate200, disabled: Nlc.slate500),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStateProperty.resolveWith(
        (s) => BorderSide(
          color: s.contains(WidgetState.hovered) ? Nlc.slate700 : Nlc.slate800,
        ),
      ),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      shape: WidgetStatePropertyAll(shape12),
      textStyle: const WidgetStatePropertyAll(label),
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(Nlc.radius),
          borderSide: BorderSide(color: color, width: width),
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: Nlc.page,
      canvasColor: Nlc.slate900,
      dividerColor: Nlc.slate800,
      disabledColor: Nlc.slate600,
      hintColor: Nlc.slate600,
      splashFactory: InkSparkle.splashFactory,
      hoverColor: Nlc.slate800.withValues(alpha: 0.5),
      highlightColor: Nlc.slate800.withValues(alpha: 0.35),
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarThemeData(
        backgroundColor: Colors.transparent,
        foregroundColor: Nlc.slate50,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 24,
        toolbarHeight: 68,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: Nlc.slate300, size: 22),
        actionsIconTheme: IconThemeData(color: Nlc.slate300, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Nlc.slate950,
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Nlc.slate950,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: Nlc.card,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.all(8),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Nlc.radiusCard),
          side: const BorderSide(color: Nlc.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Nlc.slate800,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: Nlc.slate300),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: Nlc.slate900,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: Nlc.slate600, fontSize: 14),
        labelStyle: const TextStyle(color: Nlc.slate400, fontSize: 14),
        floatingLabelStyle: const TextStyle(
          color: Nlc.indigo300,
          fontWeight: FontWeight.w600,
        ),
        helperStyle: const TextStyle(color: Nlc.slate500, fontSize: 11),
        errorStyle: const TextStyle(color: Nlc.rose300, fontSize: 11),
        prefixIconColor: Nlc.slate500,
        suffixIconColor: Nlc.slate500,
        border: inputBorder(Nlc.slate800),
        enabledBorder: inputBorder(Nlc.slate800),
        disabledBorder: inputBorder(Nlc.slate800.withValues(alpha: 0.5)),
        focusedBorder: inputBorder(Nlc.indigo500, 2),
        errorBorder: inputBorder(Nlc.rose500.withValues(alpha: 0.6)),
        focusedErrorBorder: inputBorder(Nlc.rose500, 2),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Nlc.indigo400,
        selectionColor: Nlc.indigo500.withValues(alpha: 0.35),
        selectionHandleColor: Nlc.indigo400,
      ),
      // Bouton principal de l'ERP : indigo plein, texte blanc.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: states(
            normal: Nlc.indigo600,
            hovered: Nlc.indigo500,
            disabled: Nlc.slate800,
          ),
          foregroundColor: states(normal: Colors.white, disabled: Nlc.slate500),
          iconColor: states(normal: Colors.white, disabled: Nlc.slate500),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(shape12),
          textStyle: const WidgetStatePropertyAll(label),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: secondaryButton),
      outlinedButtonTheme: OutlinedButtonThemeData(style: secondaryButton),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: states(
            normal: Nlc.indigo300,
            hovered: Colors.white,
            disabled: Nlc.slate600,
          ),
          iconColor: states(
            normal: Nlc.indigo300,
            hovered: Colors.white,
            disabled: Nlc.slate600,
          ),
          overlayColor: WidgetStatePropertyAll(
            Nlc.slate800.withValues(alpha: 0.6),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          shape: WidgetStatePropertyAll(shape12),
          textStyle: const WidgetStatePropertyAll(label),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: states(
            normal: Nlc.slate400,
            hovered: Colors.white,
            disabled: Nlc.slate700,
          ),
          overlayColor: WidgetStatePropertyAll(
            Nlc.slate800.withValues(alpha: 0.9),
          ),
          shape: WidgetStatePropertyAll(shape12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Nlc.indigo600,
        foregroundColor: Colors.white,
        elevation: 4,
        focusElevation: 4,
        hoverElevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Nlc.radiusCard),
        ),
      ),
      toggleButtonsTheme: ToggleButtonsThemeData(
        color: Nlc.slate400,
        selectedColor: Colors.white,
        fillColor: Nlc.slate800,
        hoverColor: Nlc.slate800.withValues(alpha: 0.5),
        splashColor: Colors.transparent,
        borderColor: Nlc.slate800,
        selectedBorderColor: Nlc.slate700,
        disabledColor: Nlc.slate700,
        disabledBorderColor: Nlc.slate800,
        borderRadius: BorderRadius.circular(Nlc.radius),
        textStyle: label.copyWith(fontSize: 12),
        constraints: const BoxConstraints(minHeight: 38, minWidth: 48),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.selected) ? Nlc.slate800 : Nlc.slate950,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.selected) ? Colors.white : Nlc.slate400,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.selected) ? Colors.white : Nlc.slate400,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: Nlc.slate800)),
          shape: WidgetStatePropertyAll(shape12),
          textStyle: WidgetStatePropertyAll(label.copyWith(fontSize: 12)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Nlc.slate900,
        selectedColor: Nlc.indigo600.withValues(alpha: 0.25),
        disabledColor: Nlc.slate900.withValues(alpha: 0.5),
        deleteIconColor: Nlc.slate400,
        checkmarkColor: Nlc.indigo300,
        surfaceTintColor: Colors.transparent,
        side: const BorderSide(color: Nlc.slate800),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Nlc.radiusSmall),
        ),
        labelStyle: const TextStyle(
          color: Nlc.slate200,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Nlc.indigo300,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : Nlc.slate400,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Nlc.indigo600 : Nlc.slate900,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Nlc.indigo600 : Nlc.slate700,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Nlc.indigo500
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: Nlc.slate600, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Nlc.indigo400 : Nlc.slate600,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: Nlc.indigo500,
        inactiveTrackColor: Nlc.slate800,
        thumbColor: Colors.white,
        overlayColor: Nlc.indigo500.withValues(alpha: 0.15),
        valueIndicatorColor: Nlc.slate800,
        valueIndicatorTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Nlc.indigo400,
        linearTrackColor: Nlc.slate800,
        circularTrackColor: Colors.transparent,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Nlc.slate400,
        indicatorColor: Nlc.indigo400,
        dividerColor: Nlc.slate800,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: Nlc.slate400,
        textColor: Nlc.slate100,
        titleTextStyle: const TextStyle(
          color: Nlc.slate100,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: const TextStyle(color: Nlc.slate400, fontSize: 12),
        selectedColor: Nlc.indigo300,
        selectedTileColor: Nlc.indigo950.withValues(alpha: 0.5),
        shape: shape12,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: Nlc.indigo300,
        collapsedIconColor: Nlc.slate400,
        textColor: Colors.white,
        collapsedTextColor: Nlc.slate200,
        shape: shape12,
        collapsedShape: shape12,
      ),
      // Fenêtre de dialogue de l'ERP : ardoise, liseré, grands arrondis.
      dialogTheme: DialogThemeData(
        backgroundColor: Nlc.slate900,
        surfaceTintColor: Colors.transparent,
        barrierColor: Nlc.slate950.withValues(alpha: 0.8),
        elevation: 24,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Nlc.radiusDialog),
          side: const BorderSide(color: Nlc.slate800),
        ),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        contentTextStyle: const TextStyle(
          color: Nlc.slate300,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Nlc.slate900,
        modalBackgroundColor: Nlc.slate900,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Color(0xCC020617),
        showDragHandle: true,
        dragHandleColor: Nlc.slate700,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Nlc.radiusDialog),
          ),
          side: BorderSide(color: Nlc.slate800),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Nlc.slate950,
        surfaceTintColor: Colors.transparent,
        scrimColor: Color(0xCC020617),
        shape: RoundedRectangleBorder(),
        width: 264,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Nlc.slate950,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Nlc.radius),
          side: const BorderSide(color: Nlc.slate800),
        ),
        textStyle: const TextStyle(color: Nlc.slate200, fontSize: 14),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Nlc.slate950),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: const WidgetStatePropertyAll(BorderSide(color: Nlc.slate800)),
          shape: WidgetStatePropertyAll(shape12),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Nlc.slate950),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: const WidgetStatePropertyAll(BorderSide(color: Nlc.slate800)),
          shape: WidgetStatePropertyAll(shape12),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Nlc.slate800,
          borderRadius: BorderRadius.circular(Nlc.radiusSmall),
          border: Border.all(color: Nlc.slate700),
        ),
        textStyle: const TextStyle(
          color: Nlc.slate100,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Nlc.slate800,
        contentTextStyle: const TextStyle(
          color: Nlc.slate50,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: Nlc.indigo300,
        closeIconColor: Nlc.slate300,
        behavior: SnackBarBehavior.floating,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Nlc.radius),
          side: const BorderSide(color: Nlc.slate700),
        ),
      ),
      // Barre de défilement de l'ERP : fine, ardoise, indigo au survol.
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(999),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.hovered) || s.contains(WidgetState.dragged)
              ? Nlc.indigo600
              : Nlc.slate700,
        ),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Nlc.slate950,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Nlc.indigo950.withValues(alpha: 0.8),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? Nlc.indigo400
                : Nlc.slate400,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            color: s.contains(WidgetState.selected)
                ? Nlc.indigo400
                : Nlc.slate400,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: Nlc.rose500,
        textColor: Colors.white,
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1),
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        bodyLarge: TextStyle(fontSize: 15, height: 1.45),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45),
        bodySmall: TextStyle(fontSize: 12, height: 1.4, color: Nlc.slate400),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );

    return base.useCustomSystemFont(brightness);
  }
}
