import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_texts.dart';
import '../services/account_deletion_service.dart';
import 'login_page.dart';

/// Fluxo de exclusão definitiva da conta (confirmação forte + reauth + CF).
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _danger = Color(0xFFB91C1C);

  final _confirmCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _understood = false;
  bool _loading = false;
  String? _errorKey;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final confirmOk = AccountDeletionService.matchesConfirmation(
      _confirmCtrl.text,
      Localizations.localeOf(context).languageCode,
    );
    if (!_understood || !confirmOk || _loading) return false;
    if (AccountDeletionService.usesPassword &&
        _passwordCtrl.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  Future<void> _openManageSubscription() async {
    final uri = Uri.parse(AccountDeletionService.manageSubscriptionsUrl());
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _submit() async {
    final t = AppTexts.current;
    if (!_canSubmit) return;

    setState(() {
      _loading = true;
      _errorKey = null;
    });

    try {
      // Reautenticação antes da Function
      await AccountDeletionService.reauthenticate(
        password: AccountDeletionService.usesPassword
            ? _passwordCtrl.text.trim()
            : null,
      );

      await AccountDeletionService.deleteMyAccount();
      await AccountDeletionService.clearLocalSession();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.get('delete_account_success')),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // Tentar reauth e instruir o usuário
        setState(() {
          _errorKey = 'delete_account_reauth_required';
          _loading = false;
        });
        return;
      }
      setState(() {
        _errorKey = AccountDeletionService.errorKey(e);
        _loading = false;
      });
    } catch (e) {
      // Se a Function apagou o Auth, o cliente pode falhar no signOut — tratar sucesso parcial
      final stillSignedIn = FirebaseAuth.instance.currentUser != null;
      if (!stillSignedIn) {
        await AccountDeletionService.clearLocalSession();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.get('delete_account_success')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
        return;
      }

      setState(() {
        _errorKey = AccountDeletionService.errorKey(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final needsPassword = AccountDeletionService.usesPassword;
    final confirmHintWord = AccountDeletionService.expectedConfirmationWord(
      Localizations.localeOf(context).languageCode,
    );

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _text,
        elevation: 0,
        title: Text(
          t.get('delete_account_title'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.get('delete_account_permanent'),
                  style: const TextStyle(
                    color: _danger,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.get('delete_account_warning_body'),
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.get('delete_account_data_note'),
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t.get('delete_account_subscription_warning'),
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _openManageSubscription,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(
                    t.get('delete_account_manage_subscription'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _text,
                    side: const BorderSide(color: _border),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            value: _understood,
            onChanged: _loading
                ? null
                : (v) => setState(() => _understood = v == true),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(
              t.get('delete_account_understand_checkbox'),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: _text,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.get('delete_account_type_confirm').replaceAll(
                  '{word}',
                  confirmHintWord,
                ),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: _text,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmCtrl,
            enabled: !_loading,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
            ],
            decoration: InputDecoration(
              hintText: confirmHintWord,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (needsPassword) ...[
            const SizedBox(height: 14),
            Text(
              t.get('delete_account_password_label'),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: _text,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordCtrl,
              enabled: !_loading,
              obscureText: true,
              decoration: InputDecoration(
                hintText: t.get('delete_account_password_hint'),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              AccountDeletionService.usesGoogle
                  ? t.get('delete_account_reauth_google')
                  : AccountDeletionService.usesFacebook
                      ? t.get('delete_account_reauth_facebook')
                      : t.get('delete_account_reauth_required'),
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (_errorKey != null) ...[
            const SizedBox(height: 12),
            Text(
              t.get(_errorKey!),
              style: const TextStyle(
                color: _danger,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _danger,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFFECACA),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      t.get('delete_account_confirm_button'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t.get('delete_account_logout_is_different'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
