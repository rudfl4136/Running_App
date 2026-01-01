import 'latlng_point.dart';
import 'course_turn.dart';

enum CourseLoopMode {
  single, // 기본: 1사이클만 안내
  repeat, // 반복 러닝 (트랙)
}

class Course {
  final String id;
  final String title;
  final List<LatLngPoint> route;
  final List<CourseTurn> turns;
  final bool isPublic;
  final DateTime createdAt;
  final String createdBy;

  /// 🔥 추가
  final CourseLoopMode loopMode;

  Course({
    required this.id,
    required this.title,
    required this.route,
    required this.turns,
    required this.isPublic,
    required this.createdAt,
    required this.createdBy,

    /// 🔥 기본값 중요
    this.loopMode = CourseLoopMode.single,
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

      /// 🔥 핵심: 기존 데이터 호환
      loopMode: CourseLoopMode.values.firstWhere(
        (e) => e.name == json['loopMode'],
        orElse: () => CourseLoopMode.single,
      ),
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

      /// 🔥 추가
      'loopMode': loopMode.name, // 'single' | 'repeat'
    };
  }
}
