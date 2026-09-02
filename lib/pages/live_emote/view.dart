import 'dart:math';

import 'package:PiliPlus/common/a11y/a11y_action_feedback.dart';
import 'package:PiliPlus/common/widgets/custom_tooltip.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show tabBarView, platformClampingPhysics;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/models_new/live/live_emote/datum.dart';
import 'package:PiliPlus/models_new/live/live_emote/emoticon.dart';
import 'package:PiliPlus/pages/live_emote/controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LiveEmotePanel extends StatefulWidget {
  final int roomId;
  final Function(Emoticon emote, double? width, double? height) onChoose;
  final ValueChanged<Emoticon> onSendEmoticonUnique;
  const LiveEmotePanel({
    super.key,
    required this.roomId,
    required this.onChoose,
    required this.onSendEmoticonUnique,
  });

  @override
  State<LiveEmotePanel> createState() => _LiveEmotePanelState();
}

class _LiveEmotePanelState extends State<LiveEmotePanel>
    with AutomaticKeepAliveClientMixin {
  late final LiveEmotePanelController _emotePanelController;

  @override
  void initState() {
    super.initState();
    _emotePanelController = Get.put(
      LiveEmotePanelController(widget.roomId),
      tag: widget.roomId.toString(),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(() => _buildBody(_emotePanelController.loadingState.value));
  }

  String _emoteA11yLabel(Emoticon item) {
    final raw = item.emoji?.trim();
    if (raw != null && raw.isNotEmpty) {
      final normalized = raw
          .replaceFirst(RegExp(r'^\['), '')
          .replaceFirst(RegExp(r'\]$'), '')
          .trim();
      if (normalized.isNotEmpty) {
        return '$normalized 貼圖';
      }
    }
    return '貼圖';
  }

  Widget _buildBody(LoadingState<List<LiveEmoteDatum>?> loadingState) {
    late final theme = Theme.of(context);
    late final color = ElevationOverlay.colorWithOverlay(
      theme.colorScheme.surface,
      theme.hoverColor,
      2,
    );
    return switch (loadingState) {
      Loading() => m3eLoading,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? Column(
                children: [
                  Expanded(
                    child: tabBarView(
                      controller: _emotePanelController.tabController,
                      children: response.map(
                        (item) {
                          final emote = item.emoticons;
                          if (emote == null || emote.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final first = emote.first;
                          final widthFac = first.width == null
                              ? 1.0
                              : max(1.0, first.width! / 80);
                          final heightFac = first.height == null
                              ? 1.0
                              : max(1.0, first.height! / 80);
                          final width = widthFac * 38;
                          final height = heightFac * 38;
                          return GridView.builder(
                            physics: platformClampingPhysics,
                            padding: const EdgeInsets.only(
                              left: 12,
                              right: 12,
                              bottom: 12,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: widthFac * 40,
                                  mainAxisExtent: heightFac * 40,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: emote.length,
                            itemBuilder: (context, index) {
                              final e = emote[index];
                              final label = _emoteA11yLabel(e);

                              void choose() {
                                if (item.pkgType == 3) {
                                  widget.onChoose(e, width, height);
                                  a11yActionFeedback(message: '已插入$label');
                                } else {
                                  widget.onSendEmoticonUnique(e);
                                  a11yActionFeedback(message: '已送出$label');
                                }
                              }

                              return Semantics(
                                container: true,
                                button: true,
                                excludeSemantics: true,
                                label: label,
                                hint: item.pkgType == 3
                                    ? '點兩下插入這個貼圖'
                                    : '點兩下送出這個貼圖',
                                onTap: choose,
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: InkWell(
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(6),
                                    ),
                                    onTap: choose,
                                    child: CustomTooltip(
                                      indicator: () => Triangle(
                                        color: color,
                                        size: const Size(14, 8),
                                      ),
                                      overlayWidget: () => Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: const BorderRadius.all(
                                            Radius.circular(8),
                                          ),
                                        ),
                                        child: Column(
                                          spacing: 4,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            NetworkImgLayer(
                                              src: e.url,
                                              width: 65,
                                              height: 65,
                                              type: ImageType.emote,
                                              fit: BoxFit.contain,
                                            ),
                                            Text(
                                              e.emoji == null
                                                  ? ''
                                                  : e.emoji!.startsWith('[')
                                                  ? e.emoji!.substring(
                                                      1,
                                                      e.emoji!.length - 1,
                                                    )
                                                  : e.emoji!,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: NetworkImgLayer(
                                          fit: BoxFit.contain,
                                          src: e.url,
                                          width: width,
                                          height: height,
                                          type: ImageType.emote,
                                          quality: item.pkgType == 3 ? 1 : 80,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ).toList(),
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: theme.dividerColor.withValues(alpha: 0.1),
                  ),
                  TabBar(
                    controller: _emotePanelController.tabController,
                    padding: const EdgeInsets.only(right: 60),
                    dividerColor: Colors.transparent,
                    dividerHeight: 0,
                    isScrollable: true,
                    tabs: response.indexed
                        .map(
                          (entry) => Semantics(
                            container: true,
                            button: true,
                            excludeSemantics: true,
                            label: '貼圖包第${entry.$1 + 1}組',
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: NetworkImgLayer(
                                width: 24,
                                height: 24,
                                type: ImageType.emote,
                                src: entry.$2.currentCover,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  SizedBox(height: MediaQuery.viewPaddingOf(context).bottom),
                ],
              )
            : _errorWidget(),
      Error(:final errMsg) => _errorWidget(errMsg),
    };
  }

  Widget _errorWidget([String? errMsg]) => Center(
    child: TextButton.icon(
      onPressed: _emotePanelController.onReload,
      icon: const Icon(Icons.refresh),
      label: Text(errMsg ?? '没有数据'),
    ),
  );
}
