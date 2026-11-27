import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/video.dart' as app_models;
import '../screens/login_screen.dart';
import '../services/inbox_service.dart';
import '../services/session_manager.dart';
import '../theme/reem_theme.dart';
import '../utils/media_url.dart';

/// Lien partagé pour une vidéo.
/// Une seule adresse à changer le jour où les liens REEM (https://…/v/{id}) existeront.
String videoShareLink(app_models.Video video) => video.videoUrl;

/// Menu qui remonte du bas quand on maintient le doigt sur une vidéo.
Future<void> showVideoActionsSheet(
  BuildContext context, {
  required app_models.Video video,
  required double playbackRate,
  required ValueChanged<double> onRate,
  required bool autoNext,
  required ValueChanged<bool> onAutoNext,
  required bool Function() isFavorited,
  required Future<void> Function() onToggleFavorite,
  required double volume,
  required ValueChanged<double> onVolume,
  VoidCallback? onDownload,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54, // fond légèrement assombri derrière la feuille
    builder: (_) => DraggableScrollableSheet(
      // S'ouvre sur la moitié de l'écran ; on tire vers le haut pour voir la suite
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.5, 0.92],
      expand: false,
      builder: (context, scrollController) => _VideoActionsSheet(
        scrollController: scrollController,
        video: video,
        playbackRate: playbackRate,
        onRate: onRate,
        autoNext: autoNext,
        onAutoNext: onAutoNext,
        isFavorited: isFavorited,
        onToggleFavorite: onToggleFavorite,
        volume: volume,
        onVolume: onVolume,
        onDownload: onDownload,
      ),
    ),
  );
}

enum _SendState { idle, sending, sent, failed }

class _VideoActionsSheet extends StatefulWidget {
  const _VideoActionsSheet({
    required this.scrollController,
    required this.video,
    required this.playbackRate,
    required this.onRate,
    required this.autoNext,
    required this.onAutoNext,
    required this.isFavorited,
    required this.onToggleFavorite,
    required this.volume,
    required this.onVolume,
    this.onDownload,
  });

  final ScrollController scrollController;
  final app_models.Video video;
  final double playbackRate;
  final ValueChanged<double> onRate;
  final bool autoNext;
  final ValueChanged<bool> onAutoNext;
  final bool Function() isFavorited;
  final Future<void> Function() onToggleFavorite;
  final double volume;
  final ValueChanged<double> onVolume;
  final VoidCallback? onDownload;

  @override
  State<_VideoActionsSheet> createState() => _VideoActionsSheetState();
}

class _VideoActionsSheetState extends State<_VideoActionsSheet> {
  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const int _maxVisibleFriends = 8;

  final InboxService _inbox = InboxService();
  final SessionManager _session = SessionManager();

  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = false;
  final Map<int, _SendState> _sendStates = {};

  late double _rate = widget.playbackRate;
  late bool _autoNext = widget.autoNext;
  late bool _favorited = widget.isFavorited();
  late double _volume = widget.volume;

  bool _copied = false;
  String? _hint;

  bool get _signedIn => _session.isAuthenticated;

  bool get _isOwnVideo {
    final me = _session.currentUser?['id'];
    return me != null && '$me' == '${widget.video.authorId}';
  }

