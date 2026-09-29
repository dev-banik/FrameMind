import '../models/enums.dart';

/// Returns a normalized http(s) URI or null if [input] isn't a usable link.
Uri? parseVideoUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty || !uri.host.contains('.')) return null;
  return uri;
}

SourcePlatform detectPlatform(String input) {
  final uri = parseVideoUrl(input);
  if (uri == null) return SourcePlatform.other;
  final host = uri.host.toLowerCase();
  bool matches(List<String> domains) =>
      domains.any((d) => host == d || host.endsWith('.$d'));

  if (matches(['youtube.com', 'youtu.be', 'youtube-nocookie.com'])) {
    return SourcePlatform.youTube;
  }
  if (matches(['facebook.com', 'fb.watch', 'fb.com'])) {
    return SourcePlatform.facebook;
  }
  if (matches(['instagram.com', 'instagr.am'])) {
    return SourcePlatform.instagram;
  }
  if (matches(['tiktok.com'])) {
    return SourcePlatform.tikTok;
  }
  return SourcePlatform.other;
}

/// Validation message for the URL field, or null if the URL is acceptable.
String? validateVideoUrl(String? input) {
  final text = input?.trim() ?? '';
  if (text.isEmpty) return 'Paste a video link to get started';
  if (parseVideoUrl(text) == null) return "That doesn't look like a valid link";
  return null;
}
