import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/app_auth_service.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/desktop/widgets/material_mod_popup_menu.dart'
    as mod_menu;
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';
import 'desktop_login_page.dart' as desktop_login;
import 'login_tab_page.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;
  bool _loginStatusDialogShowing = false;

  final RxBool _editHover = false.obs;
  final RxBool _passwordVisible = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  // New layout state
  final ValueNotifier<String> _selectedNav = ValueNotifier('home');
  // Which settings sub-tab to show when the embedded settings page is selected.
  final ValueNotifier<SettingsTabKey> _settingsTabKey =
      ValueNotifier(SettingsTabKey.general);
  final IDTextEditingController _homeRemoteIdController =
      IDTextEditingController();
  final RxBool _connectMenuOpen = false.obs;

  // Recent sessions page state
  final TextEditingController _recentSearchCtrl = TextEditingController();
  final ValueNotifier<String> _recentSearch = ValueNotifier('');
  final ValueNotifier<String> _recentTimeFilter = ValueNotifier('all');
  final ValueNotifier<String> _recentTypeFilter = ValueNotifier('all');

  // My devices page state
  final TextEditingController _devicesSearchCtrl = TextEditingController();
  final ValueNotifier<String> _devicesSearch = ValueNotifier('');
  final ValueNotifier<String> _devicesTimeFilter = ValueNotifier('all');
  final ValueNotifier<String> _devicesTypeFilter = ValueNotifier('all');
  // Devices fetched from the server for the logged-in account.
  // null = not loaded yet; [] = loaded but empty.
  final ValueNotifier<List<MyDevice>?> _myDevices = ValueNotifier(null);
  final ValueNotifier<bool> _myDevicesLoading = ValueNotifier(false);
  final ValueNotifier<String?> _myDevicesError = ValueNotifier(null);

  Future<void> _loadMyDevices() async {
    if (_myDevicesLoading.value) return;
    _myDevicesLoading.value = true;
    _myDevicesError.value = null;
    try {
      if (AppAuthService().currentUserName.value.isEmpty) {
        _myDevices.value = [];
        _myDevicesError.value = translate('Not logged in');
        return;
      }
      final list = await AppAuthService().fetchMyDevices();
      if (list == null) {
        _myDevicesError.value = translate('Failed');
        _myDevices.value ??= [];
      } else {
        _myDevices.value =
            list.map((e) => MyDevice.fromJson(e)).toList();
      }
    } finally {
      _myDevicesLoading.value = false;
    }
  }

  // Recent sessions (server-backed). null = not loaded yet.
  final ValueNotifier<List<MySession>?> _mySessions = ValueNotifier(null);
  final ValueNotifier<bool> _mySessionsLoading = ValueNotifier(false);
  final ValueNotifier<String?> _mySessionsError = ValueNotifier(null);

  Future<void> _loadMySessions() async {
    if (_mySessionsLoading.value) return;
    _mySessionsLoading.value = true;
    _mySessionsError.value = null;
    try {
      if (AppAuthService().currentUserName.value.isEmpty) {
        _mySessions.value = [];
        _mySessionsError.value = translate('Not logged in');
        return;
      }
      final list = await AppAuthService().fetchMySessions();
      if (list == null) {
        _mySessionsError.value = translate('Failed');
        _mySessions.value ??= [];
      } else {
        _mySessions.value = list.map((e) => MySession.fromJson(e)).toList();
      }
    } finally {
      _mySessionsLoading.value = false;
    }
  }

  // Favorites (server-backed). null = not loaded yet.
  final ValueNotifier<List<MyFavorite>?> _myFavorites = ValueNotifier(null);
  final ValueNotifier<bool> _myFavoritesLoading = ValueNotifier(false);
  final ValueNotifier<String?> _myFavoritesError = ValueNotifier(null);

  Future<void> _loadMyFavorites() async {
    if (_myFavoritesLoading.value) return;
    _myFavoritesLoading.value = true;
    _myFavoritesError.value = null;
    try {
      if (AppAuthService().currentUserName.value.isEmpty) {
        _myFavorites.value = [];
        _myFavoritesError.value = translate('Not logged in');
        return;
      }
      final list = await AppAuthService().fetchMyFavorites();
      if (list == null) {
        _myFavoritesError.value = translate('Failed');
        _myFavorites.value ??= [];
      } else {
        _myFavorites.value =
            list.map((e) => MyFavorite.fromJson(e)).toList();
      }
    } finally {
      _myFavoritesLoading.value = false;
    }
  }

  Future<void> _toggleFavorite(String peerId, bool currentlyFav) async {
    if (peerId.isEmpty) return;
    final ok = currentlyFav
        ? await AppAuthService().removeFavorite(peerId)
        : await AppAuthService().addFavorite(peerId);
    if (ok) {
      showToast(translate(currentlyFav ? 'Successful' : 'Added to favorites'));
      await _loadMyFavorites();
    } else {
      showToast(translate('Failed'));
    }
  }

  // Favorites page state
  final TextEditingController _favSearchCtrl = TextEditingController();
  final ValueNotifier<String> _favSearch = ValueNotifier('');
  final ValueNotifier<String> _favGroupFilter = ValueNotifier('all');
  final ValueNotifier<String> _favTypeFilter = ValueNotifier('all');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    return _buildBlock(
      child: Container(
        color: const Color(0xFFF3F5F8),
        constraints: const BoxConstraints(minWidth: 900, minHeight: 560),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildLeftPane(context),
            if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  // ---------------------------------------------------------------------------
  // New layout: Left sidebar
  // ---------------------------------------------------------------------------

  Widget buildLeftPane(BuildContext context) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Color(0xFFEDEFF3), width: 1),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: _buildSidebarUserCard(context),
          ),
          _buildSidebarNav(context),
          const Spacer(),
          if (!bind.isDisableSettings())
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: _buildHelpCenterCard(context),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebarUserCard(BuildContext context) {
    return Obx(() {
      final currentUserName = AppAuthService().currentUserName.value;
      final loggedIn = currentUserName.isNotEmpty;
      return GestureDetector(
        onTap: bind.isDisableAccount()
            ? null
            : () => _openSettings(SettingsTabKey.account),
        child: MouseRegion(
          cursor: bind.isDisableAccount()
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        MyTheme.accent,
                        MyTheme.accent.withOpacity(0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.person, color: Colors.white, size: 26),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loggedIn ? currentUserName : translate('Your Desktop'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: loggedIn
                              ? const Color(0xFFD7E4FF)
                              : const Color(0xFFE6E8EC),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          loggedIn
                              ? translate('Logged in')
                              : translate('Not logged in'),
                          style: TextStyle(
                            fontSize: 10,
                            color: loggedIn
                                ? MyTheme.accent
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  // Show the settings as a sub-page of the home page (shared sidebar) instead
  // of opening it in a separate tab.
  void _openSettings([SettingsTabKey? key]) {
    final target = key ??
        (DesktopSettingPage.tabKeys.isNotEmpty
            ? DesktopSettingPage.tabKeys.first
            : SettingsTabKey.general);
    _settingsTabKey.value = target;
    _selectedNav.value = 'settings';
  }

  Widget _buildSettingsPage(BuildContext context) {
    return ValueListenableBuilder<SettingsTabKey>(
      valueListenable: _settingsTabKey,
      builder: (_, tabKey, __) => DesktopSettingPage(
        // Re-create the page when the target tab changes so it opens on it.
        key: ValueKey('embedded-settings-$tabKey'),
        initialTabkey: tabKey,
        embedded: true,
      ),
    );
  }

  Widget _buildSidebarNav(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _selectedNav,
      builder: (_, selected, __) {
        return Column(
          key: _childKey,
          children: [
            _navItem(Icons.home_outlined, translate('Home'), 'home', selected),
            _navItem(Icons.desktop_windows_outlined, translate('My devices'),
                'devices', selected),
            _navItem(Icons.history, translate('Recent sessions'), 'recent',
                selected),
            _navItem(Icons.star_border, translate('Favorites'), 'favorites',
                selected),
            _navItem(Icons.folder_outlined, translate('File Transfer'), 'file',
                selected),
            if (!bind.isDisableSettings())
              _navItem(Icons.settings_outlined, translate('Settings'),
                  'settings', selected),
          ],
        );
      },
    );
  }

  Widget _navItem(
      IconData icon, String label, String key, String selected) {
    final isSelected = key == selected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (key == 'settings') {
            _openSettings();
            return;
          }
          _selectedNav.value = key;
          if (key == 'devices') _loadMyDevices();
          if (key == 'recent') {
            _loadMySessions();
            // 同步收藏数据，使"最近连接"中的收藏星标能反映当前收藏状态
            _loadMyFavorites();
          }
          if (key == 'favorites') _loadMyFavorites();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFEFF4FF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: isSelected
                    ? MyTheme.accent
                    : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Colors.black
                      : const Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _platformIcon(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('windows')) return Icons.window;
    if (p.contains('mac') || p.contains('osx')) return Icons.laptop_mac;
    if (p.contains('linux')) return Icons.computer;
    if (p.contains('android')) return Icons.smartphone;
    if (p.contains('ios')) return Icons.phone_iphone;
    return Icons.devices_other;
  }

  Widget _buildHelpCenterCard(BuildContext context) {
    final RxBool hover = false.obs;
    return Obx(() => InkWell(
          onTap: () async {
            try {
              await launchUrl(Uri.parse('https://jyyxt.cloud/docs/tech'));
            } catch (_) {}
          },
          onHover: (v) => hover.value = v,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: hover.value
                  ? const Color(0xFFEFF4FF)
                  : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEDEFF3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child:
                      Icon(Icons.shield_outlined, color: MyTheme.accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translate('Help Center'),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        translate('Get help and support'),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFF9CA3AF)),
              ],
            ),
          ),
        ));
  }

  // ---------------------------------------------------------------------------
  // New layout: Right pane
  // ---------------------------------------------------------------------------

  Widget buildRightPane(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F5F8),
      child: ValueListenableBuilder<String>(
        valueListenable: _selectedNav,
        builder: (_, selected, __) {
          Widget body;
          if (selected == 'devices') {
            body = _buildMyDevicesPage(context);
          } else if (selected == 'recent') {
            body = _buildRecentSessionsPage(context);
          } else if (selected == 'favorites') {
            body = _buildFavoritesPage(context);
          } else if (selected == 'file') {
            body = _comingSoonPanel(
                translate('File Transfer'), Icons.folder_outlined);
          } else if (selected == 'settings') {
            body = _buildSettingsPage(context);
          } else {
            body = _homeRightPane(context);
          }
          return Column(
            children: [
              Expanded(child: body),
              const Divider(height: 1, color: Color(0xFFEDEFF3)),
              Container(
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: OnlineStatusWidget()),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _homeRightPane(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _buildControlRemoteCard(context)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildLocalDeviceCard(context)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Obx(() => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: buildHelpCards(stateGlobal.updateUrl.value),
              )),
          _buildRecentPeersSection(context),
        ],
      ),
    );
  }

  Widget _comingSoonPanel(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            translate('Coming soon'),
            style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _buildControlRemoteCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate('Control Remote Desktop'),
            style:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            translate('home_control_remote_tip'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _homeRemoteIdController,
                  inputFormatters: [IDTextInputFormatter()],
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: translate('Enter Remote ID'),
                    hintStyle: const TextStyle(
                        color: Color(0xFF9CA3AF), fontSize: 14),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: MyTheme.accent, width: 1.4),
                    ),
                  ),
                  onSubmitted: (_) => _doConnect(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: () => _doConnect(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyTheme.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    translate('Connect'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildConnectMenuButton(context),
            ],
          ),
        ],
      ),
    );
  }

  void _doConnect({bool isFileTransfer = false}) {
    final id = _homeRemoteIdController.id;
    if (id.isEmpty) return;
    bind.mainSetLocalOption(
      key: '$_kRecentConnectPrefix$id',
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    connect(context, id, isFileTransfer: isFileTransfer);
  }

  Widget _buildConnectMenuButton(BuildContext context) {
    return Container(
      height: 46,
      width: 46,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Tooltip(
        message: translate('More'),
        child: Builder(
          builder: (btnContext) {
            return Obx(() => InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    _connectMenuOpen.value = true;
                    final pos = _menuPositionFromButton(btnContext);
                    await mod_menu
                        .showMenu(
                          context: context,
                          position: pos,
                          elevation: 8,
                          items: [
                            (
                              'Transfer file',
                              () => _doConnect(isFileTransfer: true),
                            ),
                          ]
                              .map((e) => MenuEntryButton<String>(
                                    childBuilder: (TextStyle? style) => Text(
                                      translate(e.$1),
                                      style: style,
                                    ),
                                    proc: () => e.$2(),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: kDesktopMenuPadding.left),
                                    dismissOnClicked: true,
                                  ))
                              .map((e) => e.build(
                                  context,
                                  const MenuConfig(
                                      commonColor:
                                          CustomPopupMenuTheme.commonColor,
                                      height: CustomPopupMenuTheme.height,
                                      dividerHeight:
                                          CustomPopupMenuTheme.dividerHeight)))
                              .expand((i) => i)
                              .toList(),
                        )
                        .then((_) => _connectMenuOpen.value = false);
                  },
                  child: Center(
                    child: _connectMenuOpen.value
                        ? Transform.rotate(
                            angle: pi,
                            child: Icon(IconFont.more,
                                size: 16, color: const Color(0xFF6B7280)),
                          )
                        : Icon(IconFont.more,
                            size: 16, color: const Color(0xFF6B7280)),
                  ),
                ));
          },
        ),
      ),
    );
  }

  Widget _buildLocalDeviceCard(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, _) {
          final showOneTime = model.approveMode != 'click' &&
              model.verificationMethod != kUsePermanentPassword;
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(translate('Local ID'),
                        style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF374151),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: translate('local_id_tip'),
                      child: const Icon(Icons.info_outline,
                          size: 14, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onDoubleTap: () {
                    Clipboard.setData(
                        ClipboardData(text: model.serverId.text));
                    showToast(translate('Copied'));
                  },
                  child: Text(
                    model.serverId.text.isEmpty ? '---' : model.serverId.text,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: MyTheme.accent,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(translate('One-time Password'),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: translate('one_time_password_tip'),
                      child: const Icon(Icons.info_outline,
                          size: 12, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onDoubleTap: () {
                          if (showOneTime) {
                            Clipboard.setData(ClipboardData(
                                text: model.serverPasswd.text));
                            showToast(translate('Copied'));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F6F8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Obx(() => Text(
                                showOneTime && !_passwordVisible.value
                                    ? '•' *
                                        (model.serverPasswd.text.isEmpty
                                            ? 6
                                            : model.serverPasswd.text.length)
                                    : (model.serverPasswd.text.isEmpty
                                        ? '------'
                                        : model.serverPasswd.text),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              )),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (showOneTime)
                      Obx(() => _smallIconBtn(
                            _passwordVisible.value
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            tooltip: _passwordVisible.value
                                ? translate('Hide Password')
                                : translate('Show Password'),
                            onTap: () => _passwordVisible.toggle(),
                          )),
                    if (showOneTime)
                      _smallIconBtn(
                        Icons.refresh,
                        tooltip: translate('Refresh Password'),
                        onTap: () => bind.mainUpdateTemporaryPassword(),
                      ),
                    _smallIconBtn(
                      Icons.content_copy_outlined,
                      tooltip: translate('Copy'),
                      onTap: () {
                        Clipboard.setData(ClipboardData(
                            text: model.serverPasswd.text));
                        showToast(translate('Copied'));
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _peerCardMenuButton(BuildContext context, Peer peer) {
    return Tooltip(
      message: translate('More'),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Builder(
          builder: (btnContext) => InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final entries = await RecentPeerCard(peer: peer)
                  .buildPopupMenuEntry(context);
              if (entries.isEmpty) return;
              final pos = _menuPositionFromButton(btnContext);
              await mod_menu.showMenu(
                context: context,
                position: pos,
                items: entries,
                elevation: 8,
              );
            },
            child: SizedBox(
              height: 34,
              width: 34,
              child: Center(
                child: Icon(IconFont.more,
                    size: 14, color: const Color(0xFF6B7280)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  RelativeRect _menuPositionFromButton(BuildContext btnContext) {
    final renderBox = btnContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(btnContext).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) {
      return RelativeRect.fill;
    }
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final size = renderBox.size;
    final overlaySize = overlay.size;
    final left = topLeft.dx;
    final top = topLeft.dy + size.height;
    final right = overlaySize.width - (topLeft.dx + size.width);
    return RelativeRect.fromLTRB(left, top, right, 0);
  }

  Widget _smallIconBtn(IconData icon,
      {required VoidCallback onTap, String? tooltip, Color? color}) {
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: color ?? const Color(0xFF6B7280)),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
  }

  // ---------------------------------------------------------------------------
  // Recent sessions: full table-style page
  // ---------------------------------------------------------------------------

  Widget _buildRecentSessionsPage(BuildContext context) {
    return ValueListenableBuilder<List<MySession>?>(
      valueListenable: _mySessions,
      builder: (_, sessions, __) {
        if (sessions == null && !_mySessionsLoading.value) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _loadMySessions());
        }
        // 确保收藏数据已加载，使收藏星标状态正确显示
        if (_myFavorites.value == null && !_myFavoritesLoading.value) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _loadMyFavorites());
        }
        return ValueListenableBuilder<bool>(
          valueListenable: _mySessionsLoading,
          builder: (_, loading, __) {
            return ValueListenableBuilder<String?>(
              valueListenable: _mySessionsError,
              builder: (_, error, __) {
                return ValueListenableBuilder<String>(
                  valueListenable: _recentSearch,
                  builder: (_, query, __) {
                    return ValueListenableBuilder<String>(
                      valueListenable: _recentTimeFilter,
                      builder: (_, timeFilter, __) {
                        return ValueListenableBuilder<String>(
                          valueListenable: _recentTypeFilter,
                          builder: (_, typeFilter, __) {
                            final all = sessions ?? <MySession>[];
                            final filtered = _filterMySessions(
                                all, query, timeFilter, typeFilter);
                            return Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _recentSessionsHeader(context, filtered.length),
                                  const SizedBox(height: 14),
                                  _recentSessionsToolbar(context, filtered.length),
                                  const SizedBox(height: 14),
                                  Expanded(
                                    child: _recentSessionsTable(context, filtered,
                                        loading, error, sessions == null),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  List<MySession> _filterMySessions(List<MySession> all, String query,
      String timeFilter, String typeFilter) {
    final q = query.trim().toLowerCase();
    final now = DateTime.now();
    return all.where((s) {
      if (q.isNotEmpty) {
        final matches = s.remoteId.toLowerCase().contains(q) ||
            s.username.toLowerCase().contains(q);
        if (!matches) return false;
      }
      if (typeFilter != 'all') {
        final isMobile = s.remoteClientType != 'desktop';
        if (typeFilter == 'mobile' && !isMobile) return false;
        if (typeFilter == 'desktop' && isMobile) return false;
      }
      if (timeFilter != 'all') {
        final dt = s.startDate;
        if (dt == null) return false;
        switch (timeFilter) {
          case 'today':
            if (!(dt.year == now.year &&
                dt.month == now.month &&
                dt.day == now.day)) return false;
            break;
          case 'week':
            if (now.difference(dt).inDays >= 7) return false;
            break;
          case 'month':
            if (now.difference(dt).inDays >= 30) return false;
            break;
        }
      }
      return true;
    }).toList();
  }

  Widget _recentSessionsHeader(BuildContext context, int count) {
    return Row(
      children: [
        Text(
          translate('Recent sessions'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Text(
          '($count)',
          style: const TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }

  Widget _recentSessionsToolbar(BuildContext context, int count) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: TextField(
              controller: _recentSearchCtrl,
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => _recentSearch.value = v,
              decoration: InputDecoration(
                isDense: true,
                hintText: translate('Search device or ID'),
                hintStyle: const TextStyle(
                    color: Color(0xFF9CA3AF), fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: Color(0xFF9CA3AF)),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _filterDropdown(
          value: _recentTimeFilter,
          items: [
            ('all', translate('All time')),
            ('today', translate('Today')),
            ('week', translate('This week')),
            ('month', translate('This month')),
          ],
        ),
        const SizedBox(width: 12),
        _filterDropdown(
          value: _recentTypeFilter,
          items: [
            ('all', translate('All types')),
            ('desktop', translate('Desktop')),
            ('mobile', translate('Mobile')),
          ],
        ),
        const SizedBox(width: 12),
        _outlineButton(
          icon: Icons.refresh,
          label: translate('Refresh'),
          onTap: () => _loadMySessions(),
        ),
        const SizedBox(width: 12),
        _outlineButton(
          icon: Icons.delete_outline,
          label: translate('Clear records'),
          onTap: count == 0 ? null : () => _confirmClearRecent(context),
        ),
      ],
    );
  }

  Widget _filterDropdown({
    required ValueNotifier<String> value,
    required List<(String, String)> items,
  }) {
    return ValueListenableBuilder<String>(
      valueListenable: value,
      builder: (_, current, __) {
        return Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: current,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down,
                  size: 18, color: Color(0xFF6B7280)),
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF374151)),
              items: items
                  .map((e) => DropdownMenuItem(
                        value: e.$1,
                        child: Text(e.$2),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) value.value = v;
              },
            ),
          ),
        );
      },
    );
  }

  Widget _outlineButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final fg = enabled ? const Color(0xFF374151) : const Color(0xFF9CA3AF);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500, color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentSessionsTable(BuildContext context, List<MySession> sessions,
      bool loading, String? error, bool notLoaded) {
    Widget content;
    if (sessions.isEmpty && (loading || notLoaded)) {
      content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (sessions.isEmpty && error != null) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(error, style: const TextStyle(color: Color(0xFF9CA3AF))),
            const SizedBox(height: 12),
            _outlineButton(
              icon: Icons.refresh,
              label: translate('Retry'),
              onTap: () => _loadMySessions(),
            ),
          ],
        ),
      );
    } else if (sessions.isEmpty) {
      content = Center(
        child: Text(
          translate('No recent sessions'),
          style: const TextStyle(color: Color(0xFF9CA3AF)),
        ),
      );
    } else {
      content = ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: sessions.length + 1,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
        itemBuilder: (_, i) {
          if (i == sessions.length) return _recentTableFooter();
          return _recentTableRow(context, sessions[i]);
        },
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _recentTableHeader(),
          const Divider(height: 1, color: Color(0xFFEDEFF3)),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _recentTableHeader() {
    const style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF6B7280),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(translate('Device'), style: style)),
          Expanded(flex: 2, child: Text(translate('Target ID'), style: style)),
          Expanded(
              flex: 2,
              child: Text(translate('Connection type'), style: style)),
          Expanded(flex: 1, child: Text(translate('Status'), style: style)),
          Expanded(
              flex: 2, child: Text(translate('Connect time'), style: style)),
          Expanded(flex: 1, child: Text(translate('Duration'), style: style)),
          SizedBox(
            width: 160,
            child: Text(translate('Actions'), style: style),
          ),
        ],
      ),
    );
  }

  Widget _recentTableFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 14, color: Color(0xFF22C55E)),
          const SizedBox(width: 6),
          Text(
            translate('End of list'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _recentTableRow(BuildContext context, MySession session) {
    final remoteId = session.remoteId;
    final displayName = remoteId.isEmpty ? '---' : remoteId;
    final active = session.active;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Device
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MyTheme.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_clientTypeIcon(session.remoteClientType),
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Target ID
          Expanded(
            flex: 2,
            child: Text(
              _formatPeerId(remoteId),
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF374151)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Connection type (direction)
          Expanded(
            flex: 2,
            child: Text(
              _directionLabel(session.direction),
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF374151)),
            ),
          ),
          // Status (session active vs ended)
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  active
                      ? translate('In session')
                      : translate('Ended'),
                  style: TextStyle(
                    fontSize: 13,
                    color: active
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          // Connect time
          Expanded(
            flex: 2,
            child: Text(
              _formatIsoTime(session.startTime),
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF374151)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Duration
          Expanded(
            flex: 1,
            child: Text(
              _formatDurationSecs(session.durationSec),
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF374151)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Actions
          SizedBox(
            width: 160,
            child: Row(
              children: [
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    onPressed: remoteId.isEmpty
                        ? null
                        : () => _connectFromRecent(context, remoteId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyTheme.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      translate('Reconnect'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 收藏星标：根据当前收藏状态显示实心/空心，再次点击可取消收藏
                ValueListenableBuilder<List<MyFavorite>?>(
                  valueListenable: _myFavorites,
                  builder: (_, favorites, __) {
                    final isFav = remoteId.isNotEmpty &&
                        (favorites?.any((f) => f.peerId == remoteId) ?? false);
                    return _smallIconBtn(
                      isFav ? Icons.star : Icons.star_border,
                      tooltip: translate(isFav
                          ? 'Remove from Favorites'
                          : 'Add to Favorites'),
                      color: isFav ? const Color(0xFFFBBF24) : null,
                      onTap: remoteId.isEmpty
                          ? () {}
                          : () => _toggleFavorite(remoteId, isFav),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _directionLabel(String direction) {
    return direction == 'incoming'
        ? translate('Incoming')
        : translate('Outgoing');
  }

  String _formatDurationSecs(int secs) {
    if (secs <= 0) return '--';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  // Group the peer id into blocks of 3 digits for readability (e.g. 252 844 127).
  String _formatPeerId(String id) {
    if (id.isEmpty || id.contains(RegExp(r'[^0-9]'))) return id;
    final buf = StringBuffer();
    for (int i = 0; i < id.length; i++) {
      if (i > 0 && (id.length - i) % 3 == 0) buf.write(' ');
      buf.write(id[i]);
    }
    return buf.toString();
  }

  static const String _kRecentConnectPrefix = 'recent-connect-at-';

  void _connectFromRecent(BuildContext context, String peerId) {
    bind.mainSetLocalOption(
      key: '$_kRecentConnectPrefix$peerId',
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    connect(context, peerId);
    setState(() {});
  }

  Future<void> _confirmClearRecent(BuildContext context) async {
    final sessions = _mySessions.value ?? [];
    if (sessions.isEmpty) return;
    deleteConfirmDialog(() async {
      final ok = await AppAuthService().clearMySessions();
      if (ok) {
        _mySessions.value = [];
        showToast(translate('Successful'));
      } else {
        showToast(translate('Failed'));
      }
    }, translate('Clear records'));
  }

  // ---------------------------------------------------------------------------
  // My devices: table-style page (same layout as Recent sessions, but without
  // the clear-records button; the table drops connection type / status /
  // connect time / duration / actions and adds device type & last login time).
  // ---------------------------------------------------------------------------

  Widget _buildMyDevicesPage(BuildContext context) {
    return ValueListenableBuilder<List<MyDevice>?>(
      valueListenable: _myDevices,
      builder: (_, devices, __) {
        // Trigger an initial load the first time the page is shown.
        if (devices == null && !_myDevicesLoading.value) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _loadMyDevices());
        }
        return ValueListenableBuilder<bool>(
          valueListenable: _myDevicesLoading,
          builder: (_, loading, __) {
            return ValueListenableBuilder<String?>(
              valueListenable: _myDevicesError,
              builder: (_, error, __) {
                return ValueListenableBuilder<String>(
                  valueListenable: _devicesSearch,
                  builder: (_, query, __) {
                    return ValueListenableBuilder<String>(
                      valueListenable: _devicesTimeFilter,
                      builder: (_, timeFilter, __) {
                        return ValueListenableBuilder<String>(
                          valueListenable: _devicesTypeFilter,
                          builder: (_, typeFilter, __) {
                            final all = devices ?? <MyDevice>[];
                            final filtered = _filterMyDevices(
                                all, query, timeFilter, typeFilter);
                            return Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _myDevicesHeader(context, filtered.length),
                                  const SizedBox(height: 14),
                                  _myDevicesToolbar(context),
                                  const SizedBox(height: 14),
                                  Expanded(
                                    child: _myDevicesTable(context, filtered,
                                        loading, error, devices == null),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  List<MyDevice> _filterMyDevices(List<MyDevice> all, String query,
      String timeFilter, String typeFilter) {
    final q = query.trim().toLowerCase();
    final now = DateTime.now();
    return all.where((d) {
      if (q.isNotEmpty) {
        final matches = d.id.toLowerCase().contains(q) ||
            d.username.toLowerCase().contains(q) ||
            d.ip.toLowerCase().contains(q);
        if (!matches) return false;
      }
      if (typeFilter != 'all') {
        final isMobile = d.clientType != 'desktop';
        if (typeFilter == 'mobile' && !isMobile) return false;
        if (typeFilter == 'desktop' && isMobile) return false;
      }
      if (timeFilter != 'all') {
        final dt = d.lastSeenDate;
        if (dt == null) return false;
        switch (timeFilter) {
          case 'today':
            if (!(dt.year == now.year &&
                dt.month == now.month &&
                dt.day == now.day)) return false;
            break;
          case 'week':
            if (now.difference(dt).inDays >= 7) return false;
            break;
          case 'month':
            if (now.difference(dt).inDays >= 30) return false;
            break;
        }
      }
      return true;
    }).toList();
  }

  Widget _myDevicesHeader(BuildContext context, int count) {
    return Row(
      children: [
        Text(
          translate('My devices'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Text(
          '($count)',
          style: const TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }

  Widget _myDevicesToolbar(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: TextField(
              controller: _devicesSearchCtrl,
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => _devicesSearch.value = v,
              decoration: InputDecoration(
                isDense: true,
                hintText: translate('Search device or ID'),
                hintStyle: const TextStyle(
                    color: Color(0xFF9CA3AF), fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: Color(0xFF9CA3AF)),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _filterDropdown(
          value: _devicesTimeFilter,
          items: [
            ('all', translate('All time')),
            ('today', translate('Today')),
            ('week', translate('This week')),
            ('month', translate('This month')),
          ],
        ),
        const SizedBox(width: 12),
        _filterDropdown(
          value: _devicesTypeFilter,
          items: [
            ('all', translate('All types')),
            ('desktop', translate('Desktop')),
            ('mobile', translate('Mobile')),
          ],
        ),
        const SizedBox(width: 12),
        _outlineButton(
          icon: Icons.refresh,
          label: translate('Refresh'),
          onTap: () => _loadMyDevices(),
        ),
      ],
    );
  }

  Widget _myDevicesTable(BuildContext context, List<MyDevice> devices,
      bool loading, String? error, bool notLoaded) {
    Widget content;
    if (devices.isEmpty && (loading || notLoaded)) {
      content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (devices.isEmpty && error != null) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off,
                size: 40, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(error,
                style: const TextStyle(color: Color(0xFF9CA3AF))),
            const SizedBox(height: 12),
            _outlineButton(
              icon: Icons.refresh,
              label: translate('Retry'),
              onTap: () => _loadMyDevices(),
            ),
          ],
        ),
      );
    } else if (devices.isEmpty) {
      content = Center(
        child: Text(
          translate('No devices'),
          style: const TextStyle(color: Color(0xFF9CA3AF)),
        ),
      );
    } else {
      content = ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: devices.length + 1,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
        itemBuilder: (_, i) {
          if (i == devices.length) return _recentTableFooter();
          return _myDevicesTableRow(context, devices[i]);
        },
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _myDevicesTableHeader(),
          const Divider(height: 1, color: Color(0xFFEDEFF3)),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _myDevicesTableHeader() {
    const style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF6B7280),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(translate('Device'), style: style)),
          Expanded(flex: 2, child: Text(translate('Target ID'), style: style)),
          Expanded(
              flex: 2, child: Text(translate('Device type'), style: style)),
          Expanded(
              flex: 2,
              child: Text(translate('Last login time'), style: style)),
        ],
      ),
    );
  }

  Widget _myDevicesTableRow(BuildContext context, MyDevice device) {
    final displayName =
        device.username.isNotEmpty ? device.username : device.id;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Device
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MyTheme.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_clientTypeIcon(device.clientType),
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (device.online)
                        Text(
                          translate('Online'),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF22C55E)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Target ID
          Expanded(
            flex: 2,
            child: Text(
              _formatPeerId(device.id),
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Device type
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _clientTypeLabel(device.clientType),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MyTheme.accent),
                ),
              ),
            ),
          ),
          // Last login time
          Expanded(
            flex: 2,
            child: Text(
              _formatIsoTime(device.lastSeen),
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _clientTypeIcon(String clientType) {
    return clientType == 'desktop'
        ? Icons.desktop_windows
        : Icons.smartphone;
  }

  String _clientTypeLabel(String clientType) {
    switch (clientType) {
      case 'desktop':
        return translate('Desktop');
      case 'full':
      case 'share_only':
        return translate('Mobile');
      default:
        return translate('Unknown');
    }
  }

  String _formatIsoTime(String iso) {
    if (iso.isEmpty) return translate('No record');
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return translate('No record');
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _buildRecentPeersSection(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.peerTabModel,
      child: ChangeNotifierProvider.value(
        value: gFFI.recentPeersModel,
        child: Consumer<Peers>(
          builder: (_, peers, __) {
            bind.mainLoadRecentPeers();
            return Obx(() {
              final query = peerSearchText.value.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? peers.peers
                  : peers.peers.where((p) {
                      return p.id.toLowerCase().contains(query) ||
                          p.username.toLowerCase().contains(query) ||
                          p.hostname.toLowerCase().contains(query) ||
                          p.alias.toLowerCase().contains(query);
                    }).toList();
              // Keep the peer tab model's cached list in sync with what we
              // actually render so "Select All" and the selected-count match.
              Provider.of<PeerTabModel>(context, listen: false)
                  .setCurrentTabCachedPeers(filtered);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Consumer<PeerTabModel>(
                    builder: (context, m, _) => m.multiSelectionMode
                        ? _buildMultiSelectActionBar(context, m, filtered)
                        : Row(
                            children: [
                              Text(translate('Recent sessions'),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 6),
                              Text('(${filtered.length})',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF6B7280))),
                              const Spacer(),
                              const PeerSearchBar(),
                              const SizedBox(width: 8),
                              _multiSelectToggle(context),
                              const SizedBox(width: 4),
                              const PeerViewDropdown(),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(36),
                      alignment: Alignment.center,
                      child: Text(
                        query.isEmpty
                            ? translate('No recent sessions')
                            : translate('No matching devices'),
                        style: const TextStyle(color: Color(0xFF9CA3AF)),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: filtered
                          .take(12)
                          .map((p) => SizedBox(
                                width: 240,
                                child: _bigPeerCard(p),
                              ))
                          .toList(),
                    ),
                ],
              );
            });
          },
        ),
      ),
    );
  }

  Widget _buildMultiSelectActionBar(
      BuildContext context, PeerTabModel model, List<Peer> visible) {
    final selectedCount = model.selectedPeers.length;
    final hasSelection = selectedCount > 0;
    final allSelected = selectedCount > 0 && selectedCount >= visible.length;

    Future<void> doDelete() async {
      final peers = model.selectedPeers.toList();
      deleteConfirmDialog(() async {
        for (var p in peers) {
          await bind.mainRemovePeer(id: p.id);
        }
        bind.mainLoadRecentPeers();
        model.setMultiSelectionMode(false);
        showToast(translate('Successful'));
      }, translate('Delete'));
    }

    Future<void> doAddToFav() async {
      final peers = model.selectedPeers.toList();
      final favs = (await bind.mainGetFav()).toList();
      for (var p in peers) {
        if (!favs.contains(p.id)) favs.add(p.id);
      }
      await bind.mainStoreFav(favs: favs);
      model.setMultiSelectionMode(false);
      showToast(translate('Successful'));
    }

    void toggleSelectAll() {
      if (allSelected) {
        for (final p in visible.toList()) {
          if (model.isPeerSelected(p.id)) model.select(p);
        }
      } else {
        model.selectAll();
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MyTheme.accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 18, color: MyTheme.accent),
          const SizedBox(width: 8),
          Text(
            '$selectedCount ${translate('Selected')}',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: MyTheme.accent),
          ),
          const Spacer(),
          _actionBarButton(
            icon: allSelected ? Icons.deselect : Icons.select_all,
            label: allSelected
                ? translate('Unselect All')
                : translate('Select All'),
            onTap: visible.isEmpty ? null : toggleSelectAll,
          ),
          const SizedBox(width: 6),
          _actionBarButton(
            icon: Icons.star_border,
            label: translate('Add to Favorites'),
            onTap: hasSelection ? doAddToFav : null,
          ),
          const SizedBox(width: 6),
          _actionBarButton(
            icon: Icons.delete_outline,
            label: translate('Delete'),
            color: Colors.red.shade600,
            onTap: hasSelection ? doDelete : null,
          ),
          const SizedBox(width: 6),
          _actionBarButton(
            icon: Icons.close,
            label: translate('Close'),
            onTap: () => model.setMultiSelectionMode(false),
          ),
        ],
      ),
    );
  }

  Widget _actionBarButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
  }) {
    final enabled = onTap != null;
    final fg = enabled
        ? (color ?? const Color(0xFF374151))
        : const Color(0xFF9CA3AF);
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _multiSelectToggle(BuildContext context) {
    final RxBool hover = false.obs;
    final model = Provider.of<PeerTabModel>(context, listen: false);
    return Tooltip(
      message: translate('Select'),
      child: Obx(() => Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onHover: (v) => hover.value = v,
              onTap: () => model.setMultiSelectionMode(true),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: hover.value
                      ? const Color(0xFFEFF4FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.check_box_outlined,
                  size: 18,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
            ),
          )),
    );
  }

  Widget _bigPeerCard(Peer peer) {
    final displayName = peer.alias.isNotEmpty
        ? peer.alias
        : (peer.username.isNotEmpty && peer.hostname.isNotEmpty
            ? '${peer.username}@${peer.hostname}'
            : (peer.hostname.isNotEmpty ? peer.hostname : peer.id));
    final platformLabel =
        peer.platform.isEmpty ? translate('Unknown') : peer.platform;
    final online = peer.online;

    return Consumer<PeerTabModel>(
      builder: (context, model, _) {
        final isMultiSelect = model.multiSelectionMode;
        final isSelected =
            isMultiSelect && model.selectedPeers.any((p) => p.id == peer.id);

        return GestureDetector(
          onTap: isMultiSelect ? () => model.select(peer) : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Card body ──────────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFEFF4FF)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? MyTheme.accent
                        : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF4FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(_platformIcon(peer.platform),
                              color: MyTheme.accent, size: 22),
                        ),
                        const Spacer(),
                        // Hide the online indicator while the checkbox sits at
                        // the top-right to avoid visual overlap.
                        if (!isMultiSelect) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: online
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            online
                                ? translate('Online')
                                : translate('Offline'),
                            style: TextStyle(
                              fontSize: 11,
                              color: online
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      displayName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF4FF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        platformLabel,
                        style: TextStyle(fontSize: 10, color: MyTheme.accent),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      peer.id,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 34,
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isMultiSelect
                                  ? () => model.select(peer)
                                  : () => _connectFromRecent(context, peer.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isMultiSelect
                                    ? (isSelected
                                        ? MyTheme.accent
                                        : Colors.white)
                                    : MyTheme.accent,
                                foregroundColor: isMultiSelect
                                    ? (isSelected
                                        ? Colors.white
                                        : MyTheme.accent)
                                    : Colors.white,
                                elevation: 0,
                                padding: EdgeInsets.zero,
                                side: isMultiSelect && !isSelected
                                    ? BorderSide(
                                        color: MyTheme.accent.withOpacity(0.4))
                                    : BorderSide.none,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                isMultiSelect
                                    ? (isSelected
                                        ? translate('Selected')
                                        : translate('Select'))
                                    : translate('Connect'),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          if (!isMultiSelect) ...[
                            const SizedBox(width: 6),
                            _peerCardMenuButton(context, peer),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Checkbox overlay (top-right corner) ───────────────
              if (isMultiSelect)
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => model.select(peer),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isSelected ? MyTheme.accent : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? MyTheme.accent
                              : const Color(0xFFD1D5DB),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Favorites: grid-of-cards page
  // ---------------------------------------------------------------------------

  static const List<Color> _kFavCardColors = [
    Color(0xFF22D3EE), // cyan
    Color(0xFFFB923C), // orange
    Color(0xFFA78BFA), // purple
    Color(0xFF60A5FA), // blue
    Color(0xFF34D399), // green
    Color(0xFFF472B6), // pink
    Color(0xFFFBBF24), // amber
    Color(0xFF94A3B8), // slate
  ];

  Color _favCardColor(String peerId) {
    if (peerId.isEmpty) return _kFavCardColors[0];
    final h = peerId.codeUnits.fold<int>(0, (a, b) => (a + b) & 0x7fffffff);
    return _kFavCardColors[h % _kFavCardColors.length];
  }

  Widget _buildFavoritesPage(BuildContext context) {
    return ValueListenableBuilder<List<MyFavorite>?>(
      valueListenable: _myFavorites,
      builder: (_, favorites, __) {
        if (favorites == null && !_myFavoritesLoading.value) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _loadMyFavorites());
        }
        return ValueListenableBuilder<bool>(
          valueListenable: _myFavoritesLoading,
          builder: (_, loading, __) {
            return ValueListenableBuilder<String?>(
              valueListenable: _myFavoritesError,
              builder: (_, error, __) {
                return ValueListenableBuilder<String>(
                  valueListenable: _favSearch,
                  builder: (_, query, __) {
                    return ValueListenableBuilder<String>(
                      valueListenable: _favGroupFilter,
                      builder: (_, groupFilter, __) {
                        return ValueListenableBuilder<String>(
                          valueListenable: _favTypeFilter,
                          builder: (_, typeFilter, __) {
                            final all = favorites ?? <MyFavorite>[];
                            final filtered = _filterFavorites(
                                all, query, groupFilter, typeFilter);
                            return Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _favHeader(context, filtered.length),
                                  const SizedBox(height: 14),
                                  _favToolbar(context, filtered.length),
                                  const SizedBox(height: 14),
                                  Expanded(
                                    child: _favBody(context, filtered, loading,
                                        error, favorites == null),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  List<MyFavorite> _filterFavorites(List<MyFavorite> all, String query,
      String groupFilter, String typeFilter) {
    final q = query.trim().toLowerCase();
    return all.where((f) {
      if (q.isNotEmpty) {
        final matches = f.peerId.toLowerCase().contains(q) ||
            f.alias.toLowerCase().contains(q);
        if (!matches) return false;
      }
      if (groupFilter == 'online' && !f.online) return false;
      if (groupFilter == 'offline' && f.online) return false;
      if (typeFilter != 'all') {
        final isMobile = f.clientType != 'desktop';
        if (typeFilter == 'mobile' && !isMobile) return false;
        if (typeFilter == 'desktop' && isMobile) return false;
      }
      return true;
    }).toList();
  }

  Widget _favHeader(BuildContext context, int count) {
    return Row(
      children: [
        Text(
          translate('Favorites'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF4FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MyTheme.accent),
          ),
        ),
      ],
    );
  }

  Widget _favToolbar(BuildContext context, int count) {
    return Row(
      children: [
        _favChip('all', translate('All')),
        const SizedBox(width: 8),
        _favChip('online', translate('Online')),
        const SizedBox(width: 8),
        _favChip('offline', translate('Offline')),
        const Spacer(),
        SizedBox(
          width: 220,
          height: 38,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: TextField(
              controller: _favSearchCtrl,
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => _favSearch.value = v,
              decoration: InputDecoration(
                isDense: true,
                hintText: translate('Search'),
                hintStyle:
                    const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: Color(0xFF9CA3AF)),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _filterDropdown(
          value: _favTypeFilter,
          items: [
            ('all', translate('All types')),
            ('desktop', translate('Desktop')),
            ('mobile', translate('Mobile')),
          ],
        ),
        const SizedBox(width: 12),
        _favPrimaryButton(
          icon: Icons.add,
          label: translate('Add to Favorites'),
          onTap: () => _selectedNav.value = 'recent',
        ),
      ],
    );
  }

  Widget _favChip(String key, String label) {
    return ValueListenableBuilder<String>(
      valueListenable: _favGroupFilter,
      builder: (_, current, __) {
        final selected = current == key;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _favGroupFilter.value = key,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? MyTheme.accent : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? MyTheme.accent : const Color(0xFFE5E7EB),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: selected ? Colors.white : const Color(0xFF374151),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _favPrimaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: MyTheme.accent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _favBody(BuildContext context, List<MyFavorite> favorites,
      bool loading, String? error, bool notLoaded) {
    if (favorites.isEmpty && (loading || notLoaded)) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (favorites.isEmpty && error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 14),
            Text(error,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            _outlineButton(
              icon: Icons.refresh,
              label: translate('Retry'),
              onTap: () => _loadMyFavorites(),
            ),
          ],
        ),
      );
    }
    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_border,
                size: 56, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 14),
            Text(
              translate('No favorites yet'),
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, constraints) {
        const minCardWidth = 240.0;
        const spacing = 16.0;
        int cols = ((constraints.maxWidth + spacing) / (minCardWidth + spacing))
            .floor();
        if (cols < 1) cols = 1;
        final cardWidth =
            (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return SingleChildScrollView(
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: favorites
                .map((f) => SizedBox(
                      width: cardWidth,
                      child: _favCard(context, f),
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  Widget _favCard(BuildContext context, MyFavorite fav) {
    final displayName = fav.alias.isNotEmpty ? fav.alias : fav.peerId;
    final color = _favCardColor(fav.peerId);
    final online = fav.online;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_clientTypeIcon(fav.clientType),
                    color: color, size: 24),
              ),
              const Spacer(),
              Tooltip(
                message: translate('Remove from Favorites'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _toggleFavorite(fav.peerId, true),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.star,
                        color: Color(0xFFFBBF24), size: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            displayName,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            fav.peerId,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: online
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: online
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      online ? translate('Online') : translate('Offline'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: online
                            ? const Color(0xFF15803D)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 30,
                child: ElevatedButton(
                  onPressed: () => _connectFromRecent(context, fav.peerId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyTheme.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    translate('Connect'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Legacy ID/password board kept for compatibility; no longer used in build.
  // ---------------------------------------------------------------------------

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11, top: 8),
      height: 57,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            decoration: const BoxDecoration(color: MyTheme.accent),
          ).marginOnly(top: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    translate("ID"),
                    style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.color
                            ?.withOpacity(0.5)),
                  ).marginOnly(top: 5),
                  Flexible(
                    child: GestureDetector(
                      onDoubleTap: () {
                        Clipboard.setData(
                            ClipboardData(text: model.serverId.text));
                        showToast(translate("Copied"));
                      },
                      child: TextFormField(
                        controller: model.serverId,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(top: 10, bottom: 10),
                        ),
                        style: TextStyle(
                          fontSize: 22,
                        ),
                      ).workaroundFreezeLinuxMint(),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool visibilityHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 16, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            height: 52,
            decoration: BoxDecoration(color: MyTheme.accent),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                        fontSize: 14, color: textColor?.withOpacity(0.5)),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              Clipboard.setData(
                                  ClipboardData(text: model.serverPasswd.text));
                              showToast(translate("Copied"));
                            }
                          },
                          child: Obx(() => TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            obscureText: showOneTime && !_passwordVisible.value,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.only(top: 14, bottom: 10),
                            ),
                            style: TextStyle(fontSize: 15),
                          ).workaroundFreezeLinuxMint()),
                        ),
                      ),
                      if (showOneTime)
                        Obx(() => InkWell(
                          onTap: () => _passwordVisible.toggle(),
                          onHover: (value) => visibilityHover.value = value,
                          child: Tooltip(
                            message: _passwordVisible.value
                                ? translate('Hide Password')
                                : translate('Show Password'),
                            child: Icon(
                              _passwordVisible.value
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: visibilityHover.value
                                  ? textColor
                                  : Color(0xFFDDDDDD),
                              size: 22,
                            ).marginOnly(right: 4, top: 4),
                          ),
                        )),
                      if (showOneTime || !bind.isDisableSettings())
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            color: Color(0xFFDDDDDD),
                            size: 22,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: '',
                          position: PopupMenuPosition.under,
                          itemBuilder: (context) => [
                            if (showOneTime)
                              PopupMenuItem<String>(
                                value: 'refresh',
                                child: Row(
                                  children: [
                                    Icon(Icons.refresh, size: 20),
                                    SizedBox(width: 8),
                                    Text(translate('Refresh Password')),
                                  ],
                                ),
                              ),
                            if (!bind.isDisableSettings())
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 20),
                                    SizedBox(width: 8),
                                    Text(translate('Change Password')),
                                  ],
                                ),
                              ),
                          ],
                          onSelected: (value) {
                            if (value == 'refresh') {
                              bind.mainUpdateTemporaryPassword();
                            } else if (value == 'edit') {
                              _openSettings(SettingsTabKey.safety);
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeUserInfoCard(BuildContext context) {
    return Obx(() {
      final currentUserName = AppAuthService().currentUserName.value;
      if (currentUserName.isEmpty) {
        return Align(
          alignment: Alignment.center,
          child: Text(
            translate("Your Desktop"),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        );
      }
      return FutureBuilder<Map<String, dynamic>?>(
        future: AppAuthService().getUserInfo(),
        builder: (context, snapshot) {
          final userInfo = snapshot.data;
          final username = userInfo?['username']?.toString() ?? currentUserName;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: GestureDetector(
              onTap: bind.isDisableAccount() ? null : () {
                _openSettings(SettingsTabKey.account);
              },
              child: MouseRegion(
                cursor: bind.isDisableAccount() ? MouseCursor.defer : SystemMouseCursors.click,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            MyTheme.accent,
                            MyTheme.accent.withOpacity(0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 17),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    });
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 20.0, bottom: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            children: [
              if (!isOutgoingOnly) _buildHomeUserInfoCard(context),
            ],
          ),
          SizedBox(
            height: 20.0,
          ),
          if (!isOutgoingOnly)
            Text(
              translate("desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
      // Tick once a second to refresh the elapsed-duration column on the
      // recent sessions page.
      if (_selectedNav.value == 'recent' && mounted) {
        setState(() {});
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);


    // Listen for remote disabled status (WebSocket push)
    ever(stateGlobal.remoteDisabled, (disabled) {
      if (disabled) {
        _showRemoteDisabledDialog();
      } else {
        gFFI.dialogManager.dismissByTag('remote-disabled');
      }
    });
    ever(stateGlobal.appLoginInvalidated, (invalidated) {
      if (invalidated) {
        _showLoginExpiredDialog();
      }
    });

    // 检查登录状态
    _checkLoginStatus();
  }


  void _showRemoteDisabledDialog() {
    if (!mounted) return;
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Row(children: [
          const Icon(Icons.block, color: Colors.redAccent, size: 28),
          const SizedBox(width: 10),
          Text(translate('remote_disabled_title')),
        ]),
        content: Obx(() => Text(
          stateGlobal.remoteDisabledMessage.value.isNotEmpty
              ? stateGlobal.remoteDisabledMessage.value
              : translate('remote_disabled_message'),
        )),
        actions: [],
      );
    }, tag: 'remote-disabled');
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    _selectedNav.dispose();
    _homeRemoteIdController.dispose();
    _recentSearchCtrl.dispose();
    _recentSearch.dispose();
    _recentTimeFilter.dispose();
    _recentTypeFilter.dispose();
    _devicesSearchCtrl.dispose();
    _devicesSearch.dispose();
    _devicesTimeFilter.dispose();
    _devicesTypeFilter.dispose();
    _myDevices.dispose();
    _myDevicesLoading.dispose();
    _myDevicesError.dispose();
    _mySessions.dispose();
    _mySessionsLoading.dispose();
    _mySessionsError.dispose();
    _myFavorites.dispose();
    _myFavoritesLoading.dispose();
    _myFavoritesError.dispose();
    _favSearchCtrl.dispose();
    _favSearch.dispose();
    _favGroupFilter.dispose();
    _favTypeFilter.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
      _checkLoginStatus();
    }
  }

  Future<void> _checkLoginStatus() async {
    if (kAppModeShareOnly) return;
    final ok = await AppAuthService().isLoggedIn();
    if (!ok && mounted) {
      _showLoginExpiredDialog();
    }
  }

  void _showLoginExpiredDialog() {
    if (!mounted || _loginStatusDialogShowing) return;
    _loginStatusDialogShowing = true;
    final msg = stateGlobal.appLoginInvalidatedMessage.value.isNotEmpty
        ? stateGlobal.appLoginInvalidatedMessage.value
        : translate('account_kicked_message');
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(translate('account_abnormal_title')),
        content: Text(msg),
        actions: [
          dialogButton(
            translate('btn_exit_directly'),
            onPressed: () {
              close();
              _loginStatusDialogShowing = false;
              stateGlobal.appLoginInvalidated.value = false;
              stateGlobal.appLoginInvalidatedMessage.value = '';
              exit(0);
            },
          ),
          dialogButton(
            translate('btn_relogin'),
            onPressed: () {
              close();
              _loginStatusDialogShowing = false;
              stateGlobal.appLoginInvalidated.value = false;
              stateGlobal.appLoginInvalidatedMessage.value = '';
              Navigator.of(context).pushAndRemoveUntil(
                PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const LoginTabPage(
                        windowSize: kDesktopMainWindowSize,
                        child: desktop_login.AppLoginPage()),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero),
                (route) => false,
              );
            },
          ),
        ],
      );
    }, tag: 'login-expired');
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final pw = await bind.mainGetPermanentPassword();
  final p0 = TextEditingController(text: pw);
  final p1 = TextEditingController(text: pw);
  var errMsg0 = "";
  var errMsg1 = "";
  final RxString rxPass = pw.trim().obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();

  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      bind.mainSetPermanentPassword(password: pass);
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Text(translate("Set Password")),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              height: 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginSymmetric(vertical: 8),
            const SizedBox(
              height: 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            const SizedBox(
              height: 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: 8,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: [
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

/// 一台"我的设备"——由服务器 /api/user/devices 返回，对应当前登录账号下的设备。
class MyDevice {
  final String id;
  final String username;
  final String phone;
  final String ip;
  final String clientType; // 'full' | 'share_only' | 'desktop'
  final String appVersion;
  final String lastSeen; // ISO8601
  final String firstSeen; // ISO8601
  final bool banned;
  final bool online;

  MyDevice({
    required this.id,
    required this.username,
    required this.phone,
    required this.ip,
    required this.clientType,
    required this.appVersion,
    required this.lastSeen,
    required this.firstSeen,
    required this.banned,
    required this.online,
  });

  factory MyDevice.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v?.toString() ?? '';
    return MyDevice(
      id: s(j['id']),
      username: s(j['username']),
      phone: s(j['phone']),
      ip: s(j['ip']),
      clientType: s(j['clientType']),
      appVersion: s(j['appVersion']),
      lastSeen: s(j['lastSeen']),
      firstSeen: s(j['firstSeen']),
      banned: j['banned'] == true,
      online: j['online'] == true,
    );
  }

  DateTime? get lastSeenDate => DateTime.tryParse(lastSeen);
}

/// 一条"最近连接"会话记录——由服务器 /api/user/sessions 返回。
class MySession {
  final String sessionId;
  final String deviceId;
  final String peerId;
  final String remoteId; // 对端 ID（相对当前账号）
  final String direction; // 'incoming' | 'outgoing'
  final String remoteClientType; // 'full' | 'share_only' | 'desktop'
  final String username;
  final String startTime; // ISO8601
  final String endTime; // ISO8601
  final bool active; // 会话是否仍在进行
  final int durationSec;

  MySession({
    required this.sessionId,
    required this.deviceId,
    required this.peerId,
    required this.remoteId,
    required this.direction,
    required this.remoteClientType,
    required this.username,
    required this.startTime,
    required this.endTime,
    required this.active,
    required this.durationSec,
  });

  factory MySession.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v?.toString() ?? '';
    int i(dynamic v) =>
        v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
    return MySession(
      sessionId: s(j['sessionId']),
      deviceId: s(j['deviceId']),
      peerId: s(j['peerId']),
      remoteId: s(j['remoteId']),
      direction: s(j['direction']),
      remoteClientType: s(j['remoteClientType']),
      username: s(j['username']),
      startTime: s(j['startTime']),
      endTime: s(j['endTime']),
      active: j['active'] == true,
      durationSec: i(j['durationSec']),
    );
  }

  DateTime? get startDate => DateTime.tryParse(startTime);
}

/// 一条收藏记录——由服务器 /api/user/favorites 返回。
class MyFavorite {
  final String peerId;
  final String alias;
  final String createdAt; // ISO8601
  final String clientType; // 'full' | 'share_only' | 'desktop'
  final bool online;

  MyFavorite({
    required this.peerId,
    required this.alias,
    required this.createdAt,
    required this.clientType,
    required this.online,
  });

  factory MyFavorite.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v?.toString() ?? '';
    return MyFavorite(
      peerId: s(j['peerId']),
      alias: s(j['alias']),
      createdAt: s(j['createdAt']),
      clientType: s(j['clientType']),
      online: j['online'] == true,
    );
  }
}