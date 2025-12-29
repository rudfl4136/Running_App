import 'package:cloud_firestore/cloud_firestore.dart';
import 'latlng_point.dart';
import 'run_metric_point.dart';

class RunRecord {
  final List<LatLngPoint> route;
  final double distanceMeters;
  final int durationSeconds;

  /// 🔥 핵심 데이터 (그래프 / HUD 공용)
  final List<RunMetricPoint> metrics;

  /// 🔥 평균 페이스 (초/km)
  final int averagePaceSec;

  final DateTime date;

  RunRecord({
    required this.route,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.metrics,
    required this.averagePaceSec,
    required this.date,
  });

  /* ===============================
     Firestore 저장
     =============================== */

  Map<String, dynamic> toJson() {
    return {
      'route': route.map((e) => e.toJson()).toList(),
      'distanceMeters': distanceMeters,
      'durationSeconds': durationSeconds,
      'metrics': metrics.map((e) => e.toJson()).toList(),
      'averagePaceSec': averagePaceSec,
      'date': Timestamp.fromDate(date),
    };
  }

  /* ===============================
     Firestore → Model
     =============================== */

  factory RunRecord.fromJson(Map<String, dynamic> json) {
    return RunRecord(
      route:
          (json['route'] as List? ?? [])
              .map((e) => LatLngPoint.fromJson(e))
              .toList(),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      metrics:
          (json['metrics'] as List? ?? [])
              .map((e) => RunMetricPoint.fromJson(e))
              .toList(),
      averagePaceSec: json['averagePaceSec'] as int? ?? 0,
      date: _parseDate(json['date']),
    );
  }

  /// 🔒 Date 안전 파싱
  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
