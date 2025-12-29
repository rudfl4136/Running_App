import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../running/running_provider.dart';
import '../../utils/course_metrics.dart';

class CourseDetailPage extends StatelessWidget {
  final Course course;

  const CourseDetailPage({super.key, required this.course});

  List<LatLng> get _route =>
      course.route.map((p) => LatLng(p.lat, p.lng)).toList();

  @override
  Widget build(BuildContext context) {
    final lengthKm = calculateCourseLengthKm(course.route);
    final turnCount = course.turns.length;

    return Scaffold(
      appBar: AppBar(title: Text(course.title)),
      body: Column(
        children: [
          // 🗺 지도
          SizedBox(
            height: 280,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(_route),
                  padding: const EdgeInsets.all(40),
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.running',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route,
                      strokeWidth: 5,
                      color: Colors.blueAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 📊 정보 영역
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.route,
                  label: '코스 길이',
                  value: '${lengthKm.toStringAsFixed(2)} km',
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.sync_alt,
                  label: '회전 수',
                  value: '$turnCount 회',
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.speed,
                  label: '난이도',
                  value: _difficultyLabel(turnCount, lengthKm),
                ),
              ],
            ),
          ),

          const Spacer(),

          // ▶️ 러닝 시작 버튼
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  final running = context.read<RunningProvider>();

                  running.startWithCourse(course);

                  Navigator.popUntil(context, (r) => r.isFirst);
                },
                child: const Text(
                  '이 코스로 러닝 시작',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 아주 단순한 난이도 기준 (임시)
  String _difficultyLabel(int turns, double km) {
    if (km < 3 && turns < 5) return '쉬움';
    if (km < 7 && turns < 12) return '보통';
    return '어려움';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
