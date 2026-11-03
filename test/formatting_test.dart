import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/widgets/formatting.dart';

void main() {
  test('groups thousands with commas', () {
    expect(formatCount(0), '0');
    expect(formatCount(999), '999');
    expect(formatCount(1000), '1,000');
    expect(formatCount(10020), '10,020');
    expect(formatCount(1234567), '1,234,567');
    expect(formatCount(-4200), '-4,200');
  });

  test('says photo or photos', () {
    expect(photoCount(1), '1 photo');
    expect(photoCount(2), '2 photos');
    expect(photoCount(10020), '10,020 photos');
  });

  test('sizes read the way people say them', () {
    expect(formatSize(512), '512 B');
    expect(formatSize(2000), '2 KB');
    expect(formatSize(4404019), '4.2 MB');
  });

  test('months read as a name and a year', () {
    expect(formatMonth(DateTime(2024, 3)), 'March 2024');
    expect(formatMonth(DateTime(2025, 12, 31, 23)), 'December 2025');
    expect(formatMonth(DateTime(2026)), 'January 2026');
  });
}
