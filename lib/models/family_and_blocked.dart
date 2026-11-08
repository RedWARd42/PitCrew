/// Trusted-family and blocked-list types.
///
/// Modeled on the pattern Ryan's team shipped in Squeek (Rowdy Hacks XII):
/// protection is shared — incidents and block lists sync with a trusted
/// family helper, and the helper can be reached (and can push warnings)
/// inside the app instead of the user facing a scam alone.
library;

import 'message.dart';

/// The one trusted person the user can always reach from inside Swat.
class TrustedContact {
  const TrustedContact({
    required this.name,
    required this.relation,
    required this.phone,
    required this.safeWord,
  });

  final String name;
  final String relation;

  /// Fictional 555 number — demo data only.
  final String phone;

  /// The family safe word: if a "family emergency" call or text can't
  /// produce it, it isn't family. Set up in person, never by text.
  final String safeWord;
}

/// Demo trusted contact for Maya, the customer in the demo inbox.
const TrustedContact demoTrustedContact = TrustedContact(
  name: 'Alex',
  relation: 'Son · trusted contact',
  phone: '+1 214-555-0142',
  safeWord: 'BLUEBONNET',
);

enum BlockStatus { blocked, reported }

/// One entry in the blocked/incident list — Squeek's "incidents + block
/// list" idea: every blocked message stays visible with its evidence, who
/// blocked it, and whether it was also reported, and entries can come from
/// the user's own phone or be shared by the trusted contact.
class BlockedEntry {
  const BlockedEntry({
    required this.id,
    required this.sender,
    required this.snippet,
    required this.whenLabel,
    required this.riskScore,
    required this.categories,
    required this.status,
    required this.blockedBy,
    required this.incidentId,
  });

  final String id;
  final String sender;
  final String snippet;
  final String whenLabel;
  final int riskScore;

  /// The drones that convicted it — shown as colored category chips.
  final List<DroneId> categories;
  final BlockStatus status;

  /// "You" or the trusted contact's name (family-shared block list).
  final String blockedBy;
  final String incidentId;
}

/// One message in the trusted-contact chat.
class FamilyChatMessage {
  const FamilyChatMessage({
    required this.fromMe,
    required this.text,
    required this.timeLabel,
    this.isScanCard = false,
    this.scanTitle = '',
    this.scanDetail = '',
  });

  final bool fromMe;
  final String text;
  final String timeLabel;

  /// True when this bubble is a shared scan result (the fleet's report
  /// card) rather than a typed message.
  final bool isScanCard;
  final String scanTitle;
  final String scanDetail;
}
