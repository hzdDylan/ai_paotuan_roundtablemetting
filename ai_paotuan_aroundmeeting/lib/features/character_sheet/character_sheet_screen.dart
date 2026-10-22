import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/theme.dart';
import '../../engine/rules/character_rules.dart';
import '../../engine/rules/character_sheet.dart';
import '../../ui/widgets/seat_avatar.dart';
import '../../ui/widgets/stat_bar.dart';

/// 制卡 / 我的（PRD 05 §3）。
class CharacterSheetScreen extends ConsumerWidget {
  const CharacterSheetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheet = ref.watch(characterProvider);
    final notifier = ref.read(characterProvider.notifier);
    final errors = sheet.validate();
    final attributeRemaining = sheet.attributes.remaining;
    final skillRemaining = sheet.skills.remainingFor(sheet.attributes);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text(
          '制 卡',
          style: TextStyle(fontSize: 16, letterSpacing: 4),
        ),
        actions: [
          IconButton(
            tooltip: '重置角色',
            icon: const Icon(Icons.refresh),
            onPressed: notifier.reset,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _IdentityCard(sheet: sheet, notifier: notifier),
          const SizedBox(height: 22),
          _SectionHeader(
            title: '基础属性',
            trailing:
                '总和 ${sheet.attributes.total} / $attributeTotal'
                ' · 余 $attributeRemaining',
            warn: attributeRemaining != 0,
            action: TextButton(
              onPressed: attributeRemaining > 0
                  ? notifier.randomizeAttributes
                  : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('随机分配', style: TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(height: 4),
          for (final attribute in Attribute.values)
            StatBar(
              label: attribute.label,
              value: sheet.attributes[attribute],
              min: attributeMin,
              max: math.min(
                attributeMax,
                sheet.attributes[attribute] +
                    (attributeRemaining > 0 ? attributeRemaining : 0),
              ),
              // 进度条量程固定为 15–90，不随余额变化，否则会显示成「全满」。
              ratioMax: attributeMax,
              onChanged: (value) => notifier.setAttribute(attribute, value),
            ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: '技能',
            trailing:
                '技能点 ${sheet.skills.budgetFor(sheet.attributes)}'
                ' · 余 $skillRemaining',
            warn: skillRemaining < 0,
            action: TextButton(
              onPressed: skillRemaining > 0 ? notifier.randomizeSkills : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('随机分配', style: TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(height: 4),
          for (final skill in Skill.values.where((s) => s.isAllocatable))
            StatBar(
              label: skill.label,
              value: sheet.skills[skill],
              min: skill.baseValue,
              ratioMin: 0,
              max: math.min(
                skillMax,
                sheet.skills[skill] + (skillRemaining > 0 ? skillRemaining : 0),
              ),
              ratioMax: skillMax,
              onChanged: (value) => notifier.setSkill(skill, value),
            ),
          const SizedBox(height: 4),
          _DerivedRow(
            label: '神话（不可分配）',
            value: '${sheet.skills[Skill.mythos]}',
          ),
          const SizedBox(height: 20),
          const _SectionHeader(title: '派生'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DerivedChip(label: 'HP', value: '${sheet.hp}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DerivedChip(label: 'MP', value: '${sheet.mp}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DerivedChip(
                  label: 'SAN',
                  value: '${sheet.sanCurrent} / ${sheet.sanMax}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionHeader(
            title: '随身物品',
            trailing: '${sheet.items.length} / $itemSlots',
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < itemSlots; index++)
            _ItemTile(
              item: index < sheet.items.length ? sheet.items[index] : null,
              onTap: () async {
                final current = index < sheet.items.length
                    ? sheet.items[index]
                    : null;
                final edited = await showDialog<Item>(
                  context: context,
                  builder: (_) => _ItemDialog(initial: current),
                );
                if (edited != null) notifier.setItem(index, edited);
              },
              onRemove: index < sheet.items.length
                  ? () => notifier.removeItem(index)
                  : null,
            ),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ValidationBanner(errors: errors),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _save(context, errors),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: Color(0x66C9A227)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('保存'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    if (errors.isEmpty) {
                      // 从剧本进来制卡的：存完直接回到该剧本，不再选一次。
                      final pending = ref
                          .read(pendingScenarioProvider.notifier)
                          .consume();
                      context.go(pending ? '/session-config' : '/scenarios');
                    } else {
                      _save(context, errors);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brass,
                    foregroundColor: AppColors.parchmentInk,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('选择剧本'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save(BuildContext context, List<String> errors) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(errors.isEmpty ? '草稿已保存（本机）' : '还不能保存：${errors.first}'),
      ),
    );
  }
}

/// 物品编辑弹窗：独立 StatefulWidget，控制器生命周期清晰；
/// 名称为空时「确定」不可点，等于无操作。
class _ItemDialog extends StatefulWidget {
  const _ItemDialog({this.initial});

  final Item? initial;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.initial?.note ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _name.text.trim().isNotEmpty;

    return AlertDialog(
      backgroundColor: AppColors.surfaceHigh,
      title: const Text('随身物品', style: TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 12,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '名称', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: '一句话描述',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: canSave
              ? () => Navigator.of(
                  context,
                ).pop(Item(name: _name.text.trim(), note: _note.text.trim()))
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.sheet, required this.notifier});

  final CharacterSheet sheet;
  final CharacterNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeatAvatar(
          name: sheet.name,
          role: sheet.occupation,
          colorSeed: sheet.avatarColorSeed,
          size: 64,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            children: [
              TextFormField(
                initialValue: sheet.name,
                maxLength: maxNameLength,
                decoration: const InputDecoration(
                  labelText: '姓名',
                  counterText: '',
                ),
                onChanged: notifier.rename,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: sheet.occupation,
                      maxLength: maxOccupationLength,
                      decoration: const InputDecoration(
                        labelText: '职业',
                        counterText: '',
                      ),
                      onChanged: notifier.setOccupation,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 84,
                    child: TextFormField(
                      initialValue: '${sheet.age}',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '年龄'),
                      onChanged: (value) {
                        final age = int.tryParse(value);
                        if (age != null) notifier.setAge(age);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.trailing,
    this.warn = false,
    this.action,
  });

  final String title;
  final String? trailing;
  final bool warn;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(title, style: sectionLabel()),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                trailing!,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: warn ? AppColors.blood : AppColors.inkMuted,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (action != null) ...[const SizedBox(width: 6), action!],
        ],
      ),
    );
  }
}

class _DerivedRow extends StatelessWidget {
  const _DerivedRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 13, color: AppColors.brass),
          ),
        ],
      ),
    );
  }
}

class _DerivedChip extends StatelessWidget {
  const _DerivedChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x33C9A227)),
      ),
      child: Column(
        children: [
          Text(label, style: sectionLabel()),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap, this.onRemove});

  final Item? item;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: item == null
                  ? const Color(0x22FFFFFF)
                  : const Color(0x44C9A227),
            ),
          ),
          child: Row(
            children: [
              Icon(
                item == null ? Icons.add : Icons.inventory_2_outlined,
                size: 16,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item == null
                      ? '添加物品'
                      : '${item!.name}${item!.note.isEmpty ? '' : ' · ${item!.note}'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: item == null ? AppColors.inkMuted : AppColors.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 16),
                  color: AppColors.inkMuted,
                  tooltip: '移除',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValidationBanner extends StatelessWidget {
  const _ValidationBanner({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.blood.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.blood.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '还不能上桌',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.blood,
            ),
          ),
          const SizedBox(height: 6),
          for (final error in errors)
            Text('· $error', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
