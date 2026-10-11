/// Pure rules for creating more than one group.
///
/// Shared by Android and iOS. A new form signature gets a new request id.
/// The same signature keeps the id so a double tap or a retry cannot create
/// a second document for that attempt.
class GroupCityCandidate {
  const GroupCityCandidate({
    required this.cityName,
    required this.stateName,
    required this.countryName,
    required this.display,
    required this.placeId,
  });

  final String cityName;
  final String stateName;
  final String countryName;
  final String display;
  final String placeId;
}

class GroupCityDecision {
  const GroupCityDecision._({
    required this.accepted,
    required this.pending,
    this.placeId = '',
    this.cityName = '',
    this.stateName = '',
    this.display = '',
    this.messageKey,
  });

  final bool accepted;
  final bool pending;
  final String placeId;
  final String cityName;
  final String stateName;
  final String display;
  final String? messageKey;

  static const notRequired = GroupCityDecision._(
    accepted: true,
    pending: false,
  );
}

class GroupCreateFinish {
  const GroupCreateFinish({
    required this.groupId,
    required this.toastKey,
    required this.keepGroup,
    required this.createAgain,
  });

  final String groupId;
  final String toastKey;
  final bool keepGroup;
  final bool createAgain;
}

class GroupCreateFlow {
  GroupCreateFlow._();

  static bool textMatchesSelection({
    required String typed,
    required String cityName,
    required String display,
  }) {
    final value = typed.trim().toLowerCase();
    if (value.isEmpty) return false;
    final city = cityName.trim().toLowerCase();
    final shown = display.trim().toLowerCase();
    if (value == city || value == shown) return true;
    if (shown.startsWith('$value,')) return true;
    if (city.isNotEmpty && shown.startsWith('$city,')) {
      return value == city;
    }
    return false;
  }

  /// A stored placeId is enough when the visible text still describes it.
  /// Typed text is accepted only when one suggestion matches. Several
  /// suggestions, or none, stay pending with a specific message.
  static GroupCityDecision resolveCity({
    required bool required,
    required String typed,
    required String selectedPlaceId,
    required String selectedCityName,
    required String selectedStateName,
    required String selectedDisplay,
    required List<GroupCityCandidate> suggestions,
    required bool searched,
  }) {
    if (!required) return GroupCityDecision.notRequired;

    final placeId = selectedPlaceId.trim();
    final text = typed.trim();
    final shown = selectedDisplay.trim().isEmpty
        ? selectedCityName.trim()
        : selectedDisplay.trim();
    if (placeId.isNotEmpty &&
        textMatchesSelection(
          typed: text.isEmpty ? shown : text,
          cityName: selectedCityName,
          display: shown,
        )) {
      return GroupCityDecision._(
        accepted: true,
        pending: false,
        placeId: placeId,
        cityName: selectedCityName.trim(),
        stateName: selectedStateName.trim(),
        display: selectedDisplay.trim().isEmpty
            ? selectedCityName.trim()
            : selectedDisplay.trim(),
      );
    }

    if (text.isEmpty) {
      return const GroupCityDecision._(
        accepted: false,
        pending: true,
        messageKey: 'create_group_enter_city',
      );
    }

    if (!searched) {
      return const GroupCityDecision._(
        accepted: false,
        pending: true,
        messageKey: 'group_create_place_required',
      );
    }

    final matches = suggestions.where((item) {
      if (item.placeId.trim().isEmpty) return false;
      return textMatchesSelection(
        typed: text,
        cityName: item.cityName,
        display: item.display,
      );
    }).toList();

    if (matches.length == 1) {
      final item = matches.first;
      return GroupCityDecision._(
        accepted: true,
        pending: false,
        placeId: item.placeId.trim(),
        cityName: item.cityName.trim(),
        stateName: item.stateName.trim(),
        display: item.display.trim(),
      );
    }
    if (matches.isEmpty) {
      return const GroupCityDecision._(
        accepted: false,
        pending: true,
        messageKey: 'group_create_city_invalid',
      );
    }
    return const GroupCityDecision._(
      accepted: false,
      pending: true,
      messageKey: 'group_create_place_required',
    );
  }

  static String signature({
    required String name,
    required String scope,
    required String placeId,
    required String country,
    required String joinPolicy,
  }) {
    return [
      name.trim(),
      scope.trim(),
      placeId.trim(),
      country.trim(),
      joinPolicy.trim(),
    ].join('\u0001');
  }

  static String requestIdFor({
    required String? currentId,
    required String? boundSignature,
    required String signature,
    required String Function() mint,
  }) {
    final existing = (currentId ?? '').trim();
    if (existing.isNotEmpty && boundSignature == signature) return existing;
    return mint();
  }

  static bool shouldStartSubmit({required bool inFlight}) => !inFlight;

  /// The group already exists. An image failure must not delete it or
  /// start another create.
  static GroupCreateFinish finish({
    required String groupId,
    required bool avatarFailed,
  }) {
    return GroupCreateFinish(
      groupId: groupId,
      toastKey: avatarFailed
          ? 'group_create_avatar_failed'
          : 'group_create_success',
      keepGroup: true,
      createAgain: false,
    );
  }
}
