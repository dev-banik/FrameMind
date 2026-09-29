import '../../../../core/models/enums.dart';
import '../../../../core/utils/json.dart';

/// Response of `GET /users/me`.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.plan,
    required this.maxResolution,
    this.photoUrl,
    this.videosGeneratedToday = 0,
    this.dailyVideoLimit,
  });

  final String id;
  final String name;
  final String email;
  final String? photoUrl;
  final Plan plan;
  final int videosGeneratedToday;

  /// Null means unlimited.
  final int? dailyVideoLimit;
  final Resolution maxResolution;

  bool get isPremium => plan == Plan.premium;

  bool get isUnlimited => dailyVideoLimit == null;

  int? get remainingToday {
    final limit = dailyVideoLimit;
    if (limit == null) return null;
    final remaining = limit - videosGeneratedToday;
    return remaining < 0 ? 0 : remaining;
  }

  bool get quotaExhausted => remainingToday != null && remainingToday! <= 0;

  bool canUse(Resolution resolution) =>
      resolution.index <= maxResolution.index || isPremium;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: asString(json['id']),
        name: asString(json['name']),
        email: asString(json['email']),
        photoUrl: asStringOrNull(json['photoUrl']),
        plan: Plan.parse(json['plan']),
        videosGeneratedToday: asInt(json['videosGeneratedToday']),
        dailyVideoLimit: asIntOrNull(json['dailyVideoLimit']),
        maxResolution: Resolution.parse(json['maxResolution']),
      );
}
