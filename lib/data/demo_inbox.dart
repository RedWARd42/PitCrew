/// Synthetic demo inbox.
///
/// Hackathon rule (T-Mobile Safe Signal): builders create their own
/// synthetic scam scenarios — no real customer data. These six messages are
/// invented, and each one exercises a different part of the fleet:
///
///  * `smish-tmobile` — the main scenario. One message that trips almost
///    every drone: spoofed sender, lookalike domain, QR push, pressure,
///    PIN ask, and verification-code fishing.
///  * `real-tmobile` — the genuine article from short code 456, there to
///    prove the fleet can also say "this one is fine" (honest confidence).
///  * `smish-chase`, `smish-usps` — two more scam shapes (bank alert,
///    redelivery fee).
///  * `mom`, `friend` — ordinary personal texts, no brand claims at all.
library;

import '../models/message.dart';

const List<ChatMessage> demoInbox = [
  ChatMessage(
    id: 'smish-tmobile',
    sender: '+1 872-555-0147',
    timeLabel: '9:41 PM',
    body:
        'T-Mobile: URGENT — your line will be SUSPENDED within 24 hours due '
        'to an unpaid balance of \$86.40. Verify NOW to keep your number '
        'active: t-mobile-verify-secure.com/pay — scan the QR code to '
        'confirm your account PIN and send us the 6-digit code we texted '
        'you. Do not ignore this final notice.',
    qrPayload: 'https://t-mobile-verify-secure.com/qr?id=881',
  ),
  ChatMessage(
    id: 'real-tmobile',
    sender: '456',
    timeLabel: '6:02 PM',
    body:
        'T-Mobile: Your bill of \$74.99 is ready. View or pay it in the '
        'T-Mobile app, or at t-mobile.com. It is due Nov 21. Questions? '
        'Call 611 from your T-Mobile phone.',
  ),
  ChatMessage(
    id: 'smish-chase',
    sender: '+1 312-555-0198',
    timeLabel: '4:17 PM',
    body:
        'CHASE FRAUD ALERT: Unusual purchase of \$1,240.00 at BESTBUY. If '
        'this was not you, verify immediately at chase-secure-login.xyz — '
        'your card will be locked if you do not respond today.',
  ),
  ChatMessage(
    id: 'smish-usps',
    sender: '+1 640-555-0113',
    timeLabel: '1:05 PM',
    body:
        'USPS: Your package is being held at the warehouse because of an '
        'incomplete address. Pay the \$1.99 redelivery fee within 12 hours '
        'to release it: usps-redelivery-fee.com/track',
  ),
  ChatMessage(
    id: 'mom',
    sender: 'Mom',
    timeLabel: '11:30 AM',
    body:
        'Running about 10 minutes late, traffic on 75 is awful. Start '
        'without me if the table is ready!',
  ),
  ChatMessage(
    id: 'friend',
    sender: '+1 214-555-0176',
    timeLabel: 'Yesterday',
    body:
        'that demo was actually insane lol. send me the link to the '
        'arcade build when you get a chance?',
  ),
];
