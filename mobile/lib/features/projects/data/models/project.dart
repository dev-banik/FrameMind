import '../../../../core/utils/json.dart';
import '../../../history/data/models/chat_models.dart';

class Project {
  const Project({
    required this.id,
    required this.name,
    this.chatCount = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final int chatCount;
  final DateTime? createdAt;

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: asString(json['id']),
        name: asString(json['name']),
        chatCount: asInt(json['chatCount']),
        createdAt: asDateOrNull(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'chatCount': chatCount,
        'createdAt': dateToJson(createdAt),
      };

  Project copyWith({String? name, int? chatCount}) => Project(
        id: id,
        name: name ?? this.name,
        chatCount: chatCount ?? this.chatCount,
        createdAt: createdAt,
      );
}

/// Response of `GET /project/{id}`.
class ProjectDetail {
  const ProjectDetail({
    required this.id,
    required this.name,
    this.createdAt,
    this.chats = const [],
  });

  final String id;
  final String name;
  final DateTime? createdAt;
  final List<ChatSummary> chats;

  factory ProjectDetail.fromJson(Map<String, dynamic> json) => ProjectDetail(
        id: asString(json['id']),
        name: asString(json['name']),
        createdAt: asDateOrNull(json['createdAt']),
        chats: parseList(json['chats'], ChatSummary.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': dateToJson(createdAt),
        'chats': chats.map((c) => c.toJson()).toList(),
      };
}
