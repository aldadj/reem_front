import 'package:flutter/material.dart';

import 'reem_theme.dart';

/// Logo Reem : pastille dégradée + nom en dégradé.
class ReemLogo extends StatelessWidget {
  const ReemLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: ReemColors.gradient,
            borderRadius: BorderRadius.circular(size * 0.3),
            boxShadow: [
              BoxShadow(
                color: ReemColors.accent.withValues(alpha: 0.4),
                blurRadius: 24,
              ),
            ],
          ),
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: size * 0.64),
        ),
        const SizedBox(height: 14),
        ShaderMask(
          shaderCallback: (rect) => ReemColors.gradient.createShader(rect),
          child: Text(
            'REEM',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.58,
              fontWeight: FontWeight.w900,
              letterSpacing: 5,
            ),
          ),
        ),
      ],
    );
  }
}
