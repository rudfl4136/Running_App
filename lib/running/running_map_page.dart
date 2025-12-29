import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'running_provider.dart';
import 'widgets/running_hud.dart';

class RunningMapPage extends StatelessWidget {
  const RunningMapPage({super.key});

  @override
  Widget build(BuildContext context) {
    final running = context.watch<RunningProvider>();

    // route -> LatLng 변환
    final List<LatLng> points =
        running.route.map((e) => LatLng(e.lat, e.lng)).toList();

    final mapController = MapController();

    // 최신 위치 (없으면 서울로 설정)
    LatLng center =
        points.isNotEmpty ? points.last : const LatLng(37.5665, 126.9780);

    return Scaffold(
      appBar: AppBar(title: const Text("실시간 경로 지도 (flutter_map)")),
      body: Stack(
        children: [
          /// 🗺 지도
          FlutterMap(
            mapController: mapController,
            options: MapOptions(initialCenter: center, initialZoom: 16),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: "com.example.app",
              ),

              PolylineLayer(
                polylines: [
                  Polyline(points: points, strokeWidth: 4, color: Colors.blue),
                ],
              ),

              if (points.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 40,
                      height: 40,
                      point: points.last,
                      child: const Icon(
                        Icons.circle,
                        color: Colors.red,
                        size: 18,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          /// 🚦 HUD (🔥 바로 여기!)
          if (running.hudAvailable)
            Positioned(
              top: 20,
              left: 16,
              right: 16,
              child: _HudOverlay(running: running),
            ),
        ],
      ),
    );
  }
}

class _HudOverlay extends StatelessWidget {
  final RunningProvider running;

  const _HudOverlay({required this.running});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(153),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${running.hudDistanceToNextTurnM?.toStringAsFixed(0)} m 후 '
            '${running.hudNextTurnLabel}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: running.hudCourseProgressRatio,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
          ),
        ],
      ),
    );
  }
}
