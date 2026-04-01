import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


import '../services/purchase_service.dart';
import '../l10n/app_texts.dart';


class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});


  @override
  State<PremiumPage> createState() => _PremiumPageState();
}


class _PremiumPageState extends State<PremiumPage> {
  final db = FirebaseFirestore.instance;
  final uid = FirebaseAuth.instance.currentUser?.uid;


  bool _loading = false;


  String? _priceString;
  bool _hasPackage = true;


  String _loadedLocaleCode = '';


  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);


  DocumentReference<Map<String, dynamic>> get _userDoc =>
      db.collection('users').doc(uid);


  @override
  void initState() {
    super.initState();


    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (uid == null) return;
      await _prepareRevenueCat();
      await _syncPremiumFromRevenueCat();
    });
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();


    final locale = Localizations.localeOf(context);
    final nextCode = '${locale.languageCode}_${locale.countryCode ?? ''}';


    if (_loadedLocaleCode == nextCode) return;
    _loadedLocaleCode = nextCode;


    AppTexts.load(locale).then((_) {
      if (mounted) setState(() {});
    });
  }


  Future<void> _prepareRevenueCat() async {
    if (uid == null) return;


    try {
      await PurchaseService.instance.configure(appUserId: uid!);


      final has = await PurchaseService.instance.hasPackageAvailable();
      final price = await PurchaseService.instance.getDefaultPriceString();


      if (!mounted) return;
      setState(() {
        _hasPackage = has;
        _priceString = price;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasPackage = false;
        _priceString = null;
      });
    }
  }


  Future<void> _syncPremiumFromRevenueCat() async {
    if (uid == null) return;


    try {
      await PurchaseService.instance.configure(appUserId: uid!);
      final premium = await PurchaseService.instance.isPremium();


      await _userDoc.set({
        'isPremium': premium,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }


  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      ),
    );
  }


  Future<void> _buyPremiumReal() async {
    final t = AppTexts.current;
    if (uid == null) return;


    if (!_hasPackage) {
      _snack(t.get('premium_in_setup_try_later'));
      return;
    }


    setState(() => _loading = true);
    try {
      await PurchaseService.instance.configure(appUserId: uid!);
      await PurchaseService.instance.buyPremium();
      await _syncPremiumFromRevenueCat();


      if (!mounted) return;
      _snack(t.get('premium_activated'));
    } catch (e) {
      if (!mounted) return;
      _snack('${t.get('purchase_error')}: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _restorePremiumReal() async {
    final t = AppTexts.current;
    if (uid == null) return;


    setState(() => _loading = true);
    try {
      await PurchaseService.instance.configure(appUserId: uid!);
      await PurchaseService.instance.restore();


      await _syncPremiumFromRevenueCat();


      if (!mounted) return;
      _snack(t.get('purchases_restored'));
    } catch (e) {
      if (!mounted) return;
      _snack('${t.get('restore_error')}: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  void _premiumAlreadyActiveInfo() {
    final t = AppTexts.current;
    _snack(t.get('premium_already_active'));
  }


  String _userCountryName(Map<String, dynamic> data) {
    final t = AppTexts.current;
    final country = (data['country'] ?? '').toString().trim();


    if (country.isEmpty) return t.get('your_country');


    return country;
  }


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;


    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    );


    if (uid == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: overlay,
            iconTheme: const IconThemeData(color: _text),
            title: Text(
              t.get('premium'),
              style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
            ),
          ),
          body: Center(child: Text(t.get('you_need_to_be_logged_in'))),
        ),
      );
    }


    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDoc.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final isPremium = (data['isPremium'] ?? false) == true;


        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(
              backgroundColor: _bg,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              systemOverlayStyle: overlay,
              iconTheme: const IconThemeData(color: _text),
              title: Text(
                t.get('premium'),
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 14,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7CC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFFE08A)),
                        ),
                        child: const Icon(Icons.star_rounded, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isPremium
                              ? t.get('your_premium_is_active')
                              : t.get('activate_premium_unlock_world'),
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: _text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  t.get('what_you_get_with_premium'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 10),
                _BenefitTile(
                  icon: Icons.public,
                  title:
                      '${_userCountryName(data)} + ${t.get('world')}',
                  subtitle: t.get('premium_benefit_all_countries_chat'),
                ),
                _BenefitTile(
                  icon: Icons.flash_on,
                  title: t.get('premium_benefit_no_country_block_title'),
                  subtitle: t.get('premium_benefit_no_country_block_subtitle'),
                ),
                _BenefitTile(
                  icon: Icons.timer_off,
                  title: t.get('premium_benefit_no_time_limit_title'),
                  subtitle: t.get('premium_benefit_no_time_limit_subtitle'),
                ),
                _BenefitTile(
                  icon: Icons.support_agent,
                  title: t.get('premium_benefit_priority_support_title'),
                  subtitle: t.get('premium_benefit_priority_support_subtitle'),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPremium
                            ? t.get('you_are_already_premium')
                            : t.get('ready_to_unlock_world'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: _text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPremium
                            ? t.get('if_change_phone_restore_purchase')
                            : (_hasPackage
                                ? t.get('subscribe_and_chat_outside_country')
                                : t.get('premium_products_not_connected')),
                        style: const TextStyle(
                          fontSize: 13,
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (!isPremium)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [_remdyBlue, _logoBlue],
                            ),
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _loading ? null : _buyPremiumReal,
                            icon: const Icon(Icons.star, size: 18),
                            label: Text(
                              _loading
                                  ? t.get('please_wait')
                                  : (_priceString == null
                                      ? t.get('subscribe_premium')
                                      : '${t.get('subscribe_premium')} • $_priceString'),
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _premiumAlreadyActiveInfo,
                          icon: const Icon(Icons.star_rounded, size: 18),
                          label: Text(
                            t.get('premium_active_short'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _remdyBlue,
                            side: const BorderSide(color: _border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _restorePremiumReal,
                        icon: const Icon(Icons.restore, size: 18),
                        label: Text(
                          t.get('restore_purchase'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _remdyBlue,
                          side: const BorderSide(color: _border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t.get('premium_observation_store_restore'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


class _BenefitTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;


  const _BenefitTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });


  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon, color: _remdyBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
