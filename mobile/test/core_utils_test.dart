import 'package:flutter_test/flutter_test.dart';
import 'package:framemind/core/models/enums.dart';
import 'package:framemind/core/utils/date_grouping.dart';
import 'package:framemind/core/utils/url_utils.dart';
import 'package:framemind/features/history/data/models/chat_models.dart';

void main() {
  group('enum parsing', () {
    test('is case-insensitive', () {
      expect(ChatStatus.parse('scriptready'), ChatStatus.scriptReady);
      expect(GenerationStage.parse('GeneratingVideo'), GenerationStage.generatingVideo);
      expect(Resolution.parse('P1080'), Resolution.p1080);
    });

    test('tolerates unknown values', () {
      expect(ChatStatus.parse('Archived'), ChatStatus.unknown);
      expect(GenerationStage.parse(null), GenerationStage.unknown);
      expect(SourcePlatform.parse('Vimeo'), SourcePlatform.other);
      expect(Language.tryParse('French'), isNull);
    });
  });

  group('date grouping', () {
    final now = DateTime(2026, 9, 29, 15);

    test('buckets relative to now', () {
      expect(dateGroupFor(DateTime(2026, 9, 29, 1), now: now), DateGroup.today);
      expect(dateGroupFor(DateTime(2026, 9, 28, 23), now: now), DateGroup.yesterday);
      expect(dateGroupFor(DateTime(2026, 9, 24), now: now), DateGroup.last7Days);
      expect(dateGroupFor(DateTime(2026, 9, 5), now: now), DateGroup.lastMonth);
      expect(dateGroupFor(DateTime(2026, 6, 1), now: now), DateGroup.older);
    });

    test('groups keep bucket order', () {
      final groups = groupByDate<DateTime>(
        [DateTime(2026, 1, 1), DateTime(2026, 9, 29), DateTime(2026, 9, 28)],
        (d) => d,
        now: now,
      );
      expect(groups.keys.toList(), [DateGroup.today, DateGroup.yesterday, DateGroup.older]);
    });
  });

  group('url utils', () {
    test('detects platforms', () {
      expect(detectPlatform('https://youtu.be/abc'), SourcePlatform.youTube);
      expect(detectPlatform('www.tiktok.com/@a/video/1'), SourcePlatform.tikTok);
      expect(detectPlatform('https://m.facebook.com/watch?v=1'), SourcePlatform.facebook);
      expect(detectPlatform('https://instagram.com/reel/x'), SourcePlatform.instagram);
      expect(detectPlatform('https://vimeo.com/1'), SourcePlatform.other);
    });

    test('validates links', () {
      expect(validateVideoUrl(''), isNotNull);
      expect(validateVideoUrl('not a url'), isNotNull);
      expect(validateVideoUrl('https://youtu.be/abc'), isNull);
    });
  });

  test('ChatSummary round-trips JSON', () {
    final json = {
      'id': '1',
      'projectId': null,
      'title': 'Kindness',
      'thumbnailUrl': null,
      'language': 'Bangla',
      'durationSeconds': 60,
      'status': 'Completed',
      'latestVideoId': 'v1',
      'createdAt': '2026-09-29T10:00:00Z',
    };
    final chat = ChatSummary.fromJson(json);
    expect(chat.language, Language.bangla);
    expect(chat.status, ChatStatus.completed);
    expect(chat.hasVideo, isTrue);
    expect(ChatSummary.fromJson(chat.toJson()).createdAt, chat.createdAt);
  });
}
