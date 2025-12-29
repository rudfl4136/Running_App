import 'latlng_point.dart';
import 'course_turn.dart';

class Course {
  final String id;
  final String title;
  final List<LatLngPoint> route;
  final List<CourseTurn> turns;
  final bool isPublic;
  final DateTime createdAt;
  final String createdBy;

  Course({
    required this.id,
    required this.title,
    required this.route,
    required this.turns,
    required this.isPublic,
    required this.createdAt,
    required this.createdBy,
  });

  factory Course.fromJson(String id, Map<String, dynamic> json) {
    return Course(
      id: id,
      title: json['title'],
      route:
          (json['route'] as List).map((e) => LatLngPoint.fromJson(e)).toList(),
      turns:
          (json['turns'] as List).map((e) => CourseTurn.fromJson(e)).toList(),
      isPublic: json['isPublic'] ?? true,
      createdAt: DateTime.parse(json['createdAt']),
      createdBy: json['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'route': route.map((e) => e.toJson()).toList(),
      'turns': turns.map((e) => e.toJson()).toList(),
      'isPublic': isPublic,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
    };
  }
}
