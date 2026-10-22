import '../../engine/scenario/scenario.dart';

/// 剧本目录端口：应用层不关心资源来自 assets、文件还是网络。
abstract interface class ScenarioRepository {
  Future<List<Scenario>> loadCatalog();
}
