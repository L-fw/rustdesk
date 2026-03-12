import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/app_auth_service.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/web/settings_page.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'app_login_page.dart';
import 'connection_page.dart';

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  final List<PageShape> _pages = [];
  bool get isChatPageCurrentTab => false;
  var _loginStatusDialogShowing = false;

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initPages();
    _checkLoginStatus();
    // Listen for device banned status
    ever(stateGlobal.deviceBanned, (banned) {
      if (banned) {
        _showBannedDialog();
      }
    });
    // Listen for remote disabled status (WebSocket push)
    ever(stateGlobal.remoteDisabled, (disabled) {
      if (disabled) {
        if (stateGlobal.isInMainPage) {
          _showRemoteDisabledDialog();
        }
      } else {
        _dismissRemoteDisabledDialog();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLoginStatus();
    }
  }

  void _showBannedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('设备已被禁用'),
          content: Obx(() => Text(stateGlobal.bannedMessage.value)),
          actions: const [],
        ),
      ),
    );
  }

  void _showRemoteDisabledDialog() {
    if (!mounted || !stateGlobal.isInMainPage) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: Row(children: [
            const Icon(Icons.block, color: Colors.redAccent, size: 28),
            const SizedBox(width: 10),
            const Text('远程功能已禁用'),
          ]),
          content: Obx(() => Text(
            stateGlobal.remoteDisabledMessage.value.isNotEmpty
                ? stateGlobal.remoteDisabledMessage.value
                : '远程功能已被管理员禁用，远程连接已断开。\n管理员恢复权限后将自动恢复。',
          )),
          actions: const [],
        ),
      ),
    ).then((_) {
      // dialog closed
    });
  }

  void _dismissRemoteDisabledDialog() {
    if (!mounted) return;
    // Close any open dialog
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void initPages() {
    _pages.clear();
    if (!kAppModeShareOnly && !bind.isIncomingOnly()) {
      _pages.add(ConnectionPage(
        appBarActions: [],
      ));
    }
    if (isAndroid && !bind.isOutgoingOnly()) {
      _pages.add(ServerPage());
    }
    _pages.add(SettingsPage());
  }

  Future<void> _checkLoginStatus() async {
    if (kAppModeShareOnly) return;
    final ok = await AppAuthService().isLoggedIn();
    if (!ok && mounted) {
      await _showLoginExpiredDialog();
    }
  }

  Future<void> _showLoginExpiredDialog() async {
    if (!mounted || _loginStatusDialogShowing) return;
    _loginStatusDialogShowing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('账号异常'),
          content: const Text('账号已在其他设备登录'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                SystemNavigator.pop();
              },
              child: const Text('直接退出'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AppLoginPage()),
                  (route) => false,
                );
              },
              child: const Text('重新登录'),
            ),
          ],
        ),
      ),
    );
    if (mounted) {
      _loginStatusDialogShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          if (_selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
          } else {
            return true;
          }
          return false;
        },
        child: Scaffold(
          // backgroundColor: MyTheme.grayBg,
          appBar: AppBar(
            centerTitle: true,
            title: appTitle(),
            actions: _pages.elementAt(_selectedIndex).appBarActions,
          ),
          bottomNavigationBar: BottomNavigationBar(
            key: navigationBarKey,
            items: _pages
                .map((page) =>
                    BottomNavigationBarItem(icon: page.icon, label: page.title))
                .toList(),
            currentIndex: _selectedIndex,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: MyTheme.accent, //
            unselectedItemColor: MyTheme.darkGray,
            onTap: (index) => setState(() {
              // close chat overlay when go chat page
              if (_selectedIndex != index) {
                _selectedIndex = index;
                if (isChatPageCurrentTab) {
                  gFFI.chatModel.hideChatIconOverlay();
                  gFFI.chatModel.hideChatWindowOverlay();
                  gFFI.chatModel.mobileClearClientUnread(
                      gFFI.chatModel.currentKey.connId);
                }
              }
            }),
          ),
          body: _pages.elementAt(_selectedIndex),
        ));
  }

  Widget appTitle() {
    final currentUser = gFFI.chatModel.currentUser;
    final currentKey = gFFI.chatModel.currentKey;
    if (isChatPageCurrentTab &&
        currentUser != null &&
        currentKey.peerId.isNotEmpty) {
      final connected =
          gFFI.serverModel.clients.any((e) => e.id == currentKey.connId);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Tooltip(
            message: currentKey.isOut
                ? translate('Outgoing connection')
                : translate('Incoming connection'),
            child: Icon(
              currentKey.isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${currentUser.firstName}   ${currentUser.id}",
                  ),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 133, 246, 199)),
                    ).marginSymmetric(horizontal: 2),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (kAppModeShareOnly) {
      return Obx(() {
        final localIp = bind.mainGetOptionSync(key: 'local-ip-addr');
        final hasIpv6 = localIp.contains(':');
        final ipLabel = hasIpv6 ? 'IPv6' : 'IPv4';
        final udpEnabled = bind.mainGetOptionSync(key: kOptionDisableUdp) != 'Y';
        final udpLabel = udpEnabled ? 'UDP' : 'TCP';
        // ignore: unused_local_variable
        final _ = stateGlobal.svcStatus.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                bind.mainGetAppNameSync(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(ipLabel),
            const SizedBox(width: 8),
            Text(udpLabel),
          ],
        );
      });
    }
    return Obx(() {
      final localIp = bind.mainGetOptionSync(key: 'local-ip-addr');
      final hasIpv6 = localIp.contains(':');
      final ipLabel = hasIpv6 ? 'IPv6' : 'IPv4';
      final udpEnabled = bind.mainGetOptionSync(key: kOptionDisableUdp) != 'Y';
      final udpLabel = udpEnabled ? 'UDP' : 'TCP';
      final name = AppAuthService().currentUserName.value;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(ipLabel),
          const SizedBox(width: 8),
          Text(udpLabel),
        ],
      );
    });
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      // backgroundColor: MyTheme.grayBg,
      appBar: AppBar(
        centerTitle: true,
        title: Text("${bind.mainGetAppNameSync()} (Preview)"),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "rustdesk://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id, 
        isFileTransfer: isFileTransfer, 
        isViewCamera: isViewCamera, 
        isTerminal: isTerminal,
        password: password);
    }
  }
}
