import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';


enum MenuAction {
  profile,
  invite,
  premium,
  language,
  notifications,
  faq,
  contact,
  terms,
  policy,
  about,
  logout,
}


class MenuPage extends StatefulWidget {
  final String name;
  final String photoUrl;
  final bool isPremium;
  final int invites;
  final int limit;


  final Widget profilePage;
  final Widget invitePage;
  final Widget premiumPage;
  final Widget languagePage;
  final Widget notificationsPage;
  final Widget faqPage;
  final Widget contactPage;
  final Widget termsPage;
  final Widget policyPage;
  final Widget aboutPage;


  final Future<void> Function() onLogout;


  const MenuPage({
    super.key,
    required this.name,
    required this.photoUrl,
    required this.isPremium,
    required this.invites,
    required this.limit,
    required this.profilePage,
    required this.invitePage,
    required this.premiumPage,
    required this.languagePage,
    required this.notificationsPage,
    required this.faqPage,
    required this.contactPage,
    required this.termsPage,
    required this.policyPage,
    required this.aboutPage,
    required this.onLogout,
  });


  @override
  State<MenuPage> createState() => _MenuPageState();
}


class _MenuPageState extends State<MenuPage> {
  String _loadedLocaleCode = '';


  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);


  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);


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



  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }


  Widget _item({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? _muted),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? _text,
          fontWeight: FontWeight.w800,
        ),
      ),
      onTap: onTap,
    );
  }


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: _muted),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
  t.get('menu'),
  style: const TextStyle(
    color: _text,
    fontWeight: FontWeight.w900,
  ),
)
 
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_remdyBlue, _logoBlue]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white.withOpacity(0.18),
                  backgroundImage:
                      widget.photoUrl.isNotEmpty ? NetworkImage(widget.photoUrl) : null,
                  child: widget.photoUrl.isEmpty
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.isPremium
                            ? t.get('premium_active')
                            : t.get('free_account'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _item(
                  context: context,
                  icon: Icons.person,
                  title: t.get('profile'),
                  onTap: () => _open(context, widget.profilePage),
                ),
                const Divider(height: 1),
                _item(
                  context: context,
                  icon: Icons.card_giftcard,
                  title: '${t.get('invite')} (${widget.invites}/${widget.limit})',
                  onTap: () => _open(context, widget.invitePage),
                ),
                const Divider(height: 1),
                _item(
                  context: context,
                  icon: Icons.star_rounded,
                  title: t.get('premium'),
                  onTap: () => _open(context, widget.premiumPage),
                ),
                const Divider(height: 1),
                _item(
                  context: context,
                  icon: Icons.language,
                  title: t.get('language'),
                  onTap: () => _open(context, widget.languagePage),
                ),
                const Divider(height: 1),
                _item(
                  context: context,
                  icon: Icons.notifications,
                  title: t.get('notifications'),
                  onTap: () => _open(context, widget.notificationsPage),
                ),
                const Divider(height: 1),
                _item(
                  context: context,
                  icon: Icons.help_outline,
                  title: t.get('faq'),
                  onTap: () => _open(context, widget.faqPage),
                ),
                const Divider(height: 1),
                _item(
                  context: context,
                  icon: Icons.mail_outline,
                  title: t.get('contact'),
                  onTap: () => _open(context, widget.contactPage),
                ),
                const Divider(height: 1),
                _item(
                  context: context,
                  icon: Icons.description_outlined,
                  title: t.get('terms'),
                  onTap: () => _open(context, widget.termsPage),
                ),
                const Divider(height: 1),
                _item(
                  context: context,
                  icon: Icons.privacy_tip_outlined,
                  title: t.get('privacy_policy'),
                  onTap: () => _open(context, widget.policyPage),
                ),
                const Divider(height: 1),
                _item(
                  context: context,
                  icon: Icons.info_outline,
                  title: t.get('about'),
                  onTap: () => _open(context, widget.aboutPage),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _item(
              context: context,
              icon: Icons.logout_rounded,
              title: t.get('logout'),
              onTap: () async {
                await widget.onLogout();
              },
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
