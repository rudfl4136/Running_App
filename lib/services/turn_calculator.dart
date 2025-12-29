import 'dart:math';
import '../models/latlng_point.dart';
import '../models/course_turn.dart';
import 'package:geolocator/geolocator.dart';

List<CourseTurn> calculateTurns(
  List<LatLngPoint> route, {
  double minTurnAngle = 30, // degrees
}) {
  if (route.length < 3) return [];

  final turns = <CourseTurn>[];
  double distanceFromStart = 0;

  for (int i = 1; i < route.length - 1; i++) {
    final prev = route[i - 1];
    final curr = route[i];
    final next = route[i + 1];

    // 누적 거리 계산
    distanceFromStart += Geolocator.distanceBetween(
      prev.lat,
      prev.lng,
      curr.lat,
      curr.lng,
    );

    final angle = _signedAngle(prev, curr, next);

    if (angle.abs() < minTurnAngle) continue;

    final type = angle > 0 ? TurnType.right : TurnType.left;

    turns.add(
      CourseTurn(
        type: type,
        distanceFromStart: distanceFromStart,
        routeIndex: i,
      ),
    );
  }

  return turns;
}

double _signedAngle(LatLngPoint a, LatLngPoint b, LatLngPoint c) {
  final abx = b.lat - a.lat;
  final aby = b.lng - a.lng;
  final bcx = c.lat - b.lat;
  final bcy = c.lng - b.lng;

  final dot = abx * bcx + aby * bcy;
  final cross = abx * bcy - aby * bcx;

  final mag1 = sqrt(abx * abx + aby * aby);
  final mag2 = sqrt(bcx * bcx + bcy * bcy);

  if (mag1 == 0 || mag2 == 0) return 0;

  final cos = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
  final angle = acos(cos) * 180 / pi;

  // cross의 부호로 좌/우 판별
  return cross >= 0 ? angle : -angle;
}
