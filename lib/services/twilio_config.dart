/// The fleet's Twilio number — the "Fleet Line" (redo of the earlier
/// Photon line, on Twilio instead).
///
/// Calls to this number hit the `swat-call-block` Twilio Function
/// (source in `twilio/` at the repo root): callers on the block list
/// are rejected instantly and the user gets a spoken alert call;
/// everyone else rings through. Supplied at run time, never
/// committed:
///
///   flutter run --dart-define=TWILIO_FLEET_NUMBER=+1XXXXXXXXXX
const String kTwilioFleetNumber = String.fromEnvironment(
  'TWILIO_FLEET_NUMBER',
);

bool get twilioConfigured => kTwilioFleetNumber.isNotEmpty;
