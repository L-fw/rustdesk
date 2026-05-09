import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';

class LoginTabPage extends StatefulWidget {
  final Widget child;
  final bool showBackButton;

  const LoginTabPage({Key? key, required this.child, this.showBackButton = false}) : super(key: key);

  @override
  State<LoginTabPage> createState() => _LoginTabPageState();
}

class _LoginTabPageState extends State<LoginTabPage> with WindowListener {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);
  final invisibleTabKeys = <String>[].obs;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    if (isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        const windowSize = Size(460, 700); // Fixed size for login/register page
        await windowManager.setMinimumSize(windowSize);
        await windowManager.setResizable(false);
        await windowManager.setSize(windowSize);
      });
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    tabController.clear();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (rustDeskWinManager.getActiveWindows().contains(kMainWindowId)) {
      await rustDeskWinManager.unregisterActiveWindow(kMainWindowId);
    }
    bool isMinimized = await windowManager.isMinimized();
    if (isMinimized) {
      await windowManager.restore();
    }
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    final titleBar = SizedBox(
      height: kDesktopRemoteTabBarHeight,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: (_) => startDragging(true),
              onPanCancel: () {
                if (isMacOS) setMovable(true, false);
              },
              onPanEnd: (_) {
                if (isMacOS) setMovable(true, false);
              },
              onDoubleTap: () => toggleMaximize(true)
                  .then((value) => stateGlobal.setMaximized(value)),
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          WindowActionPanel(
            isMainWindow: true,
            state: tabController.state,
            tabController: tabController,
            invisibleTabKeys: invisibleTabKeys,
            showMinimize: true,
            showMaximize: false,
            showClose: true,
            onClose: widget.showBackButton
                ? () async {
                    Navigator.of(context).pop();
                    return false;
                  }
                : null,
          ).paddingOnly(left: 10),
        ],
      ),
    );

    final tabWidget = Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Column(
        children: [
          if (!kUseCompatibleUiMode) titleBar,
          Expanded(child: widget.child),
        ],
      ),
    );

    return isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => DragToResizeArea(
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: windowManagerEnableResizeEdges,
              child: tabWidget,
            ),
          );
  }
}

