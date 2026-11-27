import 'package:flutter/material.dart';

import '../services/session_manager.dart';
import '../services/story_service.dart';
import '../theme/reem_theme.dart';
import '../utils/media_url.dart';

/// Rangée de stories en haut de la Communauté : « Ta story » puis les comptes suivis.
class StoryBar extends StatelessWidget {
  const StoryBar({
    super.key,
    required this.groups,
    required this.onOpen,
    required this.onAdd,
  });

  final List<StoryGroup> groups;
  final ValueChanged<int> onOpen; // index dans [groups]
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final myIndex = groups.indexWhere((group) => group.isMe);
    final others = <int>[
      for (var i = 0; i < groups.length; i++)
        if (!groups[i].isMe) i,
    ];

    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _MyStoryTile(
            group: myIndex >= 0 ? groups[myIndex] : null,
            onOpen: myIndex >= 0 ? () => onOpen(myIndex) : onAdd,
            onAdd: onAdd,
          ),
          for (final index in others)
            _StoryTile(group: groups[index], onTap: () => onOpen(index)),
        ],
      ),
    );
  }
}

Widget _avatar(BuildContext context, String? photo, String name, double radius) {
  final url = absoluteMediaUrl(photo);
  return CircleAvatar(
    radius: radius,
    backgroundColor: context.reem.surfaceHigh,
    backgroundImage: url != null ? NetworkImage(url) : null,
    child: url == null
        ? Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w700, fontSize: radius * 0.8),
          )
        : null,
  );
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({required this.group, required this.onTap});

  final StoryGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unseen = group.hasUnseen;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: unseen ? ReemColors.gradient : null,
                border: unseen ? null : Border.all(color: context.reem.textMuted, width: 1.5),
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, color: context.reem.background),
                child: _avatar(context, group.photo, group.name, 28),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: unseen ? context.reem.text : context.reem.textMuted,
                fontSize: 12,
                fontWeight: unseen ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyStoryTile extends StatelessWidget {
  const _MyStoryTile({required this.group, required this.onOpen, required this.onAdd});

  final StoryGroup? group;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final user = SessionManager().currentUser;
    final name = '${user?['name'] ?? ''}';
    final hasStories = group != null;
    final unseen = group?.hasUnseen ?? false;

    return SizedBox(
      width: 76,
      child: Column(
        children: [
          const SizedBox(height: 6),
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: onOpen,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: hasStories && unseen ? ReemColors.gradient : null,
                    border: hasStories && !unseen ? Border.all(color: context.reem.textMuted, width: 1.5) : null,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: context.reem.background),
                    child: _avatar(context, user?['profile_photo_path']?.toString(), name, 28),
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: ReemColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.reem.background, width: 2),
                    ),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Ta story',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.reem.text, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
