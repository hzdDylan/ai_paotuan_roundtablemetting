import '../../engine/director/director.dart';
import '../../engine/rules/character_rules.dart';
import '../../engine/rules/character_sheet.dart';
import '../../engine/scenario/bp_names.dart';
import '../../engine/scenario/scenario.dart';
import 'session_config.dart';

/// 一局开始时的静态快照。
class SessionBootstrapped {
  const SessionBootstrapped({
    required this.scenario,
    required this.scene,
    required this.participants,
    required this.bpNames,
  });

  final Scenario scenario;
  final SceneDef scene;
  final List<ActorRef> participants;
  final List<String> bpNames;

  int get partySize => scenario.partySize;
}

/// 开局装配：裁剪 BP、命名、构建 ActorRef。纯计算。
final class SessionBootstrap {
  const SessionBootstrap();

  SessionBootstrapped build({
    required Scenario scenario,
    required CharacterSheet character,
    required SessionConfig config,
  }) {
    final configured = _withConfiguredBp(scenario, config, character);
    return SessionBootstrapped(
      scenario: configured,
      scene: configured.scenes.first,
      participants: _buildParticipants(configured, character),
      bpNames: configured.bpActors.map((actor) => actor.name).toList(),
    );
  }

  Scenario _withConfiguredBp(
    Scenario scenario,
    SessionConfig config,
    CharacterSheet character,
  ) {
    final poolSize = scenario.bpActors.length;
    final maxByParty = scenario.partyMax - 1 - scenario.npcs.length;
    final limit = poolSize < maxByParty ? poolSize : maxByParty;
    final count = config.bpCount.clamp(1, limit < 1 ? 1 : limit);

    // 名字语言跟随玩家：中文玩家配中文名，其余配英文名。
    final fallback = pickBpNames(count, playerName: character.name);
    final names = <String>[
      for (var i = 0; i < count; i++)
        i < config.bpNames.length && config.bpNames[i].trim().isNotEmpty
            ? config.bpNames[i].trim()
            : fallback[i],
    ];

    var index = 0;
    final actors = <ScenarioActor>[];
    for (final actor in scenario.actors) {
      if (actor.kind != ActorKindRef.bp) {
        actors.add(actor);
        continue;
      }
      if (index >= count) continue;
      actors.add(
        ScenarioActor(
          id: actor.id,
          kind: actor.kind,
          name: names[index],
          goal: actor.goal,
          secret: actor.secret,
          tags: actor.tags,
          quip: actor.quip,
          switchTrigger: actor.switchTrigger,
        ),
      );
      index++;
    }

    return Scenario(
      id: scenario.id,
      version: scenario.version,
      title: scenario.title,
      subtitle: scenario.subtitle,
      minutes: scenario.minutes,
      rating: scenario.rating,
      partyMax: scenario.partyMax,
      opening: scenario.opening,
      contentScope: scenario.contentScope,
      actors: actors,
      npcs: scenario.npcs,
      scenes: scenario.scenes,
    );
  }

  List<ActorRef> _buildParticipants(
    Scenario scenario,
    CharacterSheet character,
  ) {
    final actorRefs = <ActorRef>[
      ActorRef(
        id: 'human',
        name: character.name.isEmpty ? '你' : character.name,
        kind: ActorKind.human,
        tags: <String>{
          for (final skill in Skill.values)
            if (skill.isAllocatable) skill.label,
        },
      ),
    ];
    for (final actor in scenario.actors) {
      if (actor.kind != ActorKindRef.bp) continue;
      actorRefs.add(
        ActorRef(
          id: actor.id,
          name: actor.name,
          kind: ActorKind.bp,
          tags: actor.tags,
        ),
      );
    }
    for (final npc in scenario.npcs) {
      actorRefs.add(
        ActorRef(
          id: npc.id,
          name: npc.name,
          kind: ActorKind.npc,
          tags: npc.tags,
        ),
      );
    }
    return actorRefs;
  }
}
