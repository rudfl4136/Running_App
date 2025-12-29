import 'dart:math';
import '../models/latlng_point.dart';

List<LatLngPoint> simplifyRoute(
  List<LatLngPoint> points, {
  double angleThreshold = 5, // degrees
}) {
  if (points.length < 3) return points;

  final result = <LatLngPoint>[points.first];

  for (int i = 1; i < points.length - 1; i++) {
    final prev = points[i - 1];
    final curr = points[i];
    final next = points[i + 1];

    final angle = _angleBetween(prev, curr, next);

    if (angle.abs() >= angleThreshold) {
      result.add(curr);
    }
  }

  result.add(points.last);
  return result;
}

double _angleBetween(LatLngPoint a, LatLngPoint b, LatLngPoint c) {
  final abx = b.lat - a.lat;
  final aby = b.lng - a.lng;
  final bcx = c.lat - b.lat;
  final bcy = c.lng - b.lng;

  final dot = abx * bcx + aby * bcy;
  final mag1 = sqrt(abx * abx + aby * aby);
  final mag2 = sqrt(bcx * bcx + bcy * bcy);

  if (mag1 == 0 || mag2 == 0) return 0;

  final cos = dot / (mag1 * mag2);
  final rad = acos(cos.clamp(-1.0, 1.0));
  return rad * 180 / pi;
}
