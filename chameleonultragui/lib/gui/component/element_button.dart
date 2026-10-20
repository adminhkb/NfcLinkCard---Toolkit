import 'dart:math';

import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/gui/component/card_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ElementButton extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String firstLine;
  final String secondLine;
  final List<Widget> children;
  final int itemIndex;
  final VoidCallback? onPressed;
  final int maxLineLines;

  const ElementButton({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.firstLine,
    required this.secondLine,
    required this.children,
    required this.itemIndex,
    required this.onPressed,
    this.maxLineLines = 1,
  });

  @override
  ElementButtonState createState() => ElementButtonState();
}

class ElementButtonState extends State<ElementButton> {
  static const double _iconSize = 26.0;
  static const double _iconSpacing = 14.0;

  @override
  void initState() {
    super.initState();
  }

  double _getIconButtonWidth(BuildContext context) {
    final MaterialTapTargetSize tapTargetSize = Theme.of(context)
        .materialTapTargetSize;

    return tapTargetSize == MaterialTapTargetSize.padded ? 48.0 : 40.0;
  }

  bool _shouldMoveIcons(BuildContext context, double availableWidth) {
    if (widget.children.isEmpty) return false;

    double iconButtonWidth = _getIconButtonWidth(context);
    double iconsWidth = widget.children.length * iconButtonWidth + 8;

    TextStyle textStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    TextPainter firstLinePainter = TextPainter(
      text: TextSpan(text: widget.firstLine, style: textStyle),
      maxLines: 1,
      textScaler: MediaQuery.of(context).textScaler,
      textDirection: TextDirection.ltr,
    )..layout();

    TextPainter secondLinePainter = TextPainter(
      text: TextSpan(text: widget.secondLine, style: textStyle),
      maxLines: 1,
      textScaler: MediaQuery.of(context).textScaler,
      textDirection: TextDirection.ltr,
    )..layout();

    double textWidth = max(
      firstLinePainter.size.width,
      secondLinePainter.size.width,
    );

    double horizontalSpacing = 44.0 + _iconSpacing;

    double contentWidthNeeded = horizontalSpacing + textWidth;
    double totalWidthNeeded = contentWidthNeeded + iconsWidth;

    return totalWidthNeeded > availableWidth;
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final iconColor = widget.onPressed == null
        ? colors.onSurfaceVariant
        : widget.iconColor;

    return ElevatedButton(
      onPressed: widget.onPressed,
      style: customCardButtonStyle(appState),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            bool moveIcons = _shouldMoveIcons(context, constraints.maxWidth);

            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: !moveIcons ? 90 : 130),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          widget.icon,
                          color: iconColor,
                          size: _iconSize,
                        ),
                      ),
                      const SizedBox(width: _iconSpacing),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.firstLine,
                              maxLines: widget.maxLineLines,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: widget.onPressed == null
                                    ? colors.onSurfaceVariant
                                    : colors.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.secondLine,
                              maxLines: widget.maxLineLines,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!moveIcons) ...widget.children,
                    ],
                  ),
                  if (moveIcons) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: widget.children,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
