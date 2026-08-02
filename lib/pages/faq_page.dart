import 'package:flutter/material.dart';
import '../l10n/app_texts.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8, left: 2),
      child: Text(
        title,
        style: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _qa({
    required String q,
    required String a,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Theme(
          data: ThemeData(
            dividerColor: Colors.transparent,
          ),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8),
            title: Text(
              q,
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            iconColor: _muted,
            collapsedIconColor: _muted,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  a,
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _section(
    AppTexts t, {
    required String titleKey,
    required List<List<String>> items,
  }) {
    return [
      _sectionTitle(t.get(titleKey)),
      ...items.map(
        (item) => _qa(
          q: t.get(item[0]),
          a: t.get(item[1]),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: true,
        title: Text(
          t.get('faq'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.get('frequently_asked_questions'),
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.get('faq_intro'),
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ..._section(
            t,
            titleKey: 'faq_cat_about',
            items: const [
              ['faq_what_is_remdy_q', 'faq_what_is_remdy_a'],
              ['faq_countries_available_q', 'faq_countries_available_a'],
              ['faq_change_country_q', 'faq_change_country_a'],
              ['faq_city_location_q', 'faq_city_location_a'],
            ],
          ),
          ..._section(
            t,
            titleKey: 'faq_cat_account',
            items: const [
              ['faq_who_sees_profile_q', 'faq_who_sees_profile_a'],
              ['faq_delete_account_q', 'faq_delete_account_a'],
              ['faq_logout_q', 'faq_logout_a'],
              ['faq_languages_available_q', 'faq_languages_available_a'],
              ['faq_change_language_q', 'faq_change_language_a'],
            ],
          ),
          ..._section(
            t,
            titleKey: 'faq_cat_people',
            items: const [
              ['faq_message_anyone_q', 'faq_message_anyone_a'],
              ['faq_world_option_q', 'faq_world_option_a'],
              ['faq_block_person_q', 'faq_block_person_a'],
              ['faq_report_person_q', 'faq_report_person_a'],
              ['faq_reads_messages_q', 'faq_reads_messages_a'],
            ],
          ),
          ..._section(
            t,
            titleKey: 'faq_cat_groups',
            items: const [
              ['faq_groups_how_q', 'faq_groups_how_a'],
              ['faq_cant_join_group_q', 'faq_cant_join_group_a'],
              ['faq_create_group_q', 'faq_create_group_a'],
            ],
          ),
          ..._section(
            t,
            titleKey: 'faq_cat_events',
            items: const [
              ['faq_events_how_q', 'faq_events_how_a'],
              ['faq_events_organized_by_remdy_q', 'faq_events_organized_by_remdy_a'],
              ['faq_create_event_q', 'faq_create_event_a'],
              ['faq_event_pending_q', 'faq_event_pending_a'],
            ],
          ),
          ..._section(
            t,
            titleKey: 'faq_cat_remi',
            items: const [
              ['faq_what_is_remi_q', 'faq_what_is_remi_a'],
              ['faq_remi_always_correct_q', 'faq_remi_always_correct_a'],
              ['faq_remi_private_chats_q', 'faq_remi_private_chats_a'],
            ],
          ),
          ..._section(
            t,
            titleKey: 'faq_cat_premium',
            items: const [
              ['faq_what_is_premium_q', 'faq_what_is_premium_a'],
              ['faq_how_subscribe_q', 'faq_how_subscribe_a'],
              ['faq_how_cancel_q', 'faq_how_cancel_a'],
              ['faq_restore_purchase_q', 'faq_restore_purchase_a'],
              ['faq_premium_not_active_q', 'faq_premium_not_active_a'],
              ['faq_free_to_use_q', 'faq_free_to_use_a'],
            ],
          ),
          ..._section(
            t,
            titleKey: 'faq_cat_invites',
            items: const [
              ['faq_invite_premium_q', 'faq_invite_premium_a'],
              ['faq_invite_milestones_q', 'faq_invite_milestones_a'],
              ['faq_invite_expired_q', 'faq_invite_expired_a'],
            ],
          ),
          ..._section(
            t,
            titleKey: 'faq_cat_privacy',
            items: const [
              ['faq_notifications_q', 'faq_notifications_a'],
              ['faq_no_notifications_q', 'faq_no_notifications_a'],
            ],
          ),
          ..._section(
            t,
            titleKey: 'faq_cat_support',
            items: const [
              ['faq_contact_support_q', 'faq_contact_support_a'],
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
