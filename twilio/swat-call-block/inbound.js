// swat-call-block /inbound — Twilio Function (deploy in the Twilio
// Console: Functions and Assets > Services > swat-call-block).
//
// A call comes in to the fleet's Twilio number:
//   * Caller is on BLOCKED_NUMBERS -> the call is rejected, and the
//     user immediately gets a spoken alert call ("Swat here. I
//     blocked a scam call from ..."), Squeek's sendAlert pattern:
//     Twilio Calls API, Polly.Joanna-Neural, said twice, 20s timeout.
//   * Anyone else -> the call dials through to the user's real phone.
//
// Environment variables (set in the Function service):
//   USER_PHONE       the user's real number, e.g. +1XXXXXXXXXX
//   BLOCKED_NUMBERS  comma-separated E.164 numbers to reject
exports.handler = (context, event, callback) => {
  const twiml = new Twilio.twiml.VoiceResponse();
  const blocked = (context.BLOCKED_NUMBERS || '')
    .split(',')
    .map((n) => n.trim())
    .filter(Boolean);

  if (blocked.includes(event.From)) {
    // 1) Block it.
    twiml.reject({ reason: 'busy' });

    // 2) Update the user with a spoken alert call.
    const client = context.getTwilioClient();
    const alert = new Twilio.twiml.VoiceResponse();
    alert.pause({ length: 1 });
    alert.say(
      { voice: 'Polly.Joanna-Neural' },
      `Swat here. I blocked a scam call from ${event.From}. Don't call them back.`,
    );
    alert.pause({ length: 1 });
    alert.say({ voice: 'Polly.Joanna-Neural' }, 'Again.');
    alert.say(
      { voice: 'Polly.Joanna-Neural' },
      `I blocked a scam call from ${event.From}.`,
    );

    client.calls
      .create({
        to: context.USER_PHONE,
        from: event.To, // the Twilio number the scam call came in on
        twiml: alert.toString(),
        timeout: 20,
      })
      .catch(() => {});

    return callback(null, twiml);
  }

  // Not blocked: put it through to the user.
  twiml.dial(context.USER_PHONE);
  return callback(null, twiml);
};
