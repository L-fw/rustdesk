import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

class LoginTabPage extends StatefulWidget {
  final Widget child;
  final bool showBackButton;

  const LoginTabPage({Key? key, required this.child, this.showBackButton = false}) : super(key: key);

  @override
  State<LoginTabPage> createState() => _LoginTabPageState();
}

class _LoginTabPageState extends State<LoginTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);
  final invisibleTabKeys = <String>[].obs;

  @override
  void initState() {
    super.initState();
    if (isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        const minSize = Size(460, 720); // Minimum size to fit login & register pages
        await windowManager.setMinimumSize(minSize);
        final size = await windowManager.getSize();
        if (size.width < minSize.width || size.height < minSize.height) {
          await windowManager.setSize(Size(
            size.width < minSize.width ? minSize.width : size.width,
            size.height < minSize.height ? minSize.height : size.height,
          ));
        }
      });
    }
  }

  @override
  void dispose() {
    tabController.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titleBar = SizedBox(
      height: kDesktopRemoteTabBarHeight,
      child: Row(
        children: [
          if (widget.showBackButton)
            Padding(
              padding: const EdgeInsets.only(left: 8.0, right: 8.0),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 20,
              ),
            ),
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
            showMaximize: true,
            showClose: true,
          ).paddingOnly(left: 10),
        ],
      ),
    );

    final tabWidget = Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Column(
        children: [
           Obx(() => (stateGlobal.showTabBar.isTrue && !kUseCompatibleUiMode)
              ? titleBar
              : const SizedBox.shrink()),
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

