import 'package:geolocator/geolocator.dart';
import '../models/latlng_point.dart';

/// 📏 코스 전체 길이 (km)
double calculateCourseLengthKm(List<LatLngPoint> route) {
  if (route.length < 2) return 0;

  double meters = 0;

  for (int i = 0; i < route.length - 1; i++) {
    meters += Geolocator.distanceBetween(
      route[i].lat,
      route[i].lng,
      route[i + 1].lat,
      route[i + 1].lng,
    );
  }

  return meters / 1000;
}

/// 📍 내 위치 → 코스 시작점 거리 (km)
double? calculateDistanceFromMeKm({
  required double myLat,
  required double myLng,
  required double startLat,
  required double startLng,
}) {
  final meters = Geolocator.distanceBetween(myLat, myLng, startLat, startLng);

  return meters / 1000;
}

double calculateCourseLengthMeters(List<LatLngPoint> route) {
  if (route.length < 2) return 0;

  double meters = 0;
  for (int i = 0; i < route.length - 1; i++) {
    meters += Geolocator.distanceBetween(
      route[i].lat,
      route[i].lng,
      route[i + 1].lat,
      route[i + 1].lng,
    );
  }
  return meters;
}
