import 'package:ai_paotuan_aroundmeeting/llm/schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析 2–4 条动作，并带技能或属性', () {
    final actions = parseActionSuggestions(<String, dynamic>{
      'actions': [
        {'text': '我走到门边，看走廊里有没有人', 'skill': '侦查'},
        {'text': '我把杯放下，直接问他', 'attribute': '意志'},
        {'text': '我压低声音，听门后的动静', 'skill': '聆听'},
      ],
    });
    expect(actions, hasLength(3));
    expect(actions[0].checkLabel, '侦查');
    expect(actions[1].checkLabel, '意志');
    expect(actions[2].checkLabel, '聆听');
  });

  test('只有 1 条也保留，别让玩家没得选', () {
    final actions = parseActionSuggestions(<String, dynamic>{
      'actions': [
        {'text': '我看着他', 'skill': '心理学'},
      ],
    });
    expect(actions, hasLength(1));
    expect(actions.single.checkLabel, '心理学');
  });

  test('超过 4 条只保留前 4 条', () {
    final actions = parseActionSuggestions(<String, dynamic>{
      'actions': [
        for (var i = 0; i < 6; i++) {'text': '动作$i', 'skill': '侦查'},
      ],
    });
    expect(actions, hasLength(4));
  });

  test('没有技能/属性的动作也保留；神话降级为无检定；禁语跳过', () {
    final actions = parseActionSuggestions(<String, dynamic>{
      'actions': [
        {'text': '没有依据的动作'},
        {'text': '我念一段咒', 'skill': '神话'},
        {'text': '作为AI，我建议你逃跑', 'skill': '话术'},
        {'text': '我观察门锁', 'skill': '侦查'},
        {'text': '我后退半步', 'attribute': '敏捷'},
      ],
    });
    expect(actions, hasLength(4));
    expect(actions[0].checkLabel, isEmpty);
    expect(actions[1].checkLabel, isEmpty);
    expect(actions[2].checkLabel, '侦查');
    expect(actions[3].checkLabel, '敏捷');
  });

  test('未知技能但属性合法时，用属性兜底', () {
    final actions = parseActionSuggestions(<String, dynamic>{
      'actions': [
        {'text': '我硬撑着不退', 'skill': '驾驶', 'attribute': '意志'},
        {'text': '我观察门锁', 'skill': '侦查'},
      ],
    });
    expect(actions.first.checkLabel, '意志');
  });
}
