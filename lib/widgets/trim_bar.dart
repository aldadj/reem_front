import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/reem_theme.dart';

/// Barre de découpe : deux poignées, durée choisie en surbrillance, tête de lecture.
class TrimBar extends StatelessWidget {
  const TrimBar({
    required this.totalMs,
    required this.start,
    required this.end,
    required this.position,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double totalMs;
  final double start;
  final double end;
  final ValueListenable<Duration> position;
  final void Function(double start, double end) onChanged;
  final void Function(bool movedStart) onChangeEnd;

  static const double _handle = 16; // largeur visible d'une poignée
  static const double _pad = 8; // zone de toucher en plus, de chaque côté
  static const double _minMs = 1000;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = constraints.maxWidth - 2 * (_pad + _handle);
        double toX(double ms) => _pad + _handle + (totalMs <= 0 ? 0 : ms / totalMs) * usable;
        final left = toX(start);
        final right = toX(end);
        final minGap = totalMs < _minMs ? totalMs : _minMs;

        Widget grip() => Container(
              width: _handle,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
              alignment: Alignment.center,
              child: Container(width: 2.5, height: 18, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2))),
            );

        return SizedBox(
          height: 58,
          child: Stack(
            children: [
              // piste
              Positioned(
                left: _pad + _handle,
                right: _pad + _handle,
                top: 9,
                bottom: 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
                ),
              ),
              // partie gardée
              Positioned(
                left: left,
                width: (right - left).clamp(0.0, double.infinity).toDouble(),
                top: 3,
                bottom: 3,
                child: DecoratedBox(
                  decoration: const BoxDecoration(gradient: ReemColors.gradient),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: ColoredBox(
                      color: const Color(0xCC0B0F1E),
                      child: ValueListenableBuilder<Duration>(
                        valueListenable: position,
                        builder: (context, pos, _) {
                          final span = end - start;
                          final double fraction =
                              span <= 0 ? 0.0 : ((pos.inMilliseconds - start) / span).clamp(0.0, 1.0).toDouble();
                          return Align(
                            alignment: Alignment(fraction * 2 - 1, 0),
                            child: Container(width: 3, color: Colors.white),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // poignée gauche
              Positioned(
                left: left - _handle - _pad,
                top: 0,
                bottom: 0,
                width: _handle + 2 * _pad,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) {
                    final next = (start + d.delta.dx / usable * totalMs).clamp(0.0, end - minGap).toDouble();
                    onChanged(next, end);
                  },
                  onHorizontalDragEnd: (_) => onChangeEnd(true),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: _pad), child: grip()),
                ),
              ),
              // poignée droite
              Positioned(
                left: right - _pad,
                top: 0,
                bottom: 0,
                width: _handle + 2 * _pad,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) {
                    final next = (end + d.delta.dx / usable * totalMs).clamp(start + minGap, totalMs).toDouble();
                    onChanged(start, next);
                  },
                  onHorizontalDragEnd: (_) => onChangeEnd(false),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: _pad), child: grip()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
