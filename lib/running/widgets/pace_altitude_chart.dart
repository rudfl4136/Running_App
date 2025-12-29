import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/run_metric_point.dart';

class PaceAltitudeChart extends StatelessWidget {
  final List<RunMetricPoint> metrics;

  const PaceAltitudeChart({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    if (metrics.length < 2) {
      return const Center(child: Text('그래프 데이터 없음'));
    }

    final paceSpots =
        metrics
            .map(
              (m) => FlSpot(
                m.distanceKm,
                m.paceSec / 60, // 🔥 초 → 분
              ),
            )
            .toList();

    final altitudeSpots =
        metrics.map((m) => FlSpot(m.distanceKm, m.altitude)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📈 페이스 변화 (min/km)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 180, child: _buildChart(paceSpots, Colors.blue)),
        const SizedBox(height: 24),
        const Text(
          '⛰ 고도 변화 (m)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 180, child: _buildChart(altitudeSpots, Colors.green)),
      ],
    );
  }

  Widget _buildChart(List<FlSpot> spots, Color color) {
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.black87,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '거리 ${spot.x.toStringAsFixed(2)} km\n'
                  '값 ${spot.y.toStringAsFixed(1)}',
                  const TextStyle(color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