  @override
  void initState() {
    super.initState();
    if (_signedIn) _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() => _loadingFriends = true);
    final list = await _inbox.fetchFriends();
    if (!mounted) return;
    setState(() {
      _friends = list.whereType<Map>().map((f) => Map<String, dynamic>.from(f)).toList();
      _loadingFriends = false;
    });
  }

  String get _link => videoShareLink(widget.video);

  String get _shareText => '${widget.video.title}\n$_link';

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _sendTo(Map<String, dynamic> friend, [VoidCallback? refresh]) async {
    final id = int.tryParse('${friend['id']}');
    if (id == null || _sendStates[id] == _SendState.sending) return;

    void change(_SendState state) {
      if (!mounted) return;
      setState(() => _sendStates[id] = state);
      refresh?.call();
    }

    change(_SendState.sending);
    final ok = await _inbox.sendVideoToUser(id, widget.video, _link);
    if (ok) HapticFeedback.lightImpact();
    change(ok ? _SendState.sent : _SendState.failed);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _link));
    if (!mounted) return;
    setState(() {
      _copied = true;
      _hint = null;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _nativeShare() async {
    await SharePlus.instance.share(ShareParams(text: _shareText, subject: widget.video.title));
  }

  Future<void> _facebook() async {
    final url = Uri.parse('https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_link)}');
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    await _nativeShare();
  }

  // Instagram n'accepte pas de lien venant d'une autre application : on copie le lien
  // et on ouvre Instagram pour le coller dans un message ou une story.
  Future<void> _instagram() async {
    await Clipboard.setData(ClipboardData(text: _link));
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse('instagram://app'), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!mounted) return;
    if (opened) {
      setState(() => _hint = 'Lien copié : colle-le dans Instagram.');
    } else {
      await _nativeShare();
    }
  }

  void _goToLogin() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _toggleFavorite() async {
    if (!_signedIn) {
      _goToLogin();
      return;
    }
    await widget.onToggleFavorite();
    if (mounted) setState(() => _favorited = widget.isFavorited());
  }

  Future<void> _report() async {
    if (!_signedIn) {
      _goToLogin();
      return;
    }

    final reason = await showModalBottomSheet<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pourquoi signales-tu cette vidéo ?',
                  style: TextStyle(color: sheetContext.reem.text, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            for (final option in const [
              ('spam', 'Spam ou arnaque'),
              ('inappropriate', 'Contenu inapproprié ou sexuel'),
              ('violence', 'Violence ou danger'),
              ('hate', 'Haine ou harcèlement'),
              ('misinformation', 'Fausse information'),
              ('other', 'Autre raison'),
            ])
              ListTile(
                title: Text(option.$2, style: TextStyle(color: sheetContext.reem.text)),
                trailing: Icon(Icons.chevron_right_rounded, color: sheetContext.reem.textMuted),
                onTap: () => Navigator.pop(sheetContext, option.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;

    final error = await _inbox.reportVideo(widget.video.id, reason);
    if (!mounted) return;
    setState(() => _hint = error ?? 'Merci, ton signalement a été envoyé.');
  }

  void _openAllFriends() {
    var query = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setInner) {
          final shown = _friends.where((f) {
            final text = '${f['name']} ${f['username'] ?? ''}'.toLowerCase();
            return text.contains(query.toLowerCase());
          }).toList();

          return SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    onChanged: (value) => setInner(() => query = value),
                    decoration: const InputDecoration(
                      hintText: 'Rechercher un ami',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Text('Aucun ami trouvé', style: TextStyle(color: context.reem.textMuted)),
                        )
                      : ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (context, index) {
                            final friend = shown[index];
                            final id = int.tryParse('${friend['id']}') ?? -1;
                            final state = _sendStates[id] ?? _SendState.idle;
                            return ListTile(
                              leading: _avatar(friend, 22),
                              title: Text(
                                '${friend['name']}',
                                style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w600),
                              ),
                              subtitle: (friend['username'] ?? '').toString().isEmpty
                                  ? null
                                  : Text('@${friend['username']}', style: TextStyle(color: context.reem.textMuted)),
                              trailing: SizedBox(
                                width: 92,
                                child: ElevatedButton(
                                  onPressed: state == _SendState.sending || state == _SendState.sent
                                      ? null
                                      : () => _sendTo(friend, () => setInner(() {})),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  child: state == _SendState.sending
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text(
                                          state == _SendState.sent
                                              ? 'Envoyé'
                                              : state == _SendState.failed
                                                  ? 'Réessayer'
                                                  : 'Envoyer',
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BRIQUES D'INTERFACE
  // ---------------------------------------------------------------------------

  Widget _avatar(Map<String, dynamic> friend, double radius) {
    final photo = absoluteMediaUrl(friend['profile_photo_path']?.toString());
    final name = '${friend['name'] ?? '?'}';
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.reem.surfaceHigh,
      backgroundImage: photo != null ? NetworkImage(photo) : null,
      child: photo == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w700, fontSize: radius * 0.8),
            )
          : null,
    );
  }

  Widget _title(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.reem.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _friendTile(Map<String, dynamic> friend) {
    final id = int.tryParse('${friend['id']}') ?? -1;
    final state = _sendStates[id] ?? _SendState.idle;

    return GestureDetector(
      onTap: () => _sendTo(friend),
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                _avatar(friend, 28),
                if (state != _SendState.idle)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state == _SendState.failed
                            ? ReemColors.like.withValues(alpha: 0.75)
                            : Colors.black54,
                      ),
                      child: Center(
                        child: state == _SendState.sending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : Icon(
                                state == _SendState.sent ? Icons.check_rounded : Icons.refresh_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${friend['name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.reem.text, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _friendsSection() {
    if (!_signedIn) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          'Connecte-toi pour envoyer cette vidéo à tes amis dans REEM.',
          style: TextStyle(color: context.reem.textSecondary),
        ),
      );
    }
    if (_loadingFriends) {
      return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    if (_friends.isEmpty) {
      return Text(
        'Tes amis sont les personnes que tu suis et qui te suivent aussi. Tu n’en as pas encore.',
        style: TextStyle(color: context.reem.textSecondary, height: 1.35),
      );
    }

    final visible = _friends.take(_maxVisibleFriends).toList();
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final friend in visible) ...[
            _friendTile(friend),
            const SizedBox(width: 6),
          ],
          if (_friends.length > _maxVisibleFriends)
            GestureDetector(
              onTap: _openAllFriends,
              child: SizedBox(
                width: 68,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: context.reem.surfaceHigh,
                      child: Icon(Icons.apps_rounded, color: context.reem.text),
                    ),
                    const SizedBox(height: 6),
                    Text('Voir tous', style: TextStyle(color: context.reem.text, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _roundAction({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    Gradient? gradient,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gradient == null ? (color ?? context.reem.surfaceHigh) : null,
                gradient: gradient,
              ),
              child: Center(child: icon),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.reem.text, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareSection() {
    return Wrap(
      spacing: 4,
      runSpacing: 12,
      children: [
        _roundAction(
          icon: Icon(_copied ? Icons.check_rounded : Icons.link_rounded, color: context.reem.text, size: 26),
          label: _copied ? 'Copié !' : 'Copier le lien',
          onTap: _copyLink,
        ),
        _roundAction(
          icon: const Icon(Icons.facebook_rounded, color: Colors.white, size: 28),
          label: 'Facebook',
          color: const Color(0xFF1877F2),
          onTap: _facebook,
        ),
        _roundAction(
          icon: const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 26),
          label: 'Instagram',
          gradient: const LinearGradient(
            colors: [Color(0xFF8A3AB9), Color(0xFFE95950), Color(0xFFFCAF45)],
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ),
          onTap: _instagram,
        ),
        _roundAction(
          icon: Icon(Icons.add_rounded, color: context.reem.text, size: 28),
          label: 'Plus',
          onTap: _nativeShare,
        ),
      ],
    );
  }

  Widget _speedSection() {
    String label(double rate) {
      if (rate == 1.0) return '1x';
      if (rate == 2.0) return '2x';
      return '${rate.toString().replaceAll('.', ',')}x';
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final rate in _rates)
          ChoiceChip(
            label: Text(label(rate)),
            selected: _rate == rate,
            showCheckmark: false,
            selectedColor: ReemColors.primary,
            backgroundColor: context.reem.surfaceHigh,
            side: BorderSide.none,
            labelStyle: TextStyle(
              color: _rate == rate ? Colors.white : context.reem.text,
              fontWeight: FontWeight.w700,
            ),
            onSelected: (_) {
              setState(() => _rate = rate);
              widget.onRate(rate); // appliquée tout de suite à la vidéo
            },
          ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required VoidCallback? onTap,
    Color? color,
    Widget? trailing,
  }) {
    final tint = color ?? context.reem.text;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: tint),
      title: Text(title, style: TextStyle(color: tint, fontWeight: FontWeight.w600)),
      trailing: trailing,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.reem.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 2),
                decoration: BoxDecoration(
                  color: context.reem.textMuted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _title('Envoyer à un ami'),
            _friendsSection(),
            _title('Partager'),
            _shareSection(),
            if (_hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_hint!, style: const TextStyle(color: ReemColors.primary, fontWeight: FontWeight.w600)),
              ),
            _title('Vitesse de lecture'),
            _speedSection(),
            _title('Lecture'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Défilement automatique', style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Passe à la vidéo suivante quand celle-ci se termine',
                style: TextStyle(color: context.reem.textMuted, fontSize: 12),
              ),
              value: _autoNext,
              onChanged: (value) {
                setState(() => _autoNext = value);
                widget.onAutoNext(value);
              },
            ),
            Row(
              children: [
                Icon(_volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: context.reem.textSecondary),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 100,
                    value: _volume,
                    onChanged: (value) {
                      setState(() => _volume = value);
                      widget.onVolume(value);
                    },
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text('${_volume.round()}%', style: TextStyle(color: context.reem.textMuted, fontSize: 12)),
                ),
              ],
            ),
            _title('Actions'),
            _actionTile(
              icon: _favorited ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              title: _favorited ? 'Retirer des favoris' : 'Enregistrer dans mes favoris',
              color: _favorited ? ReemColors.gold : null,
              onTap: _toggleFavorite,
            ),
            if (widget.onDownload != null)
              _actionTile(
                icon: Icons.download_outlined,
                title: 'Télécharger la vidéo',
                onTap: () {
                  Navigator.pop(context);
                  widget.onDownload!();
                },
              ),
            if (!_isOwnVideo)
              _actionTile(
                icon: Icons.flag_outlined,
                title: 'Signaler la vidéo',
                color: ReemColors.like,
                onTap: _report,
              ),
          ],
        ),
      ),
    );
  }
}
