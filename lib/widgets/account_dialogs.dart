import 'package:flutter/material.dart';

import '../screens/feed_screen.dart';
import '../services/account_service.dart';
import '../services/session_manager.dart';
import '../theme/reem_theme.dart';

bool get _isGoogleAccount => SessionManager().currentUser?['signed_up_with_google'] == true;

/// Fenêtre « Changer le mot de passe ».
Future<void> showChangePasswordDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ChangePasswordDialog(),
  );
}

/// Fenêtre « Supprimer mon compte ». À la fin, retourne sur le fil en invité.
Future<void> showDeleteAccountDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _DeleteAccountDialog(),
  );
}

InputDecoration _decoration(String hint, {Widget? suffix}) => InputDecoration(
      hintText: hint,
      suffixIcon: suffix,
    );

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isGoogleAccount && _current.text.isEmpty) {
      setState(() => _error = 'Saisis ton mot de passe actuel.');
      return;
    }
    if (_new.text.length < 8) {
      setState(() => _error = 'Le nouveau mot de passe doit contenir au moins 8 caractères.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AccountService().changePassword(
        currentPassword: _isGoogleAccount ? null : _current.text,
        newPassword: _new.text,
        confirmation: _confirm.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe modifié.')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eye = IconButton(
      icon: Icon(_hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: context.reem.textMuted),
      onPressed: () => setState(() => _hidden = !_hidden),
    );

    return AlertDialog(
      title: const Text('Changer le mot de passe'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isGoogleAccount) ...[
              TextField(
                controller: _current,
                obscureText: _hidden,
                style: TextStyle(color: context.reem.text),
                decoration: _decoration('Mot de passe actuel', suffix: eye),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _new,
              obscureText: _hidden,
              style: TextStyle(color: context.reem.text),
              decoration: _decoration('Nouveau mot de passe (8 caractères min.)', suffix: _isGoogleAccount ? eye : null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: _hidden,
              style: TextStyle(color: context.reem.text),
              decoration: _decoration('Confirmer le nouveau mot de passe'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: ReemColors.like, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text('Annuler', style: TextStyle(color: context.reem.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Modifier'),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_confirmation.text.trim() != 'SUPPRIMER') {
      setState(() => _error = 'Tape SUPPRIMER (en majuscules) pour confirmer.');
      return;
    }
    if (!_isGoogleAccount && _password.text.isEmpty) {
      setState(() => _error = 'Saisis ton mot de passe.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AccountService().deleteAccount(
        password: _isGoogleAccount ? null : _password.text,
        confirmation: _confirmation.text.trim(),
      );
      SessionManager().clearSession();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const FeedScreen()),
        (route) => false,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Ton compte a été supprimé.')));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Supprimer mon compte'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cette action est définitive. Tes vidéos, commentaires, j’aime, abonnés et messages seront supprimés.',
              style: TextStyle(color: context.reem.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (!_isGoogleAccount) ...[
              TextField(
                controller: _password,
                obscureText: true,
                style: TextStyle(color: context.reem.text),
                decoration: _decoration('Ton mot de passe'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _confirmation,
              style: TextStyle(color: context.reem.text),
              decoration: _decoration('Tape SUPPRIMER pour confirmer'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: ReemColors.like, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text('Annuler', style: TextStyle(color: context.reem.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: ReemColors.like),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Supprimer définitivement'),
        ),
      ],
    );
  }
}
