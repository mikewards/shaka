import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/reports_preferences_repository.dart';

class ManageFishSheet extends StatefulWidget {
  final String regionId;
  final List<String> allSpecies;
  final ReportsPreferencesRepository prefsRepo;
  final ReportsPreferences initialPrefs;
  final ScrollController scrollController;

  const ManageFishSheet({
    super.key,
    required this.regionId,
    required this.allSpecies,
    required this.prefsRepo,
    required this.initialPrefs,
    required this.scrollController,
  });

  static Future<ReportsPreferences?> show({
    required BuildContext context,
    required String regionId,
    required List<String> allSpecies,
    required ReportsPreferencesRepository prefsRepo,
    required ReportsPreferences initialPrefs,
  }) {
    return showModalBottomSheet<ReportsPreferences>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return ManageFishSheet(
              regionId: regionId,
              allSpecies: allSpecies,
              prefsRepo: prefsRepo,
              initialPrefs: initialPrefs,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  @override
  State<ManageFishSheet> createState() => _ManageFishSheetState();
}

class _ManageFishSheetState extends State<ManageFishSheet> {
  static const _bgColor = AppColors.darkBackground;
  static const _cardColor = AppColors.darkSurface;
  static const _borderColor = AppColors.darkBorder;

  late Set<String> _hidden;
  late Set<String> _pinned;
  late List<String> _order;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hidden = {...widget.initialPrefs.hiddenSpecies};
    _pinned = {...widget.initialPrefs.pinnedSpecies};

    final baseOrder = widget.initialPrefs.manualOrder.isNotEmpty
        ? List<String>.from(widget.initialPrefs.manualOrder)
        : List<String>.from(widget.allSpecies);

    // Ensure order contains all known species (and no duplicates).
    final seen = <String>{};
    final normalized = <String>[];
    for (final s in baseOrder) {
      if (widget.allSpecies.contains(s) && seen.add(s)) normalized.add(s);
    }
    for (final s in widget.allSpecies) {
      if (seen.add(s)) normalized.add(s);
    }
    _order = normalized;
  }

  List<String> get _visibleOrdered =>
      _order.where((s) => !_hidden.contains(s)).toList();

  List<String> get _hiddenSorted {
    final items = widget.allSpecies.where(_hidden.contains).toList();
    items.sort();
    return items;
  }

  Future<void> _persist() async {
    setState(() => _saving = true);
    try {
      await widget.prefsRepo.saveHiddenSpecies(widget.regionId, _hidden);
      await widget.prefsRepo.savePinnedSpecies(widget.regionId, _pinned);
      await widget.prefsRepo.saveManualOrder(widget.regionId, _order);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    HapticFeedback.lightImpact();
    setState(() {
      _hidden = <String>{};
      _pinned = <String>{};
      _order = List<String>.from(widget.allSpecies);
    });
    _persist();
  }

  void _togglePin(String species) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_pinned.contains(species)) {
        _pinned.remove(species);
      } else {
        _pinned.add(species);
      }
    });
    _persist();
  }

  void _hide(String species) {
    HapticFeedback.lightImpact();
    setState(() {
      _hidden.add(species);
    });
    _persist();
  }

  void _show(String species) {
    HapticFeedback.selectionClick();
    setState(() {
      _hidden.remove(species);
    });
    _persist();
  }

  void _onReorder(int oldIndex, int newIndex) {
    HapticFeedback.selectionClick();
    final visible = _visibleOrdered;
    if (newIndex > visible.length) newIndex = visible.length;
    if (oldIndex < newIndex) newIndex -= 1;
    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex, moved);

    // Merge back into full order list while keeping hidden species at end
    // (relative order preserved).
    final hidden = _order.where((s) => _hidden.contains(s)).toList();
    setState(() {
      _order = [...visible, ...hidden];
    });
    _persist();
  }

  void _done() async {
    if (_saving) return;
    HapticFeedback.selectionClick();
    final result = ReportsPreferences(
      hiddenSpecies: _hidden,
      pinnedSpecies: _pinned,
      manualOrder: _order,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final visible = _visibleOrdered;
    final hidden = _hiddenSorted;

    return Container(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.darkTextHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : _reset,
                    child: Text(
                      'Reset',
                      style: TextStyle(
                        color: _saving ? AppColors.darkTextHint : AppColors.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Manage Fish',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : _done,
                    child: Text(
                      _saving ? 'Saving…' : 'Done',
                      style: TextStyle(
                        color: _saving ? AppColors.darkTextHint : AppColors.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 20),
                children: [
                  _sectionLabel('VISIBLE'),
                  const SizedBox(height: 10),
                  _groupCard(
                    child: ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorder: _onReorder,
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, index, animation) {
                        return Material(
                          color: Colors.transparent,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 1.0, end: 1.02)
                                .animate(animation),
                            child: child,
                          ),
                        );
                      },
                      children: [
                        for (var i = 0; i < visible.length; i++)
                          _ManageRow(
                            key: ValueKey('visible_${visible[i]}'),
                            index: i,
                            title: visible[i],
                            pinned: _pinned.contains(visible[i]),
                            onTogglePin: () => _togglePin(visible[i]),
                            onHide: () => _hide(visible[i]),
                          ),
                      ],
                    ),
                  ),
                  if (hidden.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _sectionLabel('HIDDEN'),
                    const SizedBox(height: 10),
                    _groupCard(
                      child: Column(
                        children: [
                          for (var i = 0; i < hidden.length; i++)
                            Column(
                              children: [
                                _HiddenRow(
                                  title: hidden[i],
                                  onShow: () => _show(hidden[i]),
                                ),
                                if (i < hidden.length - 1)
                                  Container(
                                    height: 1,
                                    margin:
                                        const EdgeInsets.only(left: 16 + 28),
                                    color: _borderColor,
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withOpacity(0.5),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _groupCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ManageRow extends StatelessWidget {
  final int index;
  final String title;
  final bool pinned;
  final VoidCallback onTogglePin;
  final VoidCallback onHide;

  const _ManageRow({
    super.key,
    required this.index,
    required this.title,
    required this.pinned,
    required this.onTogglePin,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTogglePin,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Icon(
                  Icons.drag_handle,
                  color: AppColors.darkTextHint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: onTogglePin,
                icon: Icon(
                  pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: pinned ? AppColors.info : AppColors.darkTextHint,
                  size: 18,
                ),
              ),
              IconButton(
                onPressed: onHide,
                icon: const Icon(
                  Icons.visibility_off_outlined,
                  color: AppColors.darkTextHint,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HiddenRow extends StatelessWidget {
  final String title;
  final VoidCallback onShow;

  const _HiddenRow({
    required this.title,
    required this.onShow,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.visibility_off_outlined,
              color: AppColors.darkTextHint, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onShow,
            child: const Text(
              'Show',
              style: TextStyle(
                color: AppColors.info,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
