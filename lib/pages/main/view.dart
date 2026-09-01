import 'dart:io';

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/floating_navigation_bar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:flutter/semantics.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/main_layout.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/common/widgets/scroll_behavior.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/android/android_helper.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/mobile_observer.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32/win32.dart' as kernel32;
import 'package:window_manager/window_manager.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends PopScopeState<MainApp>
    with WindowListener, TrayListener, RouteAwareMixin {
  late final MainController _mainController = Get.find<MainController>();
  late ColorScheme _colorScheme;
  late EdgeInsets _padding;

  @override
  void initState() {
    super.initState();
    if (PlatformUtils.isDesktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = ColorScheme.of(context);
    _padding = MediaQuery.paddingOf(context);
  }

  @override
  void dispose() {
    if (PlatformUtils.isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (_mainController.directExitOnBack) {
      windowManager.destroy();
    } else {
      windowManager.hide();
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        windowManager.show();
        windowManager.focus();
      case 'exit_app':
        windowManager.destroy();
    }
  }

  void _onBack() {
    if (_mainController.useSideBar) {
      if (_mainController.selectedIndex.value != 0) {
        _mainController
          ..setIndex(0)
          ..barOffset?.value = 0.0
          ..showBottomBar?.value = true
          ..setSearchBar();
      } else {
        _onBack();
      }
    } else {
      if (_mainController.selectedIndex.value != 0) {
        _mainController
          ..setIndex(0)
          ..barOffset?.value = 0.0
          ..showBottomBar?.value = true
          ..setSearchBar();
      } else {
        _onBack();
      }
    }
  }

  Widget? get _bottomNav {
    Widget? bottomNav;
    if (_mainController.navigationBars.length > 1) {
      if (_mainController.floatingNavBar) {
        bottomNav = Obx(
          () => FloatingNavigationBar(
            onDestinationSelected: _mainController.setIndex,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => FloatingNavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else if (_mainController.enableMYBar) {
        bottomNav = Obx(
          () => NavigationBar(
            maintainBottomViewPadding: true,
            onDestinationSelected: _mainController.setIndex,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => NavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else {
        bottomNav = Obx(
          () => BottomNavigationBar(
            currentIndex: _mainController.selectedIndex.value,
            onTap: _mainController.setIndex,
            iconSize: 16,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: .fixed,
            items: _mainController.navigationBars
                .map(
                  (e) => BottomNavigationBarItem(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    activeIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      }

      if (_mainController.hideBottomBar) {
        if (_mainController.barOffset case final barOffset?) {
          return Obx(
            () => FractionalTranslation(
              translation: Offset(
                0.0,
                barOffset.value / Style.topBarHeight,
              ),
              child: bottomNav,
            ),
          );
        }
        if (_mainController.showBottomBar case final showBottomBar?) {
          return Obx(
            () => AnimatedSlide(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              offset: Offset(0, showBottomBar.value ? 0 : 1),
              child: bottomNav,
            ),
          );
        }
      }
    }

    return bottomNav;
  }

  Widget _sideBar() {
    if (_mainController.navigationBars.length > 1) {
      if (context.isTablet && _mainController.optTabletNav) {
        return Padding(
          padding: const .only(top: 25),
          child: MediaQuery.removePadding(
            context: context,
            removeRight: true,
            child: DrawerTheme(
              data: DrawerThemeData(width: 130 + _padding.left),
              child: Obx(
                () => NavigationDrawer(
                  flex: 5,
                  backgroundColor: Colors.transparent,
                  onDestinationSelected: _mainController.setIndex,
                  selectedIndex: _mainController.selectedIndex.value,
                  header: Expanded(flex: 4, child: userAndSearchVertical()),
                  tilePadding: const .symmetric(vertical: 5, horizontal: 12),
                  indicatorShape: const RoundedRectangleBorder(
                    borderRadius: .all(.circular(16)),
                  ),
                  children: _mainController.navigationBars
                      .map(
                        (e) => NavigationDrawerDestination(
                          label: Text(e.label),
                          icon: _buildIcon(type: e),
                          selectedIcon: _buildIcon(
                            type: e,
                            selected: true,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        );
      }
      return Obx(
        () => NavigationRail(
          groupAlignment: 0.5,
          labelType: .selected,
          leading: userAndSearchVertical(),
          backgroundColor: Colors.transparent,
          onDestinationSelected: _mainController.setIndex,
          selectedIndex: _mainController.selectedIndex.value,
          destinations: _mainController.navigationBars
              .map(
                (e) => NavigationRailDestination(
                  label: Text(e.label),
                  icon: _buildIcon(type: e),
                  selectedIcon: _buildIcon(type: e, selected: true),
                ),
              )
              .toList(),
        ),
      );
    }
    return Container(
      width: 80,
      margin: .only(top: 12 + _padding.top, left: _padding.left),
      child: userAndSearchVertical(),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    final pageBody = _mainController.mainTabBarView
        ? TabBarView(
            controller: _mainController.controller,
            physics: const NeverScrollableScrollPhysics(),
            scrollDirection:
                _mainController.useBottomNav ? .horizontal : .vertical,
            children: _mainController.navigationBars.map((i) => i.page).toList(),
          )
        : PageView(
            controller: _mainController.controller,
            physics: const NeverScrollableScrollPhysics(),
            children: _mainController.navigationBars.map((i) => i.page).toList(),
          );

    // The outer main navigation pager is not content scrolling. Exclude it
    // from the app-wide VoiceOver paging bridge; the actual lists inside each
    // tab keep using CustomScrollBehavior normally.
    child = ScrollConfiguration(
      behavior: const MaterialScrollBehavior(),
      child: pageBody,
    );

    Widget? sideBar;
    Widget? bottomNav;
    final EdgeInsets padding;
    if (_mainController.useBottomNav) {
      bottomNav = _bottomNav;
      if (bottomNav != null) {
        bottomNav = MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: Semantics(
            container: true,
            explicitChildNodes: false,
            label: '導覽列',
            child: bottomNav,
          ),
        );
      }
      final navHeight = 75.0;
      padding = .only(
        top: _padding.top,
        left: _padding.left,
        right: _padding.right,
        bottom: navHeight,
      );
    } else {
      sideBar = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: _colorScheme.outline.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: _sideBar(),
      );
      padding = .only(
        top: _padding.top,
        right: _padding.right,
        bottom: _padding.bottom,
      );
    }

    return MainLayout(
      padding: padding,
      sideBar: sideBar,
      bottomNav: bottomNav,
      child: child,
    );
  }

  Widget _buildIcon({required NavigationBarType type, bool selected = false}) {
    return selected ? type.selectIcon : type.icon;
  }

  Widget userAndSearchVertical() => const SizedBox.shrink();

  void setSearchBar() {}
}
