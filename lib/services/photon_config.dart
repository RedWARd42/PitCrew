/// Photon Fleet Line configuration.
///
/// The fleet also lives outside this app on Photon 2.0 (Spectrum): the
/// service in the repo's `photon/` folder answers texts on iMessage /
/// SMS (and any other enabled channel) and real voice calls on the
/// fleet's SMS number via a SIP voice provider.
///
/// The number is supplied at build/run time so no number is baked into
/// the source:
///
///   flutter run --dart-define=PHOTON_FLEET_NUMBER=+15551234567
///
/// Empty means "not set up yet" — the Fleet Line card then shows the
/// setup steps instead of dial buttons.
const String kPhotonFleetNumber = String.fromEnvironment('PHOTON_FLEET_NUMBER');

bool get photonFleetConfigured => kPhotonFleetNumber.isNotEmpty;
