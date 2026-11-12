import 'package:event_map/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profil JSON gidiş-dönüşü tercihleri korur', () {
    const user = AppUser(
      id: '1',
      email: 'a@b.com',
      fullName: 'Ada Yılmaz',
      role: UserRole.user,
      preferences: UserPreferences(
        categories: {'concert'},
        district: 'Konak',
        radiusKm: 10,
      ),
    );
    final back = AppUser.fromProfileJson(
      user.toProfileJson(),
      email: user.email,
    );
    expect(back.preferences.categories, {'concert'});
    expect(back.preferences.district, 'Konak');
    expect(back.preferences.radiusKm, 10);
    expect(back.initials, 'AY');
  });

  test('ilçe temizlenebilir', () {
    const prefs = UserPreferences(district: 'Bornova');
    expect(prefs.copyWith(clearDistrict: true).district, isNull);
  });
}
