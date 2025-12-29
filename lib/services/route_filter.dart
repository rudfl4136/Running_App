import 'package:geolocator/geolocator.dart';
import '../models/latlng_point.dart';

List<LatLngPoint> removeNoise(List<LatLngPoint> raw) {
  if (raw.length < 2) return raw;

  final result = <LatLngPoint>[];
  LatLngPoint? last;

  for (final p in raw) {
    if (last == null) {
      result.add(p);
      last = p;
      continue;
    }

    final distance = Geolocator.distanceBetween(
      last.lat,
      last.lng,
      p.lat,
      p.lng,
    );

    if (distance >= 5) {
      result.add(p);
      last = p;
    }
  }

  return result;
}
