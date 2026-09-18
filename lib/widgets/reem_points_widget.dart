import 'package:flutter/material.dart';
import 'package:reem_front/services/point_service.dart';

class ReemPointsWidget extends StatelessWidget {
  const ReemPointsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: PointService.getBalance(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2));
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!;
        final int points = data['points'] ?? 0;
        final String level = data['level'] ?? 'Créateur Débutant';

        return Column(
          children: [
            _buildLevelBadge(level),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.stars, color: Colors.amber, size: 20),
                const SizedBox(width: 4),
                Text(
                  '$points Points REEM',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildLevelBadge(String level) {
    Color badgeColor;
    IconData badgeIcon;

    switch (level) {
      case 'Star REEM':
        badgeColor = Colors.cyanAccent;
        badgeIcon = Icons.diamond;
        break;
      case 'Créateur Elite':
        badgeColor = Colors.amber;
        badgeIcon = Icons.emoji_events;
        break;
      case 'Créateur Confirmé':
        badgeColor = Colors.grey[300]!;
        badgeIcon = Icons.verified;
        break;
      default:
        badgeColor = Colors.orangeAccent;
        badgeIcon = Icons.auto_awesome;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, color: badgeColor, size: 16),
          const SizedBox(width: 6),
          Text(
            level.toUpperCase(),
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
