import 'package:flutter/services.dart' show rootBundle;

import '../../application/ports/scenario_repository.dart';
import '../../engine/scenario/scenario.dart';
import 'scenario_parser.dart';

/// 随包剧本目录（D-19 / D-20）。
final class AssetScenarioRepository implements ScenarioRepository {
  const AssetScenarioRepository({
    this.paths = const <String, String>{
      'dinner_hale': 'assets/scenarios/dinner_hale/scenario.yaml',
      'mist_dock': 'assets/scenarios/mist_dock/scenario.yaml',
      'paramount_last_dance':
          'assets/scenarios/paramount_last_dance/scenario.yaml',
      'xiafei_47': 'assets/scenarios/xiafei_47/scenario.yaml',
    },
  });

  final Map<String, String> paths;

  @override
  Future<List<Scenario>> loadCatalog() async {
    final loaded = await Future.wait(
      paths.values.map((path) async {
        final source = await rootBundle.loadString(path);
        return parseScenario(source);
      }),
    );
    return List<Scenario>.unmodifiable(loaded);
  }
}
