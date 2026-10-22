/// 数值规则常量与枚举（SE §3.7、§3.3）。
///
/// 这里集中放「可以被讨论、可以被改」的数字与名字：
/// 改数值只改本文件，不改逻辑。
///
/// 依据：
/// - Q-02：8 项属性总和 550（初始各 50 + 可分配 150），单项 15–90
/// - Q-04 / Q-11：9 项技能，技能点 = 智力 × 6（智力 50 时 300），可分配项上限 70
/// - Q-09：大成功 / 大失败分两档（按基础技能值）
library;

/// 8 项基础属性。
enum Attribute { str, dex, pow, con, intel, mag, luck, app }

extension AttributeInfo on Attribute {
  /// 界面上显示的中文名。
  String get label => switch (this) {
    Attribute.str => '力量',
    Attribute.dex => '敏捷',
    Attribute.pow => '意志',
    Attribute.con => '体质',
    Attribute.intel => '智力',
    Attribute.mag => '魔法',
    Attribute.luck => '幸运',
    Attribute.app => '外貌',
  };
}

/// 8 项技能。
///
/// `mythos` 不可分配：只能通过接触神话获得。
enum Skill {
  mythos,
  spotHidden,
  listen,
  libraryUse,
  stealth,
  psychology,
  sleightOfHand,
  persuade,
}

extension SkillInfo on Skill {
  String get label => switch (this) {
    Skill.mythos => '神话',
    Skill.spotHidden => '侦查',
    Skill.listen => '聆听',
    Skill.libraryUse => '图书馆',
    Skill.stealth => '潜行',
    Skill.psychology => '心理学',
    Skill.sleightOfHand => '妙手',
    Skill.persuade => '话术',
  };

  /// 经典基础值。
  int get baseValue => switch (this) {
    Skill.mythos => 0,
    Skill.spotHidden => 25,
    Skill.listen => 20,
    Skill.libraryUse => 20,
    Skill.stealth => 20,
    Skill.psychology => 10,
    Skill.sleightOfHand => 10,
    Skill.persuade => 5,
  };

  bool get isAllocatable => this != Skill.mythos;
}

/// 按中文名查属性（建议行动、剧本标注用）。
Attribute? attributeByLabel(String label) {
  for (final attribute in Attribute.values) {
    if (attribute.label == label) return attribute;
  }
  return null;
}

/// 按中文名查技能（剧本 YAML 用）。
Skill? skillByLabel(String label) {
  for (final skill in Skill.values) {
    if (skill.label == label) return skill;
  }
  return null;
}

// ---------------------------------------------------------------------------
// 属性
// ---------------------------------------------------------------------------

/// BP（AI 玩家）没有角色卡：所有技能统一按 55 算。
const int bpSkillValue = 55;

const int attributeBase = 50;
const int attributeMin = 15;
const int attributeMax = 90;
const int attributeCount = 8;
const int attributeTotal = 550;

/// 可自由分配的点数：550 - 8 × 50 = 150。
const int attributePool = attributeTotal - attributeBase * attributeCount;

// ---------------------------------------------------------------------------
// 技能
// ---------------------------------------------------------------------------

/// 技能点 = 智力 × 6（智力 50 时共 300）。
const int skillPointsPerInt = 6;

/// 可分配技能的上限。
const int skillMax = 70;

// ---------------------------------------------------------------------------
// 角色卡
// ---------------------------------------------------------------------------

/// 随身物品上限：先只允许 2 件，后续再开放（V-20）。
const int itemSlots = 2;
const int maxNameLength = 12;
const int maxOccupationLength = 12;
const int minAge = 16;
const int maxAge = 90;

/// HP = 体质 ÷ 5 + 5。
int hpFor(int con) => con ~/ 5 + 5;

/// MP = 意志 ÷ 5。
int mpFor(int pow) => pow ~/ 5;

/// SAN 上限 = 意志（初始值；之后独立受损）。
int sanMaxFor(int pow) => pow;

// ---------------------------------------------------------------------------
// 检定（Q-09）
// ---------------------------------------------------------------------------

/// 宽档阈值：基础技能 ≥ 50 时，大成功 1–5、大失败仅 100。
const int wideTierThreshold = 50;

/// 宽档大成功上沿。
const int wideTierCritHigh = 5;

/// 窄档大成功上沿（只有 1）。
const int narrowTierCritHigh = 1;

/// 窄档大失败下沿。
const int narrowTierFumbleLow = 96;

/// 宽档大失败下沿（只有 100）。
const int wideTierFumbleLow = 100;
