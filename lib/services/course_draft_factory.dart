import '../models/run_record.dart';
import '../models/course_draft.dart';
import 'route_filter.dart';
import 'route_simplifier.dart';
import 'route_outlier_filter.dart';
import 'turn_calculator.dart';

CourseDraft createCourseDraft(RunRecord record) {
  final step1 = removeNoise(record.route);
  final step2 = removeDirectionOutliers(step1);
  final step3 = simplifyRoute(step2);

  final turns = calculateTurns(step3);

  return CourseDraft(route: step3, turns: turns);
}
