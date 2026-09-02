import 'package:PiliPlus/common/a11y/a11y_focus_scroll.dart';
import 'package:PiliPlus/common/widgets/avatars.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/dynamics/widgets/action_panel.dart';
import 'package:PiliPlus/pages/dynamics/widgets/author_panel.dart';
import 'package:PiliPlus/pages/dynamics/widgets/dyn_content.dart';
import 'package:PiliPlus/pages/dynamics/widgets/interaction.dart';
import 'package:PiliPlus/pages/dynamics_repost/view.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/request_utils.dart';
import 'package:flutter/semantics.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class DynamicPanel extends StatelessWidget {
  final DynamicItemModel item;
  final bool isDetail;
  final ValueChanged<Object>? onRemove;
  final bool isSave;
  final void Function(bool isTop, Object dynId)? onSetTop;
  final VoidCallback? onBlock;
  final VoidCallback? onUnfold;
  final bool isDetailPortraitW;
  final Future<LoadingState> Function(bool isPrivate, Object dynId)?
  onSetPubSetting;
  final VoidCallback? onEdit;
  final ValueChanged<int>? onSetReplySubject;

  const DynamicPanel({
    super.key,
    required this.item,
    this.isDetail = false,
    this.onRemove,
    this.isSave = false,
    this.onSetTop,
    this.onBlock,
    this.onUnfold,
    this.isDetailPortraitW = true,
    this.onSetPubSetting,
    this.onEdit,
    this.onSetReplySubject,
  });

  String? _clean(String? value) {
    final text = value?.trim();
    return text?.isNotEmpty == true ? text : null;
  }

  String? _majorText(DynamicItemModel target) {
    final major = target.modules.moduleDynamic?.major;
    if (major == null) return null;
    final values = <String?>[
      major.opus?.title,
      major.archive?.title,
      major.ugcSeason?.title,
      major.pgc?.title,
      major.courses?.title,
      major.liveRcmd?.title,
      major.live?.title,
      major.medialist?.title,
      major.music?.title,
      major.common?.title,
      major.upowerCommon?.title,
      major.subscriptionNew?.liveRcmd?.content?.livePlayInfo?.title,
      major.none?.tips,
    ];
    for (final value in values) {
      if (_clean(value) case final text?) return text;
    }
    return null;
  }

  String? _bodyText(DynamicItemModel target) {
    final moduleDynamic = target.modules.moduleDynamic;
    final desc = _clean(moduleDynamic?.desc?.text);
    final summary = _clean(moduleDynamic?.major?.opus?.summary?.text);
    if (desc != null && summary != null && desc != summary) {
      return '$desc，$summary';
    }
    return desc ?? summary;
  }

  String _a11yLabel(DynamicItemModel target) {
    final author = target.modules.moduleAuthor;
    final moduleDynamic = target.modules.moduleDynamic;
    final stat = target.modules.moduleStat;
    final parts = <String>[
      _clean(author?.name) ?? '未知使用者',
      if (_clean(moduleDynamic?.topic?.name) case final topic?) '話題 $topic',
      if (_bodyText(target) case final body?) body,
      if (_majorText(target) case final major?) major,
    ];

    if (target.orig case final orig?) {
      final origParts = <String>[
        if (_clean(orig.modules.moduleAuthor?.name) case final name?) name,
        if (_bodyText(orig) case final body?) body,
        if (_majorText(orig) case final major?) major,
      ];
      if (origParts.isNotEmpty) {
        parts.add('轉發自 ${origParts.join('，')}');
      }
    }

    final picCount = moduleDynamic?.major?.opus?.pics?.length ?? 0;
    if (picCount > 0) {
      parts.add('包含$picCount張圖片');
    }
    if (_clean(target.modules.moduleDispute?.title) case final dispute?) {
      parts.add(dispute);
    }
    if (stat?.forward?.count case final count?) {
      parts.add('轉發$count');
    }
    if (stat?.comment?.count case final count?) {
      parts.add('評論$count');
    }
    if (stat?.like?.count case final count?) {
      parts.add('讚$count');
    }
    if (author?.pubTs case final pubTs?) {
      final pubTime = DateFormatUtils.a11yDateFormat(pubTs);
      if (pubTime.isNotEmpty) {
        parts.add('$pubTime發佈');
      }
    } else if (_clean(author?.pubTime) case final pubTime?) {
      parts.add('$pubTime發佈');
    }
    return parts.join('，');
  }

  @override
  Widget build(BuildContext context) {
    if (item.visible == false) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final authorWidget = AuthorPanel(
      item: item,
      isDetail: isDetail,
      onRemove: onRemove,
      isSave: isSave,
      onSetTop: onSetTop,
      onBlock: onBlock,
      onSetPubSetting: onSetPubSetting,
      onEdit: onEdit,
      onSetReplySubject: onSetReplySubject,
    );

    void showMore() => _imageSaveDialog(context, authorWidget.morePanel);

    void openDetail() => PageUtils.pushDynDetail(item);

    void showRepost() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => RepostPanel(
          item: item,
          onSuccess: () {
            final forward = item.modules.moduleStat?.forward;
            if (forward != null) {
              forward.count = (forward.count ?? 0) + 1;
            }
            if (context.mounted) {
              (context as Element?)?.markNeedsBuild();
            }
          },
        ),
      );
    }

    void openComments() => PageUtils.pushDynDetail(
      item,
      isPush: true,
      viewComment: true,
    );

    void toggleLike() {
      final like = item.modules.moduleStat?.like;
      if (like == null) return;
      RequestUtils.onLikeDynamic(
        item,
        like.status ?? false,
        () {
          if (context.mounted) {
            (context as Element?)?.markNeedsBuild();
          }
        },
      );
    }

    void visitAuthor() {
      final mid = item.modules.moduleAuthor?.mid;
      if (mid != null) {
        Get.toNamed('/member?mid=$mid');
      }
    }

    final child = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap:
            isDetail &&
                !const {
                  'DYNAMIC_TYPE_AV',
                  'DYNAMIC_TYPE_UGC_SEASON',
                  'DYNAMIC_TYPE_PGC_UNION',
                  'DYNAMIC_TYPE_PGC',
                  'DYNAMIC_TYPE_LIVE',
                  'DYNAMIC_TYPE_LIVE_RCMD',
                  'DYNAMIC_TYPE_MEDIALIST',
                  'DYNAMIC_TYPE_COURSES_SEASON',
                }.contains(item.type)
            ? null
            : openDetail,
        onLongPress: showMore,
        onSecondaryTap: PlatformUtils.isMobile ? null : showMore,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: authorWidget,
            ),
            if (item.modules.moduleDispute case final moduleDispute?)
              _buildDispute(theme, moduleDispute),
            ...dynContent(
              context,
              theme: theme,
              isSave: isSave,
              isDetail: isDetail,
              item: item,
              floor: 1,
            ),
            const SizedBox(height: 2),
            if (!isDetail) ...[
              if (item.modules.moduleInteraction case ModuleInteraction(
                :final items,
              ))
                if (items != null && items.isNotEmpty)
                  dynInteraction(
                    theme: theme,
                    items: items,
                  ),
              ActionPanel(item: item),
              if (item.modules.moduleFold case final moduleFold?) ...[
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.1),
                ),
                _buildFoldItem(theme, moduleFold),
              ],
            ] else if (!isSave)
              const SizedBox(height: 12),
          ],
        ),
      ),
    );

    final semanticsChild = isDetail
        ? child
        : Semantics(
            container: true,
            explicitChildNodes: false,
            excludeSemantics: true,
            button: true,
            label: _a11yLabel(item),
            hint: '點兩下開啟動態。上下滑可轉發、查看評論、點讚或開啟更多操作',
            onTap: openDetail,
            onDidGainAccessibilityFocus: () => a11yEnsureVisible(context),
            customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
              if (item.modules.moduleStat?.forward != null)
                const CustomSemanticsAction(label: '轉發'): showRepost,
              if (item.modules.moduleStat?.comment != null)
                const CustomSemanticsAction(label: '查看評論'): openComments,
              if (item.modules.moduleStat?.like case final like?)
                CustomSemanticsAction(
                  label: like.status == true ? '取消讚' : '點讚',
                ): toggleLike,
              if (item.modules.moduleAuthor?.mid != null)
                const CustomSemanticsAction(label: '造訪使用者'): visitAuthor,
              const CustomSemanticsAction(label: '更多操作'): showMore,
            },
            child: child,
          );

    if (isSave || (isDetail && !isDetailPortraitW)) {
      return semanticsChild;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            width: 8,
            color: theme.dividerColor.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: semanticsChild,
      ),
    );
  }

  void _imageSaveDialog(
    BuildContext context,
    Function(BuildContext) morePanel,
  ) {
    String? title;
    String? cover;
    String? bvid;
    late final major = item.modules.moduleDynamic?.major;
    switch (item.type) {
      case 'DYNAMIC_TYPE_AV':
        if (major?.archive case final archive?) {
          title = archive.title;
          cover = archive.cover;
          bvid = archive.bvid;
        }
        break;
      case 'DYNAMIC_TYPE_UGC_SEASON':
        if (major?.ugcSeason case final ugcSeason?) {
          title = ugcSeason.title;
          cover = ugcSeason.cover;
          bvid = ugcSeason.bvid;
        }
        break;
      case 'DYNAMIC_TYPE_PGC' || 'DYNAMIC_TYPE_PGC_UNION':
        if (major?.pgc case final pgc?) {
          title = pgc.title;
          cover = pgc.cover;
        }
        break;
      case 'DYNAMIC_TYPE_LIVE_RCMD':
        if (major?.liveRcmd case final liveRcmd?) {
          title = liveRcmd.title;
          cover = liveRcmd.cover;
        }
        break;
      case 'DYNAMIC_TYPE_LIVE':
        if (major?.live case final live?) {
          title = live.title;
          cover = live.cover;
        }
        break;
      case 'DYNAMIC_TYPE_COURSES_SEASON':
        if (major?.courses case final courses?) {
          title = courses.title;
          cover = courses.cover;
        }
        break;
      case 'DYNAMIC_TYPE_SUBSCRIPTION_NEW':
        if (major?.subscriptionNew?.liveRcmd?.content?.livePlayInfo
            case final livePlayInfo?) {
          title = livePlayInfo.title;
          cover = livePlayInfo.cover;
        }
        break;
      default:
        morePanel(context);
        return;
    }
    imageSaveDialog(
      title: title,
      cover: cover,
      bvid: bvid,
    );
  }

  Widget _buildFoldItem(ThemeData theme, ModuleFold moduleFold) {
    Widget child = Text.rich(
      textAlign: TextAlign.center,
      style: TextStyle(
        height: 1,
        fontSize: 13,
        color: theme.colorScheme.outline,
      ),
      strutStyle: const StrutStyle(
        height: 1,
        leading: 0,
        fontSize: 13,
      ),
      TextSpan(
        children: [
          TextSpan(text: moduleFold.statement ?? '展开'),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(
              size: 19,
              Icons.keyboard_arrow_down,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
    final users = moduleFold.users;
    if (users != null && users.isNotEmpty) {
      child = Row(
        spacing: 5,
        mainAxisAlignment: .center,
        children: [
          avatars(colorScheme: theme.colorScheme, users: users),
          child,
        ],
      );
    }
    return InkWell(
      onTap: onUnfold,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: child,
      ),
    );
  }

  Widget _buildDispute(ThemeData theme, ModuleDispute moduleDispute) {
    final child = Container(
      width: .infinity,
      margin: const .fromLTRB(12, 2, 12, 6),
      padding: const .symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(
          alpha: theme.isLight ? 0.5 : 0.7,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Text.rich(
        style: TextStyle(
          height: 1,
          fontSize: 13,
          color: theme.colorScheme.onSecondaryContainer,
        ),
        strutStyle: const StrutStyle(
          leading: 0,
          height: 1,
          fontSize: 13,
        ),
        TextSpan(
          children: [
            WidgetSpan(
              alignment: .middle,
              child: Padding(
                padding: const .only(right: 4),
                child: Icon(
                  size: 15,
                  Icons.warning_rounded,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            TextSpan(text: moduleDispute.title),
          ],
        ),
      ),
    );
    if (moduleDispute.jumpUrl?.isNotEmpty == true) {
      return GestureDetector(
        onTap: () => PageUtils.handleWebview(moduleDispute.jumpUrl!),
        child: child,
      );
    }
    return child;
  }
}
