import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/run_record.dart';
import '../models/run_metric_point.dart';
import 'widgets/pace_altitude_chart.dart';

import '../services/course_draft_factory.dart';
import '../models/course_draft.dart';
import '../pages/course/course_draft_preview_page.dart'; // ⭐ 이 줄 추가

class RunDetailPage extends StatelessWidget {
  final RunRecord record;

  const RunDetailPage({super.key, required this.record});

  List<LatLng> get _latLngRoute =>
      record.route.map((p) => LatLng(p.lat, p.lng)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('러닝 상세')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _MapCard(route: _latLngRoute),
            const SizedBox(height: 16),
            _SummaryCard(record: record),
            const SizedBox(height: 16),
            _ChartCard(metrics: record.metrics),
            const SizedBox(height: 24),

            // ⭐⭐⭐ 여기 추가 ⭐⭐⭐
            _ShareCourseButton(record: record),
          ],
        ),
      ),
    );
  }
}
//  =============================================================
//🗺 코스 공유 버튼
//============================================================

class _ShareCourseButton extends StatelessWidget {
  final RunRecord record;

  const _ShareCourseButton({required this.record});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.share),
        label: const Text('이 러닝을 코스로 공유하기', style: TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () {
          // ⭐ RunRecord → CourseDraft 변환
          final draft = createCourseDraft(record);

          // 다음 화면으로 이동 (미리보기)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => CourseDraftPreviewPage(original: record, draft: draft),
            ),
          );
        },
      ),
    );
  }
}

/* ============================================================
   🗺 지도 카드
   ============================================================ */

class _MapCard extends StatelessWidget {
  final List<LatLng> route;

  const _MapCard({required this.route});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 260,
        child:
            route.isEmpty
                ? const Center(child: Text('경로 데이터 없음'))
                : FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(route),
                      padding: const EdgeInsets.all(40),
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.running',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: route,
                          strokeWidth: 4,
                          color: Colors.blueAccent,
                        ),
                      ],
                    ),
                  ],
                ),
      ),
    );
  }
}

/* ============================================================
   📊 요약 카드
   ============================================================ */

class _SummaryCard extends StatelessWidget {
  final RunRecord record;

  const _SummaryCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(
              label: '거리',
              value: '${(record.distanceMeters / 1000).toStringAsFixed(2)}',
              unit: 'km',
            ),
            _StatItem(
              label: '시간',
              value: _formatTime(record.durationSeconds),
              unit: '',
            ),
            _StatItem(
              label: '평균 페이스',
              value: _formatPace(record.averagePaceSec),
              unit: '/km',
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   📈 그래프 카드
   ============================================================ */

class _ChartCard extends StatelessWidget {
  final List<RunMetricPoint> metrics;

  const _ChartCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: PaceAltitudeChart(metrics: metrics),
      ),
    );
  }
}

/* ============================================================
   🔢 공용 위젯 / 포맷
   ============================================================ */

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _StatItem({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            if (unit.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  unit,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String _formatTime(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _formatPace(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  return '${m}\'${s.toString().padLeft(2, '0')}\"';
}
