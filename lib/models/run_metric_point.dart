class RunMetricPoint {
  final double distanceKm; // 누적 거리
  final double paceSec; // 초/km
  final double altitude; // m

  RunMetricPoint({
    required this.distanceKm,
    required this.paceSec,
    required this.altitude,
  });

  Map<String, dynamic> toJson() {
    return {'distanceKm': distanceKm, 'paceSec': paceSec, 'altitude': altitude};
  }

  factory RunMetricPoint.fromJson(Map<String, dynamic> json) {
    return RunMetricPoint(
      distanceKm: (json['distanceKm'] as num).toDouble(),
      paceSec: (json['paceSec'] as num).toDouble(),
      altitude: (json['altitude'] as num).toDouble(),
    );
  }
}
