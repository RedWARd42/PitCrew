import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/core/redactor.dart';

void main() {
  final r = Redactor();
  // input -> expected output
  final cases = <String, String>{
    'mail me at jane.doe+x@mail.example.com ok': 'mail me at <EMAIL> ok',
    'a@b.co and c@d.org': '<EMAIL> and <EMAIL>',
    'card 4111 1111 1111 1111 thanks': 'card <CARD> thanks',
    'card 4111-1111-1111-1111': 'card <CARD>',
    'pay 4111111111111111': 'pay <CARD>',
    'amex 378282246310005 done': 'amex <CARD> done',
    'ssn 123-45-6789 ok': 'ssn <SSN> ok',
    'ssn: 078-05-1120.': 'ssn: <SSN>.',
    'live at 123 Main Street today': 'live at <ADDR> today',
    'send to 4500 Elm Ave.': 'send to <ADDR>',
    'office 77 Sunset Blvd now': 'office <ADDR> now',
    'Your code is 482913': 'Your code is <CODE:6>',
    'otp 1234': 'otp <CODE:4>',
    'use 12345678 to log in': 'use <CODE:8> to log in',
    'pin 98765 here': 'pin <CODE:5> here',
    // things that must be left alone
    'call 469-555-0182 now': 'call 469-555-0182 now',
    'call +1 (469) 555-0182': 'call +1 (469) 555-0182',
    'total is \$1234.50': 'total is \$1234.50',
    'pay \$5000 today': 'pay \$5000 today',
    'at 10:30 pm': 'at 10:30 pm',
    'meet at 1130 am': 'meet at 1130 am',
    'only 123 left': 'only 123 left',
    'wins 99999999999 points': 'wins 99999999999 points',
    'not a card 1234 5678 9012 3456': 'not a card <CODE:4> <CODE:4> <CODE:4> <CODE:4>',
    'visit https://t-mobi1e-acct-verify.co/a8f?c=123456 now': 'visit https://t-mobi1e-acct-verify.co/a8f?c=123456 now',
    'go to www.bank-secure.com/login/12345': 'go to www.bank-secure.com/login/12345',
    'see example.com/x/987654': 'see example.com/x/987654',
    'hello there': 'hello there',
    '': '',
    'a@b.co code 123456 at https://x.co/12345': '<EMAIL> code <CODE:6> at https://x.co/12345',
  };
  cases.forEach((input, expected) {
    test('redact "$input"', () => expect(r.redact(input).text, expected));
  });

  test('luhn', () {
    expect(luhnValid('4111111111111111'), isTrue);
    expect(luhnValid('4111111111111112'), isFalse);
    expect(luhnValid('123'), isFalse);
  });

  test('counts and toRedactions', () {
    final x = r.redact('a@b.co 482913 and 123456');
    expect(x.counts, {'EMAIL': 1, 'CODE': 2});
    expect(x.toRedactions(), containsAll([{'type': 'EMAIL', 'count': 1}, {'type': 'CODE', 'count': 2}]));
  });

  test('contact names replaced, whole word, case-insensitive', () {
    final x = r.redact('Hi MOM, tell Momentum and mom', contactNames: ['Mom']);
    expect(x.text, 'Hi CONTACT, tell Momentum and CONTACT');
    expect(x.counts['CONTACT'], 2);
  });

  test('longer contact names win', () {
    expect(r.redact('Ann Lee called', contactNames: ['Ann', 'Ann Lee']).text, 'CONTACT called');
  });

  test('output never contains the raw secrets', () {
    final out = r.redact('card 4111 1111 1111 1111 ssn 123-45-6789 code 482913 jane@x.com').text;
    for (final s in ['4111', '123-45', '482913', 'jane']) {
      expect(out.contains(s), isFalse, reason: s);
    }
  });
}
