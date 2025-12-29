import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import '../models/latlng_point.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/run_record.dart';
import '../models/run_metric_point.dart';
import '../../models/finish_response.dart';
import 'dart:math';
import '../models/course.dart';
import '../models/course_turn.dart';
import '../utils/course_metrics.dart';

/* ============================================================
   🏃 러닝 상태 enum
   ============================================================ */

enum RunningStatus {
  idle, // 시작 전
  running, // 러닝 중
  paused, // 일시정지
  finished, // 종료됨
}

/* ============================================================
   🏃 RunningProvider
   ============================================================ */
class RunningProvider extends ChangeNotifier {
  /* ---------- 코스 러닝 상태 ---------- */

  Course? _currentCourse;
  Course? get currentCourse => _currentCourse;

  bool get isCourseRunning => _currentCourse != null;

  // HUD 계산용
  int _currentCourseIndex = 0; // 내가 지금까지 온 코스 route index
  int get currentCourseIndex => _currentCourseIndex;

  double _courseProgressMeters = 0; // 코스 상에서 이동한 거리
  double get courseProgressKm => _courseProgressMeters / 1000;

  CourseTurn? _nextTurn;
  CourseTurn? get nextTurn => _nextTurn;

  /* ---------- 상태 ---------- */
  RunningStatus _status = RunningStatus.idle;
  RunningStatus get status => _status;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  bool _autoPaused = false;
  bool get autoPaused => _autoPaused;

  int _seconds = 0;
  int get seconds => _seconds;

  Timer? _timer;
  StreamSubscription<Position>? _positionSub;

  // 자동 일시정지 관련
  Position? _lastPosition;
  Timer? _gpsSilenceWatcher;
  DateTime? _lastPositionTime;

  static const int autoPauseSeconds = 10; // 10초

  /* ---------- 데이터 ---------- */

  final List<LatLngPoint> _route = [];
  List<LatLngPoint> get route => List.unmodifiable(_route);

  final List<RunMetricPoint> _metrics = [];
  List<RunMetricPoint> get metrics => List.unmodifiable(_metrics);

  double _distanceMeters = 0.0;
  double get distanceKm => _distanceMeters / 1000.0;

  double _displayDistanceMeters = 0.0;
  double get displayDistanceKm => _displayDistanceMeters / 1000;

