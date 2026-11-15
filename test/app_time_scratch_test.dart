import 'package:flutter_test/flutter_test.dart';
import 'package:pwa/utils/app_time.dart';
void main() {
  test('local', () {
    final l = DateTime.utc(2026, 11, 14, 3, 30).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final expected = '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
    expect(AppTime.formatDateTime('2026-11-14T03:30:00Z'), expected);
    expect(AppTime.formatDateTime('2026-11-14T03:30:00'), expected);
    expect(AppTime.formatDateTime('2026-11-14 03:30:00+00'), expected);
    print('${DateTime.now().timeZoneName}: $expected');
  });
}
