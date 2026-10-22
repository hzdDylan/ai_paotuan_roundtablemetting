import 'dart:math';

/// BP（AI 玩家）中文名字池。
const List<String> bpNamesZh = <String>[
  '沈砚',
  '陆离',
  '白露',
  '顾青',
  '苏禾',
  '程野',
  '林澈',
  '叶知秋',
  '温言',
  '许迟',
  '江照',
  '闻笛',
  '唐棠',
  '宋栖',
  '周叙',
  '秦岚',
  '孟舟',
  '裴然',
  '祁安',
  '阮夕',
  '何暮',
  '施南',
  '柳汀',
  '谢寻',
];

/// BP（AI 玩家）英文名字池。
const List<String> bpNamesEn = <String>[
  'Vincent',
  'Marlow',
  'Ada',
  'Rowan',
  'Elias',
  'Nora',
  'Julian',
  'Iris',
  'Felix',
  'Clara',
  'Hugo',
  'Vera',
  'Oscar',
  'Lena',
  'Miles',
  'Ruth',
  'Simon',
  'Edith',
  'Leo',
  'Mabel',
  'Arthur',
  'Nina',
  'Walter',
  'Stella',
];

/// 玩家名是否含中文。
bool isChineseName(String name) => RegExp(r'[\u4e00-\u9fff]').hasMatch(name);

/// 按玩家名字的语言挑 BP 名：中文玩家配中文名，其余配英文名。
List<String> pickBpNames(int count, {String playerName = '', Random? random}) {
  final rng = random ?? Random();
  final zh = isChineseName(playerName);
  final pool = List<String>.from(zh ? bpNamesZh : bpNamesEn)..shuffle(rng);
  return pool.take(count).toList(growable: false);
}
