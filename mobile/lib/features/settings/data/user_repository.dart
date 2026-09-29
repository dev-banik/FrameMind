import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'models/user_profile.dart';

/// `/users/*` endpoints.
class UserRepository {
  UserRepository(this._api);

  final ApiClient _api;

  /// `GET /users/me`
  Future<UserProfile> getMe() async {
    final data = await _api.get('/users/me');
    return UserProfile.fromJson(asJsonMap(data));
  }

  /// `POST /users/me/device-token` with platform `android` | `ios`.
  Future<void> registerDeviceToken(String token, String platform) async {
    await _api.post(
      '/users/me/device-token',
      data: {'token': token, 'platform': platform},
    );
  }
}

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(apiClientProvider)),
);
