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

enum HudNavState {
  inactive, // 코스 근처 아님 → HUD 숨김
  onCourse, // 정상 안내
  offCourse, // 코스 이탈
  lapDone, // 랩 완료 순간 (트랙)
  wrongWay, // 🔥 추가
}

enum TurnAnnounceStage { none, approaching50, approaching20, immediate, passed }

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

  TurnAnnounceState? _turnAnnounceState;

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

  // 🔁 Track (repeat) mode
  int _currentLap = 1;
  int get currentLap => _currentLap;

  int? _targetLapCount; // optional (설정 안 하면 무한)
  int? get targetLapCount => _targetLapCount;

  bool _isLapDone = false;
  bool get isLapDone => _isLapDone;

  // 이 바퀴 기준 진행률 (0.0 ~ 1.0)
  double _lapProgress = 0.0;
  double get lapProgress => _lapProgress;

  // 🔥 캐시용 (한 바퀴 길이)
  double? _lapLengthMeters;

  // 🔥 wrongWay 상태
  // 방향이 완전히 반대일 때 진입
  bool _isWrongWay = false;
  bool get isWrongWay => _isWrongWay;

  // 사용자의 현재 바라보는 방향 (degrees)
  double? _userBearing;
  double? get userBearing => _userBearing;

  // HUD 시작 index (중간 시작 & 루프용)
  int _hudStartCourseIndex = 0;

  static const int autoPauseSeconds = 10; // 10초

  HudNavState _hudNavState = HudNavState.inactive;

  HudNavState get hudNavState => _hudNavState;
  int _wrongWayRecoverCount = 0;

  HudNavState? _lastSpokenHudState;
  TurnAnnounceStage? _lastSpokenTurnStage;

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

  //  ============================================================
  //  오프코스 화살표 회전 (radians)
  //  ============================================================
  double? get offCourseArrowRotationRad {
    //  🔥 오프코스 복귀 방향 사용
    if (_userBearing == null || offCourseRecoveryBearing == null) return null;

    double diff = offCourseRecoveryBearing! - _userBearing!;

    // -180 ~ 180 정규화
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    //    // degrees to radians 변환
    return diff * pi / 180;
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  //  ============================================================
  //  HUD 네비게이션 상태 (외부용)
  //  ============================================================
  HudNavState get effectiveHudState {
    if (_hudNavState == HudNavState.wrongWay) {
      return HudNavState.wrongWay;
    }

    if (_hudNavState == HudNavState.offCourse) {
      return HudNavState.offCourse;
    }

    if (_hudNavState == HudNavState.lapDone) {
      return HudNavState.lapDone;
    }

    if (_hudNavState == HudNavState.onCourse) {
      return HudNavState.onCourse;
    }

    return HudNavState.inactive;
  }
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

    // 📐 사용자 진행 방향(bearing) 계산
    if (_route.length >= 2) {
      final prev = _route[_route.length - 2];
      final curr = _route.last;

      _userBearing = calculateBearing(prev, curr);
    }

    // 🔥 wrongWay 판단
    final distanceToCourse = _distanceToNearestCoursePoint(pos);

    if (_currentCourse != null &&
        _route.length >= 2 &&
        _currentCourseIndex < _currentCourse!.route.length - 1) {
      final userPrev = _route[_route.length - 2];
      final userCurr = _route.last;

      final courseA = _currentCourse!.route[_currentCourseIndex];
      final courseB = _currentCourse!.route[_currentCourseIndex + 1];

      final dot = _calculateDirectionDotProduct(
        userPrev,
        userCurr,
        courseA,
        courseB,
      );

      // ---------------------------------------------
      // 1️⃣ wrongWay 진입 판단 (아직 wrongWay가 아닐 때만)
      // ---------------------------------------------
      if (!_isWrongWay &&
          dot < -0.3 && // 방향이 명확히 반대
          distanceToCourse < 30) {
        // 코스 근처일 때만
        _isWrongWay = true;
        _wrongWayRecoverCount = 0;
        _hudNavState = HudNavState.wrongWay;
        _onHudStateChanged(_hudNavState);
        // NOTE: notifyListeners()는 handleNewPosition() 말미에서 일괄 호출
        //notifyListeners();
      }
      // ---------------------------------------------
      // 2️⃣ wrongWay 복귀 판단 (wrongWay 상태일 때만)
      // ---------------------------------------------
      else if (_isWrongWay) {
        if (dot > 0.3 && distanceToCourse < 20) {
          _wrongWayRecoverCount++;

          if (_wrongWayRecoverCount >= 3) {
            _isWrongWay = false;
            _wrongWayRecoverCount = 0;
            _hudNavState = HudNavState.onCourse;
            _onHudStateChanged(_hudNavState);
            // NOTE: notifyListeners()는 handleNewPosition() 말미에서 일괄 호출
            //notifyListeners();
          }
        } else {
          // 조건이 깨지면 카운트 리셋
          _wrongWayRecoverCount = 0;
        }
      }
    }

    // 🔥 코스 진행 업데이트 (이게 엔진이다)
    // NOTE: wrongWay 상태에서는 코스 진행률을 업데이트하지 않음
    // NOTE: wrongWay 상태에서는 HUD 상태 머신 자동 전환 금지
    if (_currentCourse != null && _hudNavState != HudNavState.wrongWay) {
      _updateCourseProgress(newPoint);
    }

    // 🔥 회전 안내
    final distance = hudDistanceToNextTurnM;
    if (distance != null) {
      _updateTurnAnnounce(distance);
    }

    // 🔥 HUD 상태
    //final distanceToCourse = _distanceToNearestCoursePoint(pos);
    _updateHudNavState(distanceToCourse);

    notifyListeners();
  }

  /* ============================================================
     내부 헬퍼
     ============================================================ */

  //  ============================================================
  //  코스 상에서 가장 가까운 지점까지의 거리 (meters)
  //  ============================================================
  double _distancePointToSegment(LatLngPoint p, LatLngPoint a, LatLngPoint b) {
    final px = p.lat;
    final py = p.lng;
    final ax = a.lat;
    final ay = a.lng;
    final bx = b.lat;
    final by = b.lng;

    final abx = bx - ax;
    final aby = by - ay;
    final apx = px - ax;
    final apy = py - ay;

    final abLenSq = abx * abx + aby * aby;
    if (abLenSq == 0) {
      return Geolocator.distanceBetween(px, py, ax, ay);
    }

    final t = (apx * abx + apy * aby) / abLenSq;
    final clampedT = t.clamp(0.0, 1.0);

    final closestX = ax + clampedT * abx;
    final closestY = ay + clampedT * aby;

    return Geolocator.distanceBetween(px, py, closestX, closestY);
  }

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
    _hudNavState = HudNavState.onCourse;
    _currentCourse = course;

    // 🔥 중간 시작 대응
    _hudStartCourseIndex = _findNearestRouteIndex();
    _currentCourseIndex = _hudStartCourseIndex;
    _courseProgressMeters = calculateCourseLengthMeters(
      course.route.sublist(0, _hudStartCourseIndex),
    );

    // 🔁 트랙 초기화
    _currentLap = 1;
    _isLapDone = false;
    _lapProgress = 0;

    // 🔥 턴 안내 상태 초기화
    _turnAnnounceState =
        _nextTurn != null ? TurnAnnounceState(turn: _nextTurn!) : null;
    _lastSpokenTurnStage = null;
    notifyListeners();

    // 🔥 기존 러닝 시작 로직 재사용
    await start();
  }

  //  ============================================================
  //  코스 진행도 업데이트
  //  ============================================================
  void _updateCourseProgress(LatLngPoint current) {
    final courseRoute = _currentCourse!.route;
    if (_currentCourseIndex >= courseRoute.length - 1) return;

    final currPoint = courseRoute[_currentCourseIndex];
    final nextPoint = courseRoute[_currentCourseIndex + 1];

    final segmentLength = Geolocator.distanceBetween(
      currPoint.lat,
      currPoint.lng,
      nextPoint.lat,
      nextPoint.lng,
    );

    final distanceToNext = Geolocator.distanceBetween(
      current.lat,
      current.lng,
      nextPoint.lat,
      nextPoint.lng,
    );

    final progressedOnSegment = max(0, segmentLength - distanceToNext);

    // 🔥 핵심: segment 내부 진행 반영
    final newProgress =
        calculateCourseLengthMeters(
          courseRoute.sublist(0, _currentCourseIndex),
        ) +
        progressedOnSegment;

    _courseProgressMeters = newProgress;

    // 다음 포인트 도착 처리
    if (distanceToNext < 8) {
      _currentCourseIndex++;

      _nextTurn =
          _currentCourse!.turns
              .where((t) => t.routeIndex > _currentCourseIndex)
              .toList()
              .firstOrNull;

      // 🔥 회전 통과 처리
      _turnAnnounceState?.stage = TurnAnnounceStage.passed;
      _lastSpokenTurnStage = null;
    }

    _turnAnnounceState =
        _nextTurn != null ? TurnAnnounceState(turn: _nextTurn!) : null;

    if (_currentCourse!.loopMode == CourseLoopMode.repeat) {
      final lapLength = calculateCourseLengthMeters(_currentCourse!.route);

      if (lapLength > 0) {
        final progressedThisLap = _courseProgressMeters % lapLength;
        _lapProgress = (progressedThisLap / lapLength).clamp(0.0, 1.0);
        _lapLengthMeters ??= lapLength;

        // 🔁 랩 완료 감지
        if (_lapProgress >= 0.98 && !_isLapDone) {
          _isLapDone = true;
          _hudNavState = HudNavState.lapDone;
          _speak('$_currentLap 랩 완료', strongHaptic: true);
          //notifyListeners();

          HapticFeedback.mediumImpact();

          Future.delayed(const Duration(seconds: 1), () {
            _currentLap++;
            _isLapDone = false;
            _hudNavState = HudNavState.onCourse;
            //notifyListeners();
          });
        }
      }
    }
    // NOTE: notifyListeners는 handleNewPosition()에서 일괄 처리
    //notifyListeners();
  }

  double? get hudDistanceToNextTurnM {
    if (_currentCourse == null || _nextTurn == null) return null;

    final nextTurnDistance = _nextTurn!.distanceFromStart;
    final remaining = nextTurnDistance - _courseProgressMeters;

    if (remaining.isNaN || remaining.isInfinite) return null;
    return max(0, remaining);
  }

  double? get courseBearing {
    if (_currentCourse == null) return null;
    if (_currentCourseIndex >= _currentCourse!.route.length - 1) return null;

    final a = _currentCourse!.route[_currentCourseIndex];
    final b = _currentCourse!.route[_currentCourseIndex + 1];

    return calculateBearing(a, b);
  }

  //  ============================================================
  //  HUD 화살표 회전 (radians)
  //  ============================================================
  double? get hudArrowRotationRad {
    if (_userBearing == null) return null;

    final targetBearing = courseBearing;
    if (targetBearing == null) return null;

    double diff = targetBearing - _userBearing!;

    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    // 🔥 다음 회전 방향 보정 (onCourse만)
    if (_hudNavState == HudNavState.onCourse && _nextTurn != null) {
      diff += _turnBiasDeg(_nextTurn!.type, hudTurnStage);
    }
    return diff * pi / 180;
  }

  //  ============================================================
  //  회전 편향도 (degrees)   보정 각도 계산 함수 추가
  //  ============================================================
  double _turnBiasDeg(TurnType type, TurnAnnounceStage? stage) {
    final isImmediate = stage == TurnAnnounceStage.immediate;

    switch (type) {
      case TurnType.left:
        return isImmediate ? -60 : -30;
      case TurnType.right:
        return isImmediate ? 60 : 30;
      case TurnType.straight:
        return 0;
    }
  }

  //============================================================
  //    효과적인 HUD 화살표 회전 (외부용)
  //============================================================
  double? get effectiveHudArrowRotation {
    if (_hudNavState == HudNavState.wrongWay) {
      return pi; // U턴
    }

    if (_hudNavState == HudNavState.offCourse) {
      return offCourseArrowRotationRad ?? hudArrowRotationRad;
    }

    return hudArrowRotationRad;
  }

  double? get offCourseRecoveryBearing {
    if (_currentCourse == null) return null;

    final route = _currentCourse!.route;
    if (_currentCourseIndex >= route.length - 1) return null;
    if (_lastPosition == null) return null;

    final user = LatLngPoint(
      lat: _lastPosition!.latitude,
      lng: _lastPosition!.longitude,
      altitude: _lastPosition!.altitude,
    );

    double minDistance = double.infinity;
    int bestIndex = -1;

    // 🔥 "앞쪽 segment"만 탐색
    final start = _currentCourseIndex;
    final end = min(_currentCourseIndex + 5, route.length - 1);

    for (int i = start; i < end; i++) {
      final a = route[i];
      final b = route[i + 1];

      final d = _distancePointToSegment(user, a, b);
      if (d < minDistance) {
        minDistance = d;
        bestIndex = i;
      }
    }

    if (bestIndex == -1) return null;

    // 👉 선택된 forward segment의 방향
    final from = route[bestIndex];
    final to = route[bestIndex + 1];

    return calculateBearing(from, to); // degrees
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

  //  ============================================================
  //  HUD 사용 가능 여부
  //  ============================================================
  bool get hudAvailable {
    return _currentCourse != null && _status == RunningStatus.running;
  }

  TurnAnnounceStage? get hudTurnStage => _turnAnnounceState?.stage;
  /*
  void _updateTurnAnnounce(double distanceToTurn) {
    if (_turnAnnounceState == null) return;

    final state = _turnAnnounceState!;

    // 이미 지난 회전이면 무시
    if (state.stage == TurnAnnounceStage.passed) return;

    if (distanceToTurn <= 5 &&
        state.stage.index < TurnAnnounceStage.immediate.index) {
      state.stage = TurnAnnounceStage.immediate;
      _onImmediateTurn();
    } else if (distanceToTurn <= 20 &&
        state.stage.index < TurnAnnounceStage.approaching20.index) {
      state.stage = TurnAnnounceStage.approaching20;
      _onApproachingTurn(20);
    } else if (distanceToTurn <= 50 &&
        state.stage.index < TurnAnnounceStage.approaching50.index) {
      state.stage = TurnAnnounceStage.approaching50;
      _onApproachingTurn(50);
    }
  }
*/
  void _updateTurnAnnounce(double distanceToTurn) {
    if (_turnAnnounceState == null) return;

    final state = _turnAnnounceState!;

    // 이미 지난 회전이면 무시
    if (state.stage == TurnAnnounceStage.passed) return;

    // 🚨 즉시 회전 (최우선)
    if (distanceToTurn <= 5 &&
        state.stage.index < TurnAnnounceStage.immediate.index) {
      state.stage = TurnAnnounceStage.immediate;
      _onTurnStageChanged(state.stage);
      return;
    }

    // ⚠️ 20m 접근
    if (distanceToTurn <= 20 &&
        state.stage.index < TurnAnnounceStage.approaching20.index) {
      state.stage = TurnAnnounceStage.approaching20;
      _onTurnStageChanged(state.stage);
      return;
    }

    // ℹ️ 50m 접근 (UI만, TTS 없음)
    if (distanceToTurn <= 50 &&
        state.stage.index < TurnAnnounceStage.approaching50.index) {
      state.stage = TurnAnnounceStage.approaching50;
      // ❌ TTS 호출 없음
      return;
    }
  }
  /*
  void _onApproachingTurn(int meters) {
    debugPrint('➡️ ${meters}m 후 ${hudNextTurnLabel}');
    if (meters == 20) {
      _speak('20미터 후 ${hudNextTurnLabel}');
    } else if (meters == 50) {
      _speak('50미터 후 ${hudNextTurnLabel}');
    }
    // TODO: TTS / 햅틱
  }

  void _onImmediateTurn() {
    _speak('지금 ${hudNextTurnLabel}하세요', strongHaptic: true);    
    debugPrint('🚨 지금 ${hudNextTurnLabel}');
    // TODO: 강한 햅틱 + 음성
  }
  */

  //    ============================================================
  //    코스 상에서 가장 가까운 지점 인덱스 찾기
  //    ============================================================
  int _findNearestRouteIndex() {
    if (_currentCourse == null) return 0;
    final route = _currentCourse!.route;
    if (route.length < 2) return 0;
    if (_lastPosition == null) return 0;

    final px = _lastPosition!.latitude;
    final py = _lastPosition!.longitude;

    double minDistance = double.infinity;
    int nearestIndex = 0;

    for (int i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];

      final ax = a.lat;
      final ay = a.lng;
      final bx = b.lat;
      final by = b.lng;

      final abx = bx - ax;
      final aby = by - ay;
      final apx = px - ax;
      final apy = py - ay;

      final abLenSq = abx * abx + aby * aby;
      if (abLenSq == 0) continue;

      // projection 비율
      final t = (apx * abx + apy * aby) / abLenSq;

      double closestX;
      double closestY;

      if (t < 0) {
        closestX = ax;
        closestY = ay;
      } else if (t > 1) {
        closestX = bx;
        closestY = by;
      } else {
        closestX = ax + t * abx;
        closestY = ay + t * aby;
      }

      final dist = Geolocator.distanceBetween(px, py, closestX, closestY);

      if (dist < minDistance) {
        minDistance = dist;
        nearestIndex = i;
      }
    }

    // 안전 보정
    if (nearestIndex >= route.length - 1) {
      nearestIndex = route.length - 2;
    }

    return nearestIndex;
  }

  /*
  void _updateHudNavState(double distanceToCourse) {
    _hudNavState = HudNavState.offCourse;
    _onHudStateChanged(_hudNavState);
  }
  */
  void _updateHudNavState(double distanceToCourse) {
    // wrongWay는 최우선, 자동 변경 금지
    // NOTE: wrongWay 상태에서는 HUD 상태 머신 자동 전환 금지
    // (wrongWay 해제는 전용 로직에서만 처리)
    if (_hudNavState == HudNavState.wrongWay) {
      // 너무 멀어지면 offCourse로 강제 전환
      if (distanceToCourse > 50) {
        _isWrongWay = false;
        _wrongWayRecoverCount = 0;
        _hudNavState = HudNavState.offCourse;
        _onHudStateChanged(_hudNavState);
        notifyListeners();
      }
      return;
    }

    switch (_hudNavState) {
      case HudNavState.inactive:
        if (distanceToCourse < 30) {
          _hudNavState = HudNavState.onCourse;
          _onHudStateChanged(_hudNavState);
        }
        break;

      case HudNavState.onCourse:
        if (distanceToCourse > 40) {
          _hudNavState = HudNavState.offCourse;
          _onHudStateChanged(_hudNavState);
        }
        break;

      case HudNavState.offCourse:
        if (distanceToCourse < 20) {
          _reAlignCourseAfterRejoin();
          _hudNavState = HudNavState.onCourse;
          _onHudStateChanged(_hudNavState);
        }
        break;

      case HudNavState.lapDone:
        // 타이머로 복귀됨
        break;

      case HudNavState.wrongWay:
        break;
    }
  }

  double _distanceToNearestCoursePoint(Position pos) {
    if (_currentCourse == null) return double.infinity;

    double minDist = double.infinity;

    for (final p in _currentCourse!.route) {
      final d = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        p.lat,
        p.lng,
      );
      if (d < minDist) minDist = d;
    }

    return minDist;
  }

  void _reAlignCourseAfterRejoin() {
    if (_currentCourse == null) return;

    // 1️⃣ 가장 가까운 route index 재계산
    final newIndex = _findNearestRouteIndex();
    _currentCourseIndex = newIndex;

    // 2️⃣ 코스 진행 거리 재계산
    _courseProgressMeters = calculateCourseLengthMeters(
      _currentCourse!.route.sublist(0, newIndex),
    );

    // 3️⃣ 다음 회전 재설정
    _nextTurn =
        _currentCourse!.turns
            .where((t) => t.routeIndex > newIndex)
            .toList()
            .firstOrNull;

    // 4️⃣ 회전 안내 상태 리셋
    _turnAnnounceState =
        _nextTurn != null ? TurnAnnounceState(turn: _nextTurn!) : null;

    // 5️⃣ 트랙 러닝이면 lap 기준도 자연스럽게 이어짐
    // (_courseProgressMeters 기반 % lapLength 로 계산됨)
    _lastSpokenTurnStage = null;
    debugPrint('🔁 코스 복귀 → index=$newIndex');
  }

  double _calculateDirectionDotProduct(
    LatLngPoint from,
    LatLngPoint to,
    LatLngPoint courseA,
    LatLngPoint courseB,
  ) {
    // 사용자 이동 벡터
    final ux = to.lat - from.lat;
    final uy = to.lng - from.lng;

    // 코스 진행 벡터
    final cx = courseB.lat - courseA.lat;
    final cy = courseB.lng - courseA.lng;

    final uLen = sqrt(ux * ux + uy * uy);
    final cLen = sqrt(cx * cx + cy * cy);

    if (uLen == 0 || cLen == 0) return 0;

    return (ux * cx + uy * cy) / (uLen * cLen);
  }

  // 두 지점 간의 방위각 계산 (0~360도)
  double calculateBearing(LatLngPoint from, LatLngPoint to) {
    final lat1 = from.lat * pi / 180;
    final lat2 = to.lat * pi / 180;
    final dLon = (to.lng - from.lng) * pi / 180;

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    final bearingRad = atan2(y, x);
    final bearingDeg = (bearingRad * 180 / pi + 360) % 360;

    return bearingDeg; // 0~360
  }

  DateTime? _lastTtsTime;
  static const int _ttsCooldownSeconds = 4;

  bool _canSpeak() {
    if (_lastTtsTime == null) return true;
    return DateTime.now().difference(_lastTtsTime!).inSeconds >=
        _ttsCooldownSeconds;
  }

  Future<void> _speak(String text, {bool strongHaptic = false}) async {
    if (!_canSpeak()) return;

    _lastTtsTime = DateTime.now();

    if (strongHaptic) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }

    // 🔊 실제 TTS (flutter_tts 연결 시)
    debugPrint('🔊 TTS: $text');

    // TODO: flutter_tts.speak(text);
  }

  void _onHudStateChanged(HudNavState newState) {
    if (_lastSpokenHudState == newState) return;

    switch (newState) {
      case HudNavState.offCourse:
        _speak('코스를 이탈했습니다');
        break;

      case HudNavState.onCourse:
        _speak('코스로 복귀했습니다');
        break;

      case HudNavState.lapDone:
        _speak('$_currentLap 랩 완료', strongHaptic: true);
        break;

      case HudNavState.wrongWay:
        _speak('역방향입니다. 방향을 돌려주세요', strongHaptic: true);
        break;

      default:
        break;
    }

    _lastSpokenHudState = newState;
  }

  void _onTurnStageChanged(TurnAnnounceStage stage) {
    // 🔒 같은 단계는 다시 말하지 않음
    if (_lastSpokenTurnStage == stage) return;

    switch (stage) {
      case TurnAnnounceStage.approaching20:
        _speak('20미터 후 ${hudNextTurnLabel}');
        break;

      case TurnAnnounceStage.immediate:
        _speak('지금 ${hudNextTurnLabel}하세요', strongHaptic: true);
        break;

      default:
        break;
    }

    _lastSpokenTurnStage = stage;
  }
}

class TurnAnnounceState {
  final CourseTurn turn;
  TurnAnnounceStage stage;

  TurnAnnounceState({required this.turn, this.stage = TurnAnnounceStage.none});
}
