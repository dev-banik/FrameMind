import '../../../../core/utils/json.dart';

class ScriptCharacter {
  const ScriptCharacter({required this.name, this.description = ''});

  final String name;
  final String description;

  factory ScriptCharacter.fromJson(Map<String, dynamic> json) => ScriptCharacter(
        name: asString(json['name']),
        description: asString(json['description']),
      );

  Map<String, dynamic> toJson() => {'name': name, 'description': description};
}

class Dialogue {
  const Dialogue({required this.character, required this.line});

  final String character;
  final String line;

  factory Dialogue.fromJson(Map<String, dynamic> json) => Dialogue(
        character: asString(json['character']),
        line: asString(json['line']),
      );

  Map<String, dynamic> toJson() => {'character': character, 'line': line};

  Dialogue copyWith({String? character, String? line}) => Dialogue(
        character: character ?? this.character,
        line: line ?? this.line,
      );
}

class Scene {
  const Scene({
    required this.number,
    this.visual = '',
    this.narration = '',
    this.dialogues = const [],
    this.cameraDirection = '',
    this.durationSeconds = 5,
  });

  final int number;
  final String visual;
  final String narration;
  final List<Dialogue> dialogues;
  final String cameraDirection;
  final int durationSeconds;

  factory Scene.fromJson(Map<String, dynamic> json) => Scene(
        number: asInt(json['number'], 1),
        visual: asString(json['visual']),
        narration: asString(json['narration']),
        dialogues: parseList(json['dialogues'], Dialogue.fromJson),
        cameraDirection: asString(json['cameraDirection']),
        durationSeconds: asInt(json['durationSeconds'], 5),
      );

  Map<String, dynamic> toJson() => {
        'number': number,
        'visual': visual,
        'narration': narration,
        'dialogues': dialogues.map((d) => d.toJson()).toList(),
        'cameraDirection': cameraDirection,
        'durationSeconds': durationSeconds,
      };

  Scene copyWith({
    int? number,
    String? visual,
    String? narration,
    List<Dialogue>? dialogues,
    String? cameraDirection,
    int? durationSeconds,
  }) =>
      Scene(
        number: number ?? this.number,
        visual: visual ?? this.visual,
        narration: narration ?? this.narration,
        dialogues: dialogues ?? this.dialogues,
        cameraDirection: cameraDirection ?? this.cameraDirection,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );
}

class Script {
  const Script({
    required this.title,
    this.summary = '',
    this.characters = const [],
    this.scenes = const [],
  });

  final String title;
  final String summary;
  final List<ScriptCharacter> characters;
  final List<Scene> scenes;

  int get totalDurationSeconds =>
      scenes.fold(0, (sum, scene) => sum + scene.durationSeconds);

  factory Script.fromJson(Map<String, dynamic> json) => Script(
        title: asString(json['title']),
        summary: asString(json['summary']),
        characters: parseList(json['characters'], ScriptCharacter.fromJson),
        scenes: parseList(json['scenes'], Scene.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'characters': characters.map((c) => c.toJson()).toList(),
        'scenes': scenes.map((s) => s.toJson()).toList(),
      };

  Script copyWith({
    String? title,
    String? summary,
    List<ScriptCharacter>? characters,
    List<Scene>? scenes,
  }) =>
      Script(
        title: title ?? this.title,
        summary: summary ?? this.summary,
        characters: characters ?? this.characters,
        scenes: scenes ?? this.scenes,
      );
}
