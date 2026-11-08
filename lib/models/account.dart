/// The signed-in user, as the account knows them.
///
/// Swat is not built for one demo persona: whoever logs in is the person
/// being protected, and the app uses *their* name — in the greeting, on
/// protection reports, and as the author of blocks they file.
///
/// The display name comes from the account info: the name on the account
/// when there is one, otherwise a name made from the account email
/// (`maya.reyes@…` → "Maya Reyes") — the same trick mail apps use when a
/// profile has no display name yet.
library;

class UserAccount {
  const UserAccount({required this.name, required this.email});

  /// Name on the account; may be empty (then [displayName] derives one).
  final String name;

  final String email;

  /// The name the app should use for this person, always non-empty.
  String get displayName {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return deriveNameFromEmail(email);
  }

  String get firstName => displayName.split(' ').first;

  /// Make a presentable name out of an email address:
  /// `ryan.edward@`, `ryan_edward@`, `RYAN-EDWARD@` → "Ryan Edward".
  /// A local part with no usable words yields "Friend" rather than a
  /// blank or a string of digits.
  static String deriveNameFromEmail(String email) {
    final local = email.split('@').first;
    final words = local
        .split(RegExp(r'[._\-+]+'))
        .where((w) => w.isNotEmpty && !RegExp(r'^\d+$').hasMatch(w))
        .toList();
    if (words.isEmpty) return 'Friend';
    return words
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  Map<String, String> toMap() => {'name': name, 'email': email};

  static UserAccount? fromMap(Map<dynamic, dynamic> map) {
    final email = (map['email'] as String?)?.trim() ?? '';
    if (email.isEmpty) return null;
    return UserAccount(name: (map['name'] as String?) ?? '', email: email);
  }
}
