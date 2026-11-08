/// Synthetic demo mailbox — same rule as the SMS demo inbox: invented
/// scenarios only, no real mail. Each email exercises different drones:
///
///  * `phish-tmobile-billing` — lookalike sending domain, pressure,
///    lookalike link, account-PIN ask.
///  * `phish-payroll-qr` — the original Signal Swarm scenario: a payroll
///    QR phish with a disguised sender and a Reply-To trick.
///  * `phish-ceo-giftcards` — impersonation + gift-card payment rail,
///    no link at all (proves the fleet isn't just a link checker).
///  * `real-tmobile-bill` — genuine: official domain, official link.
///  * `school-newsletter` — ordinary safe mail.
library;

import '../models/email.dart';

const List<EmailMessage> demoEmails = [
  EmailMessage(
    id: 'phish-tmobile-billing',
    fromName: 'T-Mobile Billing',
    fromAddress: 'billing@t-mobile-verify-secure.com',
    subject: 'ACTION REQUIRED: your payment failed — line suspension',
    timeLabel: '9:12 PM',
    body:
        'Dear customer,\n\n'
        'Your autopay payment of \$86.40 failed and your line will be '
        'SUSPENDED within 24 hours. Verify your account PIN and payment '
        'details immediately to keep your number active:\n\n'
        't-mobile-verify-secure.com/billing\n\n'
        'This is your final notice. Do not ignore this email.\n\n'
        '— T-Mobile Billing Team',
  ),
  EmailMessage(
    id: 'phish-payroll-qr',
    fromName: 'Payroll Department',
    fromAddress: 'payroll@contoso-payro11.com',
    replyTo: 'hr-replies@secure-forms.net',
    subject: 'Updated direct deposit form — action by Friday',
    timeLabel: '3:48 PM',
    body:
        'Hello team,\n\n'
        'We are migrating payroll providers. To avoid a delay in your '
        'next paycheck, scan the QR code in the attached notice and '
        'confirm your bank details and Social Security number on the '
        'secure form.\n\n'
        'Thank you,\nPayroll',
    qrPayload: 'https://contoso-payro11.com/deposit-form',
    attachmentName: 'Payroll_Notice_QR.pdf',
  ),
  EmailMessage(
    id: 'phish-ceo-giftcards',
    fromName: 'Daniel Reyes (CEO)',
    fromAddress: 'd.reyes.ceo@gmail.com',
    subject: 'Quick favor — confidential',
    timeLabel: '11:03 AM',
    body:
        'I am in a meeting and cannot talk. I need you to buy six '
        '\$100 gift cards for a client thank-you today — scratch the '
        'backs and email me the codes. Keep this between us until the '
        'announcement. I will reimburse you tomorrow.\n\n'
        '— Daniel',
  ),
  EmailMessage(
    id: 'real-tmobile-bill',
    fromName: 'T-Mobile',
    fromAddress: 'noreply@t-mobile.com',
    subject: 'Your T-Mobile bill is ready',
    timeLabel: 'Yesterday',
    body:
        'Hi Maya,\n\n'
        'Your bill of \$74.99 is ready to view. Sign in at t-mobile.com '
        'or open the T-Mobile app to see your statement. Payment is due '
        'Nov 21 — autopay will take care of it, no action needed.\n\n'
        'Thanks for being with T-Mobile.',
  ),
  EmailMessage(
    id: 'school-newsletter',
    fromName: 'UTD CS Department',
    fromAddress: 'cs-newsletter@utdallas.edu',
    subject: 'This week: career fair prep + research mixer',
    timeLabel: 'Mon',
    body:
        'Hello students,\n\n'
        'Career fair prep is Thursday at 5 PM in ECSS 2.102. The '
        'undergraduate research mixer follows at 6:30 — no registration '
        'needed, just bring yourselves.\n\n'
        '— CS Department',
  ),
];
