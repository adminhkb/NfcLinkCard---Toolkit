// Composants d'interface partagés, calqués sur ceux de l'ERP (cartes, pastilles, titres, tuiles).
import 'package:flutter/material.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';

/// Fond de l'application : le motif de l'ERP, répété, légèrement assombri.
class NlcBackground extends StatelessWidget {
  const NlcBackground({super.key, required this.child, this.dim = 0.2});

  final Widget child;

  /// Opacité du voile sombre posé sur le motif.
  final double dim;

  static const _tile = AssetImage('assets/fond-erp.png');

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Nlc.pattern,
        image: DecorationImage(
          image: _tile,
          repeat: ImageRepeat.repeat,
          alignment: Alignment.topCenter,
          // L'image est dessinée à deux fois la taille de la tuile pour rester nette.
          scale: 2,
          filterQuality: FilterQuality.medium,
        ),
      ),
      child: ColoredBox(
        color: Nlc.slate950.withValues(alpha: dim),
        child: child,
      ),
    );
  }
}

/// Nom de l'application, en dégradé bleu-indigo comme le titre de l'ERP.
class NlcBrand extends StatelessWidget {
  const NlcBrand({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => Nlc.brandGradient.createShader(bounds),
      child: Text(
        'NLC Toolkit',
        maxLines: 1,
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
    );
  }
}

/// Carte translucide à liseré, posée sur le motif.
class NlcCard extends StatelessWidget {
  const NlcCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.accent,
    this.borderColor,
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Barre verticale de couleur sur le bord gauche (tuiles d'indicateurs).
  final Color? accent;
  final Color? borderColor;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      content = Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: accent),
          ),
          content,
        ],
      );
    }
    return Material(
      color: color ?? Nlc.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Nlc.radiusCard),
        side: BorderSide(color: borderColor ?? Nlc.border),
      ),
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Sur-titre en capitales espacées, avec une petite icône.
class NlcEyebrow extends StatelessWidget {
  const NlcEyebrow(
    this.text, {
    super.key,
    this.icon,
    this.color = Nlc.indigo300,
  });

  final String text;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// En-tête de page : sur-titre, titre, sous-titre et boutons d'action.
class NlcPageHeader extends StatelessWidget {
  const NlcPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.eyebrowIcon,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? eyebrow;
  final IconData? eyebrowIcon;

  /// Texte ou widget sous le titre.
  final Widget? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null) ...[
          NlcEyebrow(eyebrow!, icon: eyebrowIcon),
          const SizedBox(height: 6),
        ],
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          DefaultTextStyle.merge(
            style: const TextStyle(
              color: Nlc.slate400,
              fontSize: 14,
              height: 1.4,
            ),
            child: subtitle!,
          ),
        ],
      ],
    );
    if (actions.isEmpty) return heading;
    final buttons = Wrap(spacing: 8, runSpacing: 8, children: actions);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 16), buttons],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            buttons,
          ],
        );
      },
    );
  }
}

/// Titre de section en capitales, avec une action à droite.
class NlcSectionTitle extends StatelessWidget {
  const NlcSectionTitle(
    this.title, {
    super.key,
    this.action,
    this.color = Nlc.slate400,
    this.icon,
  });

