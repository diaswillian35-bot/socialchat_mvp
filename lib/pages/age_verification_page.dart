import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/age_verification.dart';
import '../services/age_verification_service.dart';
import 'privacy_page.dart';
import 'splash_page.dart';
import 'terms_page.dart';

class AgeVerificationPage extends StatefulWidget {
  const AgeVerificationPage({super.key});

  @override
  State<AgeVerificationPage> createState() => _AgeVerificationPageState();
}

class _AgeVerificationPageState extends State<AgeVerificationPage> {
  DateTime? _birthDate;
  bool _accepted = false;
  bool _saving = false;
  String? _errorKey;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: AgeVerification.latestEligibleBirthDate(now),
      firstDate: AgeVerification.earliestAllowedBirthDate(now),
      lastDate: now,
      helpText: AppTexts.current.get('age_birth_date'),
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDate = picked;
        _errorKey = null;
      });
    }
  }

  Future<void> _confirm() async {
    final birth = _birthDate;
    final now = DateTime.now();
    if (birth == null) return setState(() => _errorKey = 'age_date_required');
    if (!AgeVerification.isReasonable(birth, now)) {
      return setState(() => _errorKey = 'age_date_invalid');
    }
    if (!AgeVerification.isAdult(birth, now)) {
      return setState(() => _errorKey = 'age_underage_blocked');
    }
    if (!_accepted) return setState(() => _errorKey = 'age_terms_required');

    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      await AgeVerificationService.confirm(dateOfBirth: birth);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SplashPage()),
        (_) => false,
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _errorKey = e.code == 'permission-denied'
          ? 'age_underage_blocked'
          : 'age_confirmation_error');
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'age_confirmation_error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final formatted = _birthDate == null
        ? t.get('age_select_date')
        : MaterialLocalizations.of(context).formatMediumDate(_birthDate!);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(t.get('age_verification_title')),
          actions: [
            IconButton(
              tooltip: t.get('logout'),
              onPressed: _saving ? null : () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.verified_user_outlined,
                  size: 54, color: Color(0xFF313A5F)),
              const SizedBox(height: 16),
              Text(t.get('age_18_plus_notice'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(t.get('age_privacy_reason'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Semantics(
                button: true,
                label: t.get('age_birth_date'),
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(formatted),
                  ),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _accepted,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _accepted = v == true),
                title: Text(t.get('age_accept_terms')),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const TermsPage())),
                    child: Text(t.get('terms_of_use')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PrivacyPage())),
                    child: Text(t.get('privacy_policy')),
                  ),
                ],
              ),
              if (_errorKey != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(t.get(_errorKey!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w700)),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _confirm,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.get('continue')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
