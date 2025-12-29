enum TurnType { left, right, straight }

class CourseTurn {
  final TurnType type;
  final double distanceFromStart; // meters
  final int routeIndex; // 디버깅 / HUD 계산용

  CourseTurn({
    required this.type,
    required this.distanceFromStart,
    required this.routeIndex,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'distanceFromStart': distanceFromStart,
      'routeIndex': routeIndex,
    };
  }

  factory CourseTurn.fromJson(Map<String, dynamic> json) {
    return CourseTurn(
      type: TurnType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TurnType.straight,
      ),
      distanceFromStart: (json['distanceFromStart'] as num).toDouble(),
      routeIndex: json['routeIndex'] as int,
    );
  }
}