  final String title;
  final Widget? action;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Pastille d'état : fond teinté, liseré et texte de la même couleur.
class NlcChip extends StatelessWidget {
  const NlcChip(this.label, {super.key, this.color = Nlc.slate400, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            maxLines: 1,
            style: TextStyle(
              color: Color.lerp(color, Colors.white, 0.25),
              fontSize: 10,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icône dans un carré teinté.
class NlcIconBox extends StatelessWidget {
  const NlcIconBox(
    this.icon, {
    super.key,
    this.color = Nlc.indigo400,
    this.size = 42,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.29),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// Tuile d'indicateur : libellé, grande valeur, précision, barre de couleur à gauche.
class NlcStatCard extends StatelessWidget {
  const NlcStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
    required this.icon,
    this.footer,
    this.valueColor = Colors.white,
    this.onTap,
  });

  final String label;
  final String value;
  final Color accent;
  final IconData icon;
  final String? footer;
  final Color valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return NlcCard(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Nlc.slate400,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: Nlc.slate500),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 24,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(
              footer!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Nlc.slate400,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Petit encart chiffré à l'intérieur d'une carte.
class NlcMini extends StatelessWidget {
  const NlcMini({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Nlc.inset,
        borderRadius: BorderRadius.circular(Nlc.radius),
        border: Border.all(color: Nlc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Nlc.slate500,
              fontSize: 10,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Nlc.slate500,
                fontSize: 10,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Message quand une liste est vide.
class NlcEmptyHint extends StatelessWidget {
  const NlcEmptyHint({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: Nlc.slate600),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Nlc.slate300,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (text != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                text!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Nlc.slate400,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

enum NlcTone { info, success, warning, danger }

Color nlcToneColor(NlcTone tone) => switch (tone) {
  NlcTone.info => Nlc.indigo400,
  NlcTone.success => Nlc.emerald400,
  NlcTone.warning => Nlc.amber400,
  NlcTone.danger => Nlc.rose400,
};

/// Bandeau d'information, d'alerte ou d'erreur.
class NlcNotice extends StatelessWidget {
  const NlcNotice({
    super.key,
    required this.message,
    this.tone = NlcTone.info,
    this.icon,
    this.action,
    this.dense = false,
  });

  final String message;
  final NlcTone tone;
  final IconData? icon;
  final Widget? action;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = nlcToneColor(tone);
    final defaultIcon = switch (tone) {
      NlcTone.info => Icons.info_outline_rounded,
      NlcTone.success => Icons.check_circle_outline_rounded,
      NlcTone.warning => Icons.warning_amber_rounded,
      NlcTone.danger => Icons.error_outline_rounded,
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Nlc.radius),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? defaultIcon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Color.lerp(color, Colors.white, 0.45),
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 10), action!],
        ],
      ),
    );
  }
}

/// Sélecteur à segments de l'ERP : fond sombre, segment actif en ardoise.
class NlcSegmented<T> extends StatelessWidget {
  const NlcSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.expand = true,
  });

  final T value;
  final List<({T value, String label, IconData? icon})> options;
  final ValueChanged<T> onChanged;

  /// Les segments se partagent toute la largeur disponible.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Nlc.slate950,
        borderRadius: BorderRadius.circular(Nlc.radius),
        border: Border.all(color: Nlc.border),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final option in options)
            if (expand) Expanded(child: _segment(option)) else _segment(option),
        ],
      ),
    );
  }

  Widget _segment(({T value, String label, IconData? icon}) option) {
    final selected = option.value == value;
    final color = selected ? Colors.white : Nlc.slate400;
    return Material(
      color: selected ? Nlc.slate800 : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selected ? null : () => onChanged(option.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: 15, color: color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Libellé de champ en petites capitales, au-dessus d'un champ de saisie.
class NlcFieldLabel extends StatelessWidget {
  const NlcFieldLabel(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: const TextStyle(
          color: Nlc.slate400,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Tuile cliquable qui mène à une fonction : icône, titre, description.
class NlcActionTile extends StatelessWidget {
  const NlcActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.enabled = true,
    this.disabledHint,
    this.color = Nlc.indigo400,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool enabled;

  /// Remplace la description quand la tuile est indisponible.
  final String? disabledHint;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      child: NlcCard(
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NlcIconBox(icon, color: enabled ? color : Nlc.slate600),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? Colors.white : Nlc.slate500,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    enabled ? description : (disabledHint ?? description),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Nlc.slate400,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                Icon(
                  enabled
                      ? Icons.arrow_forward_rounded
                      : Icons.lock_outline_rounded,
                  size: 18,
                  color: enabled ? color : Nlc.slate600,
                ),
          ],
        ),
      ),
    );
  }
}

/// Contenu d'une page : défilement vertical, largeur maximale, marges qui suivent la fenêtre.
class NlcPageBody extends StatelessWidget {
  const NlcPageBody({super.key, required this.children, this.maxWidth = 1280});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 32,
            compact ? 20 : 32,
            compact ? 16 : 32,
            40,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Point lumineux qui bat doucement (données à jour, appareil connecté).
class NlcPulseDot extends StatefulWidget {
  const NlcPulseDot({
    super.key,
    this.color = Nlc.emerald400,
    this.size = 8,
    this.animate = true,
  });

  final Color color;
  final double size;
  final bool animate;

  @override
  State<NlcPulseDot> createState() => _NlcPulseDotState();
}

class _NlcPulseDotState extends State<NlcPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(NlcPulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size * 2,
      height: size * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.animate)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Opacity(
                opacity: (1 - _controller.value) * 0.6,
                child: Container(
                  width: size * (1 + _controller.value),
                  height: size * (1 + _controller.value),
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Message bref en bas de l'écran, vert comme les confirmations de l'ERP.
void showNlcToast(BuildContext context, String message, {bool success = true}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: success ? Nlc.emerald500 : Nlc.rose500,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Nlc.radius),
        ),
        duration: const Duration(seconds: 3),
        content: Text(
          message,
          style: const TextStyle(
            color: Nlc.slate950,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
}
