import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// ------------------------------
/// 경로 포인트 모델
/// ------------------------------
class LatLngPoint {
  final double lat;
  final double lng;

  LatLngPoint(this.lat, this.lng);
}

/// ------------------------------
/// Provider: 러닝 상태관리
/// ------------------------------
class RunningProvider extends ChangeNotifier {
  int _seconds = 0;
  Timer? _timer;

  bool _isRunning = false;

  StreamSubscription<Position>? _positionSub;

  final List<LatLngPoint> _route = [];
  double _distanceMeters = 0.0;

  int get seconds => _seconds;
  bool get isRunning => _isRunning;

  List<LatLngPoint> get route => List.unmodifiable(_route);
  double get distanceKm => _distanceMeters / 1000.0;

  // -------------------------
  // 위치 권한 확인
  // -------------------------
  Future<bool> _checkPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('❌ 위치 서비스(GPS)가 꺼져 있습니다.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      print('❌ 위치 권한이 거부되었습니다.');
      return false;
    }

    return true;
  }

  // -------------------------
  // 테스트용: 현재 위치 1회 가져오기
  // -------------------------
  Future<void> getCurrentLocationOnce() async {
    try {
      final ok = await _checkPermission();
      if (!ok) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      print('📍 현재 위치: ${pos.latitude}, ${pos.longitude}');
    } catch (e) {
      print('위치 가져오기 오류: $e');
    }
  }

  // -------------------------
  // 러닝 시작
  // -------------------------
  Future<void> start() async {
    if (_isRunning) return;

    final ok = await _checkPermission();
    if (!ok) return;

    _isRunning = true;
    notifyListeners();

    // 1) 타이머 시작
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;
      notifyListeners();
    });

    // 2) 위치 스트림 구독 시작
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best, // 최고 정확도
        distanceFilter: 5, // 5m 움직여야 이벤트 발생
      ),
    ).listen((Position pos) {
      _handleNewPosition(pos);
    });
  }

  // -------------------------
  // 새로운 위치 처리
  // -------------------------
  void _handleNewPosition(Position pos) {
    print(pos.speed);
    final newPoint = LatLngPoint(pos.latitude, pos.longitude);

    if (_route.isNotEmpty) {
      final last = _route.last;

      final double segment = Geolocator.distanceBetween(
        last.lat,
        last.lng,
        newPoint.lat,
        newPoint.lng,
      );

      // GPS 튐 방지: 0~30m 범위만 반영
      if (segment > 0 && segment < 30) {
        _distanceMeters += segment;
      } else {
        print("⚠️ GPS 튐 감지: $segment m → 무시됨");
      }
    }

    _route.add(newPoint);

    print("📍 위치 업데이트: ${newPoint.lat}, ${newPoint.lng}");
    print("📏 총 거리(m): $_distanceMeters");
    print("📌 저장된 포인트: ${_route.length}");

    notifyListeners();
  }

  // -------------------------
  // 정지
  // -------------------------
  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _positionSub?.cancel();
    notifyListeners();
  }

  // -------------------------
  // 리셋
  // -------------------------
  void reset() {
    stop();
    _seconds = 0;
    _route.clear();
    _distanceMeters = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }
}
