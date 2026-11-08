/// Email message type for the fleet's second beat: the mailbox.
///
/// The fleet started over text messages, but the original Signal Swarm
/// stage was an email inbox — and phishing email has tells texts don't
/// (sending domains, Reply-To tricks, attachments). [EmailMessage] carries
/// those fields so the email analyzer can check them.
library;

class EmailMessage {
  const EmailMessage({
    required this.id,
    required this.fromName,
    required this.fromAddress,
    required this.subject,
    required this.body,
    required this.timeLabel,
    this.replyTo,
    this.qrPayload,
    this.attachmentName,
  });

  final String id;

  /// Display name — free text the sender chooses, never verified.
  final String fromName;

  /// The actual sending address; its domain is what Angler verifies.
  final String fromAddress;

  final String subject;
  final String body;
  final String timeLabel;

  /// Where replies actually go, if different from [fromAddress]. A
  /// classic phish trick: the From looks right, your reply (with the
  /// info they asked for) goes somewhere else entirely.
  final String? replyTo;

  final String? qrPayload;
  final String? attachmentName;

  String get fromDomain {
    final at = fromAddress.lastIndexOf('@');
    return at >= 0 ? fromAddress.substring(at + 1).toLowerCase() : '';
  }

  bool get hasAttachment => attachmentName != null;

  /// Subject line + body, exactly as displayed in the reading view — the
  /// analyzer runs on this string so finding spans highlight in place.
  String get displayText => '$subject\n$body';

  String get snippet {
    final flat = body.replaceAll('\n', ' ');
    return flat.length <= 80 ? flat : '${flat.substring(0, 80)}…';
  }
}
