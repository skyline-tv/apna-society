import 'package:apna_society/services/visitor_speech_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const known = {
    'A-302',
    'B-204',
    'C-501',
    'A-101',
    'E-704',
  };

  test('English personal visit extracts name, mobile, flat, purpose', () {
    final p = parseVisitorSpeech(
      'Rahul Sharma, mobile number 9876543210, flat A 302, personal visit.',
      knownFlatNumbers: known,
    );
    expect(p.name, 'Rahul Sharma');
    expect(p.mobile, '9876543210');
    expect(p.wing, 'A');
    expect(p.flatNumber, 'A-302');
    expect(p.category, 'Guest');
    expect(p.purpose?.toLowerCase(), contains('personal'));
    expect(p.missingFields, isEmpty);
  });

  test('Hinglish delivery extracts name, flat B-204, category Delivery', () {
    final p = parseVisitorSpeech(
      'Ek delivery person aaya hai flat B 204 ke liye, naam Amit hai, mobile number 9876543210.',
      knownFlatNumbers: known,
    );
    expect(p.name, 'Amit');
    expect(p.mobile, '9876543210');
    expect(p.wing, 'B');
    expect(p.flatNumber, 'B-204');
    expect(p.category, 'Delivery');
  });

  test('Visitor with domestic help and vehicle plate', () {
    final p = parseVisitorSpeech(
      'Visitor Priya Shah, flat C 501, coming for domestic help, vehicle number MH 05 AB 1234.',
      knownFlatNumbers: known,
    );
    expect(p.name, 'Priya Shah');
    expect(p.wing, 'C');
    expect(p.flatNumber, 'C-501');
    expect(p.category, 'Domestic Help');
    expect(p.vehicleNumber, 'MH05AB1234');
    expect(p.mobile, isNull);
    expect(p.missingFields, contains('mobile'));
  });

  test('unknown flat is not invented', () {
    final p = parseVisitorSpeech(
      'Guest Ravi, mobile 9876501234, flat A 999, personal visit.',
      knownFlatNumbers: known,
    );
    expect(p.flatNumber, isNull);
    expect(p.wing, 'A');
    expect(p.missingFields, contains('flatNumber'));
    expect(p.uncertainFields, contains('flatNumber'));
  });

  test('missing mobile leaves field empty', () {
    final p = parseVisitorSpeech(
      'Visitor Neha Patel, flat A-101, personal visit.',
      knownFlatNumbers: known,
    );
    expect(p.name, 'Neha Patel');
    expect(p.flatNumber, 'A-101');
    expect(p.mobile, isNull);
    expect(p.missingFields, contains('mobile'));
  });

  test('Indian vehicle plate variants normalize', () {
    final p = parseVisitorSpeech(
      'Cab for flat E 704, vehicle MH-05-AB-1234, mobile 9123456780, name Suresh.',
      knownFlatNumbers: known,
    );
    expect(p.vehicleNumber, 'MH05AB1234');
    expect(p.category, 'Cab');
    expect(p.flatNumber, 'E-704');
  });

  test('spaced STT digits for mobile and flat', () {
    final p = parseVisitorSpeech(
      'Visitor Ravi, mobile 9 8 7 6 5 4 3 2 1 0, flat A 3 0 2, personal visit.',
      knownFlatNumbers: known,
    );
    expect(p.mobile, '9876543210');
    expect(p.flatNumber, 'A-302');
  });
}
