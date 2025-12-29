import 'course_turn.dart';
import 'latlng_point.dart';

class CourseDraft {
  final List<LatLngPoint> route;
  final List<CourseTurn> turns;

  CourseDraft({required this.route, required this.turns});
}
