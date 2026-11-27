import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/reem_theme.dart';

/// Extrait un message lisible de la réponse de l'API quand la publication échoue
/// (erreur de validation Laravel, message simple, ou texte brut).
String parsePublishError(String body, {String fallback = 'Échec de la publication.'}) {
  if (body.trim().isEmpty) return fallback;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final errors = decoded['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        if (first != null) return first.toString();
      }
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
  } catch (_) {
    // pas du JSON : on retombe sur le message par défaut
  }
  return fallback;
}

/// Titre court tiré de la description (première ligne, 100 caractères maximum).
String titleFromCaption(String caption) {
  final firstLine = caption.trim().split('\n').first.trim();
  return firstLine.length > 100 ? firstLine.substring(0, 100).trim() : firstLine;
}

/// Formulaire de publication, sur le modèle de TikTok :
///  - carte « Détails » : une seule description (hashtags et mentions en un geste) + aperçu à droite ;
///  - carte « Paramètres » : qui peut voir la vidéo.
/// Utilisé par l'écran de publication mobile et par celui du web.
class PublishForm extends StatelessWidget {
  const PublishForm({
    super.key,
    required this.captionController,
    required this.visibility,
    required this.onVisibilityChanged,
    this.cover,
    this.enabled = true,
  });

  final TextEditingController captionController;
  final String visibility; // public | friends | private
  final ValueChanged<String> onVisibilityChanged;

  /// Petit aperçu affiché à droite de la description (comme la couverture TikTok).
  final Widget? cover;
  final bool enabled;

  static const int captionMaxLength = 2000;

  static const List<(String, IconData, String, String)> _options = [
    ('public', Icons.public_rounded, 'Tout le monde', 'Tout le monde peut voir cette vidéo.'),
    ('friends', Icons.group_rounded, 'Amis', 'Seulement les personnes que tu suis et qui te suivent.'),
    ('private', Icons.lock_rounded, 'Moi uniquement', 'Toi seul(e) peux voir cette vidéo.'),
  ];

  (String, IconData, String, String) get _selected =>
      _options.firstWhere((o) => o.$1 == visibility, orElse: () => _options.first);

  /// Insère « # » ou « @ » à l'endroit du curseur (avec un espace avant si besoin).
  void _insertSymbol(String symbol) {
    final value = captionController.value;
    final text = value.text;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final needsSpace = start > 0 && !RegExp(r'\s').hasMatch(text[start - 1]);
    final insert = '${needsSpace ? ' ' : ''}$symbol';
    final next = text.replaceRange(start, end, insert);
    if (next.length > captionMaxLength) return;
    captionController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: ReemColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ReemColors.border),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _toolChip(IconData icon, String label, VoidCallback? onTap) {
    return Material(
      color: ReemColors.surfaceHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: ReemColors.textSecondary),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickVisibility(BuildContext context) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          decoration: BoxDecoration(
            color: ReemColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ReemColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Qui peut voir cette vidéo ?',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              for (final option in _options)
                ListTile(
                  leading: Icon(option.$2, color: option.$1 == visibility ? ReemColors.primary : Colors.white70),
                  title: Text(option.$3, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  subtitle: Text(option.$4, style: const TextStyle(color: ReemColors.textMuted, fontSize: 12.5)),
                  trailing: option.$1 == visibility
                      ? const Icon(Icons.check_circle_rounded, color: ReemColors.primary)
                      : const Icon(Icons.circle_outlined, color: Colors.white24),
                  onTap: () => Navigator.pop(sheetContext, option.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (value != null) onVisibilityChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionTitle('Détails'),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: captionController,
                      enabled: enabled,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: captionMaxLength,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
                      decoration: const InputDecoration(
                        hintText: 'Décris ta vidéo : ajoute des #hashtags ou mentionne des @amis…',
                        hintStyle: TextStyle(color: ReemColors.textMuted, fontSize: 15),
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  if (cover != null) ...[
                    const SizedBox(width: 12),
                    cover!,
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _toolChip(Icons.tag_rounded, 'Hashtags', enabled ? () => _insertSymbol('#') : null),
                  const SizedBox(width: 8),
                  _toolChip(Icons.alternate_email_rounded, 'Mention', enabled ? () => _insertSymbol('@') : null),
                  const Spacer(),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: captionController,
                    builder: (_, value, __) => Text(
                      '${value.text.length}/$captionMaxLength',
                      style: const TextStyle(color: ReemColors.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _sectionTitle('Paramètres'),
        _card(
          padding: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled ? () => _pickVisibility(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Icon(selected.$2, color: ReemColors.primary, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Qui peut voir cette vidéo',
                      style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(selected.$3, style: const TextStyle(color: ReemColors.textSecondary, fontSize: 13.5)),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, color: ReemColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
