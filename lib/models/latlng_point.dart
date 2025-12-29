class LatLngPoint {
  final double lat;
  final double lng;
  final double altitude; // 고도(m)

  LatLngPoint({required this.lat, required this.lng, required this.altitude});

  Map<String, dynamic> toJson() {
    return {"lat": lat, "lng": lng, "altitude": altitude};
  }

  factory LatLngPoint.fromJson(Map<String, dynamic> json) {
    return LatLngPoint(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      altitude: (json['altitude'] as num).toDouble(),
    );
  }
}
