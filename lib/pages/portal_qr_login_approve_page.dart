import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/portal_qr_error_text.dart';

class PortalQrLoginApprovePage extends StatefulWidget {
  const PortalQrLoginApprovePage({
    super.key,
    required this.sessionId,
  });

  final String sessionId;

  @override
  State<PortalQrLoginApprovePage> createState() =>
      _PortalQrLoginApprovePageState();
}

class _PortalQrLoginApprovePageState extends State<PortalQrLoginApprovePage> {
  static const Color _primary = Color(0xFF313A5F);
  static const Color _secondary = Color(0xFF264E9A);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _background = Color(0xFFF5F7FB);
  static const Color _error = Color(0xFFDC2626);

  bool _isSubmitting = false;
  bool _completed = false;
  String? _errorMessage;

  Future<void> _approve() async {
    if (_isSubmitting || _completed) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = AppTexts.current.get('portal_qr_need_login');
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('approvePortalQrLogin');

      await callable.call<Map<String, dynamic>>({
        'sessionId': widget.sessionId,
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _completed = true;
        _isSubmitting = false;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _errorMessage = _messageForFunctionsError(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _errorMessage = AppTexts.current.get('portal_qr_generic');
      });
    }
  }

  String _messageForFunctionsError(FirebaseFunctionsException error) {
    return portalQrErrorText(error);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    final userLabel = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (user?.email ?? t.get('portal_qr_your_account'));
    final photoUrl = user?.photoURL?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final initial = userLabel.isNotEmpty ? userLabel[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _primary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          t.get('portal_qr_title'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Text(
                  t.get('portal_qr_brand'),
                  style: TextStyle(
                    color: _primary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  t.get('portal_qr_subtitle'),
                  style: TextStyle(
                    color: _muted,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: _background,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Icon(
                    _completed
                        ? Icons.check_circle_outline
                        : Icons.computer_outlined,
                    size: 40,
                    color: _completed ? _secondary : _primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _completed
                    ? t.get('portal_qr_authorized')
                    : t.get('portal_qr_authorize_button'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _primary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _completed
                    ? t.get('portal_qr_success_body')
                    : t.get('portal_qr_confirm_as'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: _muted,
                ),
              ),
              if (!_completed) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFE8ECF5),
                        backgroundImage:
                            hasPhoto ? NetworkImage(photoUrl) : null,
                        child: hasPhoto
                            ? null
                            : Text(
                                initial,
                                style: const TextStyle(
                                  color: _primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userLabel,
                              style: const TextStyle(
                                color: _primary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              t.get('portal_qr_account'),
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _error.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _error,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (!_completed) ...[
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _approve,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _secondary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            t.get('portal_qr_confirm'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: const BorderSide(color: _border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      t.get('cancel'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ] else
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _secondary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      t.get('portal_qr_done'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