  double get averagePaceSec {
    if (_distanceMeters <= 0 || _seconds <= 0) return 0;
    final pace = _seconds / (_distanceMeters / 1000);
    if (pace.isNaN || pace.isInfinite) return 0;
    return pace;
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /* ============================================================
     권한 체크
     ============================================================ */

  Future<bool> _checkPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  /* ============================================================
     러닝 시작
     ============================================================ */

  Future<void> start() async {
    //  이미 러닝 중이면 무시
    if (_status != RunningStatus.idle) return;

    final ok = await _checkPermission();
    if (!ok) return;

    _lastPosition = null;
    _lastPositionTime = DateTime.now(); // 🔥 중요

    _autoPaused = false;
    _status = RunningStatus.running;
    notifyListeners();

    _startTimer();
    _startLocationStream();
    _startAutoPauseWatcher();
  }

  //  ============================================================
  //  자동 일시정지 감시자 시작
  //  ============================================================
  void _startAutoPauseWatcher() {
    _gpsSilenceWatcher?.cancel();

    _gpsSilenceWatcher = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status != RunningStatus.running) return;
      if (_lastPositionTime == null) return;

      final diff = DateTime.now().difference(_lastPositionTime!).inSeconds;

      if (diff >= autoPauseSeconds) {
        debugPrint('⏸ 자동 일시정지 (GPS 무응답)');
        pause(auto: true);
      }
    });
  }

  /* ============================================================
     일시정지
     ============================================================ */

  void pause({bool auto = false}) {
    if (_status != RunningStatus.running) return;

    _timer?.cancel();
    _timer = null;

    _positionSub?.cancel();
    _positionSub = null;

    _gpsSilenceWatcher?.cancel();
    _gpsSilenceWatcher = null;

    _autoPaused = auto; // 🔥 핵심
    _status = RunningStatus.paused;

    HapticFeedback.mediumImpact();
    _displayDistanceMeters = _distanceMeters; // ⭐ 싱크
    debugPrint(auto ? '⏸ 자동 일시정지' : '⏸ 수동 일시정지');
    notifyListeners();
  }

  /* ============================================================
     재개
     ============================================================ */

  void resume() {
    if (_status != RunningStatus.paused) return;

    _autoPaused = false; // 🔥 중요

    _lastPosition = null;
    _lastPositionTime = DateTime.now();

    _startTimer();
    _startLocationStream();
    _startAutoPauseWatcher();

    _status = RunningStatus.running;

    HapticFeedback.lightImpact();
    notifyListeners();
  }
  /* ============================================================
    종료 + 저장
    ============================================================ */

  Future<FinishResponse> finish() async {
    // 🔥 코스 러닝 관련 초기화
    _currentCourse = null;
    _currentCourseIndex = 0;
    _courseProgressMeters = 0;
    _nextTurn = null;

    //  이미 종료되었거나 저장 중이면 무시
    if (_isSaving || _status == RunningStatus.finished) {
      return const FinishResponse(result: FinishResult.saveFailed);
    }

    if (_route.isEmpty || _distanceMeters <= 0) {
      return const FinishResponse(result: FinishResult.noData);
    }

    _gpsSilenceWatcher?.cancel();
    _gpsSilenceWatcher = null;
    _stopInternal();
    _status = RunningStatus.finished;

    HapticFeedback.heavyImpact();
    notifyListeners();

    try {
      final record = await _saveRun();
      return FinishResponse(result: FinishResult.success, record: record);
    } catch (_) {
      return const FinishResponse(result: FinishResult.saveFailed);
    }
  }

  /* ============================================================
    GPS 위치 처리
    ============================================================ */

  void _handleNewPosition(Position pos) {
    // ⛔ 러닝 중이 아닐 때는 무시
    if (_status != RunningStatus.running) return;

    _lastPositionTime = DateTime.now();

    // 최초 위치
    if (_lastPosition == null) {
      _lastPosition = pos;
      return;
    }

    // 🔄 정상 이동 → 기존 로직 계속
    _lastPosition = pos;

    final newPoint = LatLngPoint(
      lat: pos.latitude,
      lng: pos.longitude,
      altitude: pos.altitude,
    );

    if (_route.isNotEmpty) {
      final last = _route.last;
      final segment = Geolocator.distanceBetween(
        last.lat,
        last.lng,
        newPoint.lat,
        newPoint.lng,
      );

      _distanceMeters += segment;
      final distanceKm = _distanceMeters / 1000;

      // 🔥 핵심: 페이스/고도 데이터 포인트 추가
      //  5m 이상 이동했을 때만 추가
      if (_seconds > 0 && _distanceMeters >= 0.005) {
        final paceSec = _seconds / distanceKm;
        if (!paceSec.isNaN && !paceSec.isInfinite) {
          _metrics.add(
            RunMetricPoint(
              distanceKm: distanceKm,
              paceSec: paceSec,
              altitude: pos.altitude,
            ),
          );
        }
      }
    }

    _route.add(newPoint);
    notifyListeners();

    if (_currentCourse != null) {
      _updateCourseProgress(newPoint);
    }
  }

  /* ============================================================
     내부 헬퍼
     ============================================================ */

  void _startTimer() {
    _timer?.cancel(); // 🔥 핵심
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;

      // 🔥 표시용 거리 보간
      if (_distanceMeters > _displayDistanceMeters) {
        final diff = _distanceMeters - _displayDistanceMeters;

        // 한 번에 다 따라잡지 않고 일부만 증가
        _displayDistanceMeters += min(diff, 1.2);
      }
      notifyListeners();
    });
  }

  //  ============================================================
  //  위치 스트림 시작
  //  ============================================================
  void _startLocationStream() {
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3, // 3미터 이상 이동 시에만 업데이트
      ),
    ).listen(_handleNewPosition);
  }

  void _stopInternal() {
    _timer?.cancel();
    _timer = null;

    _positionSub?.cancel();
    _positionSub = null;
  }

  /* ============================================================
     Firestore 저장
     ============================================================ */

  Future<RunRecord?> _saveRun() async {
    if (_route.isEmpty || _distanceMeters <= 0) return null;

    _isSaving = true;
    notifyListeners();

    final record = RunRecord(
      route: List.from(_route),
      distanceMeters: _distanceMeters,
      durationSeconds: _seconds,
      metrics: List.from(_metrics),
      averagePaceSec: averagePaceSec.round(),
      date: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc('temp_user') // 🔥 Auth 적용 시 uid로 변경
        .collection('running_records')
        .add(record.toJson());

    _isSaving = false;
    notifyListeners();

    // 저장후
    return record; // 🔥 핵심
  }

  /* ============================================================
     리셋
     ============================================================ */

  void reset() {
    _seconds = 0;
    _distanceMeters = 0;
    _route.clear();
    _metrics.clear();
    _gpsSilenceWatcher?.cancel();
    _gpsSilenceWatcher = null;
    _lastPositionTime = null;
    _status = RunningStatus.idle;
    _autoPaused = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    _gpsSilenceWatcher?.cancel(); // 추가하면 더 완벽
    super.dispose();
  }

  void startWithCourse(Course course) async {
    // 🔥 완전 초기화
    reset();

    // 🔥 코스 설정
    _currentCourse = course;
    _currentCourseIndex = 0;
    _courseProgressMeters = 0;
    _nextTurn = course.turns.isNotEmpty ? course.turns.first : null;

    notifyListeners();

    // 🔥 기존 러닝 시작 로직 재사용
    await start();
  }

  void _updateCourseProgress(LatLngPoint current) {
    final courseRoute = _currentCourse!.route;
    if (_currentCourseIndex >= courseRoute.length - 1) return;

    final target = courseRoute[_currentCourseIndex + 1];

    final dist = Geolocator.distanceBetween(
      current.lat,
      current.lng,
      target.lat,
      target.lng,
    );

    // 🔥 다음 포인트에 충분히 가까워졌으면
    if (dist < 10) {
      final prev = courseRoute[_currentCourseIndex];
      final segment = Geolocator.distanceBetween(
        prev.lat,
        prev.lng,
        target.lat,
        target.lng,
      );

      _courseProgressMeters += segment;
      _currentCourseIndex++;

      // 🔄 다음 회전 갱신
      _nextTurn = _currentCourse!.turns.firstWhere(
        (t) => t.routeIndex > _currentCourseIndex,
        orElse: () => _nextTurn!,
      );

      notifyListeners();
    }
  }

  double? get hudDistanceToNextTurnM {
    if (_currentCourse == null || _nextTurn == null) return null;

    final nextTurnDistance = _nextTurn!.distanceFromStart;
    final remaining = nextTurnDistance - _courseProgressMeters;

    if (remaining.isNaN || remaining.isInfinite) return null;
    return max(0, remaining);
  }

  String get hudNextTurnLabel {
    if (_nextTurn == null) return '';

    switch (_nextTurn!.type) {
      case TurnType.left:
        return '좌회전';
      case TurnType.right:
        return '우회전';
      case TurnType.straight:
        return '직진';
    }
  }

  double get hudCourseProgressRatio {
    if (_currentCourse == null) return 0;

    final totalMeters = calculateCourseLengthMeters(_currentCourse!.route);
    if (totalMeters <= 0) return 0;

    return (_courseProgressMeters / totalMeters).clamp(0.0, 1.0);
  }

  double get hudCourseTotalKm {
    if (_currentCourse == null) return 0;
    return calculateCourseLengthKm(_currentCourse!.route);
  }

  double get hudCourseRemainingKm {
    if (_currentCourse == null) return 0;
    final remaining = hudCourseTotalKm - (_courseProgressMeters / 1000);
    return max(0, remaining);
  }

  bool get hudIsCourseFinished {
    if (_currentCourse == null) return false;
    return _currentCourseIndex >= _currentCourse!.route.length - 1;
  }

  bool get hudAvailable {
    return _currentCourse != null && _status == RunningStatus.running;
  }
}
