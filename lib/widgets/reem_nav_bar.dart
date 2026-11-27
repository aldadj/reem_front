import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/reem_theme.dart';

/// Hauteur de la barre flottante et espace sous elle.
const double kReemNavHeight = 68;
const double kReemNavBottomGap = 12;

/// Espace à laisser en bas d'un écran pour que son contenu ne passe pas sous la barre.
double reemNavInset(BuildContext context) {
  return kReemNavHeight + kReemNavBottomGap + MediaQuery.paddingOf(context).bottom;
}

/// Permet de cacher la barre (par exemple quand les commentaires d'une vidéo sont ouverts).
class ReemNavController {
  ReemNavController._();

  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);
}

class _NavSpec {
  const _NavSpec(this.index, this.icon, this.activeIcon, this.label);

  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Barre du bas flottante : petite capsule arrondie, fond de verre transparent
/// (la vidéo se devine derrière), pastille qui glisse avec un rebond,
/// et icône qui « saute » quand on la touche.
///
/// Index : 0 Accueil, 1 Ami(e)s, 2 Publier (bouton +), 3 Messages, 4 Profil.
class ReemNavBar extends StatelessWidget {
  const ReemNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.messagesBadge = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int messagesBadge;

  static const double _radius = 36;
  static const double _sidePadding = 8;

  static const List<_NavSpec> _specs = [
    _NavSpec(0, Icons.home_outlined, Icons.home_rounded, 'Accueil'),
    _NavSpec(1, Icons.group_outlined, Icons.group_rounded, 'Ami(e)s'),
    _NavSpec(2, Icons.add_rounded, Icons.add_rounded, 'Publier'),
    _NavSpec(3, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Messages'),
    _NavSpec(4, Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final barWidth = math.min(screenWidth - 64, 320.0);
    final slotWidth = (barWidth - _sidePadding * 2) / _specs.length;

    final activeColor = isDark ? Colors.white : const Color(0xFF6A2FE0);
    final idleColor = isDark ? const Color(0xB3FFFFFF) : const Color(0x990F1424);

    final showIndicator = currentIndex != 2;
    final pillWidth = slotWidth - 8;
    final pillLeft = _sidePadding + currentIndex * slotWidth + (slotWidth - pillWidth) / 2;

    final glass = Container(
      width: barWidth,
      height: kReemNavHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        color: isDark ? Colors.black.withValues(alpha: 0.30) : Colors.white.withValues(alpha: 0.55),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.16 : 0.55),
            Colors.white.withValues(alpha: isDark ? 0.03 : 0.12),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.75),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Pastille qui glisse vers l'onglet choisi (avec un petit dépassement = rebond)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutBack,
            left: pillLeft,
            top: 8,
            width: pillWidth,
            height: kReemNavHeight - 16,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: showIndicator ? 1 : 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    colors: [
                      ReemColors.primary.withValues(alpha: isDark ? 0.42 : 0.30),
                      ReemColors.accent.withValues(alpha: isDark ? 0.42 : 0.30),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.30 : 0.60)),
                  boxShadow: [
                    BoxShadow(
                      color: ReemColors.accent.withValues(alpha: 0.30),
                      blurRadius: 16,
                      spreadRadius: -2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
            child: Row(
              children: [
                for (final spec in _specs)
                  Expanded(
                    child: spec.index == 2
                        ? _PublishButton(onTap: () => onTap(2))
                        : _NavItem(
                            spec: spec,
                            selected: currentIndex == spec.index,
                            badge: spec.index == 3 ? messagesBadge : 0,
                            activeColor: activeColor,
                            idleColor: idleColor,
                            onTap: () => onTap(spec.index),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: ReemNavController.hidden,
      builder: (context, hidden, child) {
        return IgnorePointer(
          ignoring: hidden,
          child: AnimatedSlide(
            offset: hidden ? const Offset(0, 1.6) : Offset.zero,
            duration: const Duration(milliseconds: 380),
            curve: hidden ? Curves.easeInCubic : Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: hidden ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: kReemNavBottomGap + bottomSafe),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.14),
                    blurRadius: 26,
                    spreadRadius: -2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_radius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: glass,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un onglet : l'icône « saute » avec un rebond élastique quand on le choisit.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.spec,
    required this.selected,
    required this.onTap,
    required this.activeColor,
    required this.idleColor,
    this.badge = 0,
  });

  final _NavSpec spec;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;
  final Color idleColor;
  final int badge;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with SingleTickerProviderStateMixin {
  late final AnimationController _pop;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    // value: 1 = animation terminée (rien ne bouge au démarrage)
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected && widget.selected) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    if (widget.selected) _pop.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? widget.activeColor : widget.idleColor;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.spec.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: _handleTap,
        child: AnimatedScale(
          scale: _down ? 0.82 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: SizedBox(
            height: kReemNavHeight,
            child: AnimatedBuilder(
              animation: _pop,
              builder: (context, child) {
                final linear = _pop.value.clamp(0.0, 1.0);
                final elastic = Curves.elasticOut.transform(linear);
                // L'icône part un peu plus bas et plus petite, puis bondit avec un rebond
                final scale = widget.selected ? 0.62 + 0.38 * elastic : 1.0;
                final dy = widget.selected ? (1 - elastic) * 14 : 0.0;

                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Onde qui s'élargit puis disparaît
                    if (widget.selected && linear < 1)
                      Opacity(
                        opacity: ((1 - linear) * 0.5).clamp(0.0, 1.0),
                        child: Container(
                          width: 22 + 40 * linear,
                          height: 22 + 40 * linear,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: widget.activeColor, width: 2),
                          ),
                        ),
                      ),
                    Transform.translate(
                      offset: Offset(0, dy),
                      child: Transform.scale(scale: scale, child: child),
                    ),
                  ],
                );
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      widget.selected ? widget.spec.activeIcon : widget.spec.icon,
                      key: ValueKey<bool>(widget.selected),
                      size: 27,
                      color: color,
                    ),
                  ),
                  if (widget.badge > 0)
                    Positioned(
                      right: -10,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                        decoration: BoxDecoration(
                          color: ReemColors.like,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.2),
                        ),
                        child: Text(
                          widget.badge > 99 ? '99+' : '${widget.badge}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton central « + » : le plus tourne et grossit un instant quand on le touche.
class _PublishButton extends StatefulWidget {
  const _PublishButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_PublishButton> createState() => _PublishButtonState();
}

class _PublishButtonState extends State<_PublishButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    _spin.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Publier une vidéo',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: _handleTap,
        child: AnimatedScale(
          scale: _down ? 0.86 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Center(
            child: AnimatedBuilder(
              animation: _spin,
              builder: (context, child) {
                final t = _spin.value;
                final angle = Curves.easeOutBack.transform(t) * math.pi / 2;
                final grow = 1 + 0.16 * math.sin(math.pi * t);
                return Transform.scale(
                  scale: grow,
                  child: Container(
                    width: 52,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: ReemColors.gradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: ReemColors.accent.withValues(alpha: 0.45),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Transform.rotate(angle: angle, child: child),
                  ),
                );
              },
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
            ),
          ),
        ),
      ),
    );
  }
}
