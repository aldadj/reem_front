import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/session_manager.dart';
import '../theme/reem_theme.dart';
import '../utils/media_url.dart';
import '../widgets/account_dialogs.dart';

/// Modification du profil : photo, nom, @nom d'utilisateur, bio, site web.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.initialName,
    required this.initialUsername,
    required this.initialBio,
    required this.initialWebsite,
    this.initialPhotoUrl,
    required this.onProfileUpdated,
  });

  final String initialName;
  final String initialUsername;
  final String initialBio;
  final String initialWebsite;
  final String? initialPhotoUrl;
  final void Function(Map<String, dynamic>) onProfileUpdated;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final AccountService _account = AccountService();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _bio = TextEditingController();
  final TextEditingController _website = TextEditingController();

  Uint8List? _newPhotoBytes;
  String? _newPhotoName;
  String? _photoUrl;
  bool _saving = false;
  bool _removingPhoto = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.initialName;
    _username.text = widget.initialUsername;
    _bio.text = widget.initialBio;
    _website.text = widget.initialWebsite;
    _photoUrl = widget.initialPhotoUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    _website.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      _toast('Impossible de lire cette image.');
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      _toast('La photo est trop lourde (5 Mo maximum).');
      return;
    }
    setState(() {
      _newPhotoBytes = file.bytes;
      _newPhotoName = file.name;
    });
  }

  Future<void> _removePhoto() async {
    if (_newPhotoBytes != null) {
      setState(() {
        _newPhotoBytes = null;
        _newPhotoName = null;
      });
      return;
    }
    setState(() => _removingPhoto = true);
    try {
      final user = await _account.deletePhoto();
      if (!mounted) return;
      setState(() => _photoUrl = null);
      widget.onProfileUpdated(user);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _removingPhoto = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _toast('Le nom ne peut pas être vide.');
      return;
    }

    setState(() => _saving = true);
    try {
      Map<String, dynamic> user = SessionManager().currentUser ?? {};
      if (_newPhotoBytes != null) {
        user = await _account.uploadPhoto(_newPhotoBytes!, _newPhotoName ?? 'photo.jpg');
      }
      user = await _account.updateInfo(
        name: _name.text.trim(),
        username: _username.text.trim().replaceFirst('@', ''),
        bio: _bio.text.trim(),
        website: _website.text.trim(),
      );

      if (!mounted) return;
      widget.onProfileUpdated(user);
      Navigator.of(context).pop();
      _toast('Profil mis à jour.');
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 18),
        child: Text(
          text,
          style: const TextStyle(color: ReemColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final shownPhoto = absoluteMediaUrl(_photoUrl);
    final hasPhoto = _newPhotoBytes != null || shownPhoto != null;
    final email = SessionManager().currentUser?['email']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier le profil'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: ReemColors.gradient),
                    child: CircleAvatar(
                      radius: 56,
                      backgroundColor: ReemColors.surfaceHigh,
                      backgroundImage: _newPhotoBytes != null
                          ? MemoryImage(_newPhotoBytes!)
                          : (shownPhoto != null ? NetworkImage(shownPhoto) as ImageProvider : null),
                      child: !hasPhoto ? const Icon(Icons.person_rounded, color: Colors.white70, size: 54) : null,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ReemColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: ReemColors.background, width: 3),
                      ),
                      child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(onPressed: _pickPhoto, child: const Text('Changer la photo')),
              if (hasPhoto)
                TextButton(
                  onPressed: _removingPhoto ? null : _removePhoto,
                  child: const Text('Supprimer', style: TextStyle(color: ReemColors.like)),
                ),
            ],
          ),
          _label('Nom'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Ton nom'),
          ),
          _label('Nom d’utilisateur'),
          TextField(
            controller: _username,
            autocorrect: false,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'ex. awa_ouedraogo',
              prefixText: '@',
              helperText: 'Lettres, chiffres, points et tirets bas (3 à 30 caractères)',
              helperStyle: TextStyle(color: ReemColors.textMuted),
            ),
          ),
          _label('Bio'),
          TextField(
            controller: _bio,
            maxLines: 4,
            maxLength: 300,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Parle un peu de toi…'),
          ),
          _label('Site web'),
          TextField(
            controller: _website,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'https://…'),
          ),
          _label('E-mail'),
          TextField(
            controller: TextEditingController(text: email),
            enabled: false,
            style: const TextStyle(color: ReemColors.textMuted),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline_rounded, color: ReemColors.textMuted, size: 20)),
          ),
          const SizedBox(height: 30),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_reset_rounded, color: Colors.white),
            title: const Text('Changer le mot de passe', style: TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right_rounded, color: ReemColors.textMuted),
            onTap: () => showChangePasswordDialog(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_forever_rounded, color: ReemColors.like),
            title: const Text('Supprimer mon compte', style: TextStyle(color: ReemColors.like)),
            trailing: const Icon(Icons.chevron_right_rounded, color: ReemColors.textMuted),
            onTap: () => showDeleteAccountDialog(context),
          ),
        ],
      ),
    );
  }
}
