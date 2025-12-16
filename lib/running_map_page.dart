import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'running_provider.dart';

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
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 16,
          onMapReady: () {
            // 위치가 갱신될 때마다 지도 중심 이동
            if (points.isNotEmpty) {
              mapController.move(points.last, 16);
            }
          },
        ),
        children: [
          /// 🗺️ OpenStreetMap 타일 레이어
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: "com.example.app",
          ),

          /// 📍 경로 Polyline
          PolylineLayer(
            polylines: [
              Polyline(points: points, strokeWidth: 4, color: Colors.blue),
            ],
          ),

          /// 🔵 현재 위치를 표시하는 마커
          if (points.isNotEmpty)
            MarkerLayer(
              markers: [
                Marker(
                  width: 40,
                  height: 40,
                  point: points.last,
                  child: const Icon(Icons.circle, color: Colors.red, size: 18),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
