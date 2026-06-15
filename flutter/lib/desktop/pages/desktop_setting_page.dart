import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/desktop/widgets/remote_toolbar.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/printer_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/manager.dart';
import 'package:flutter_hbb/plugin/widgets/desktop_settings.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common/widgets/dialog.dart';
import '../../common/widgets/login.dart';
import '../../common/app_auth_service.dart';
import 'desktop_login_page.dart' as desktop_login;
import 'privacy_policy.dart' as privacy_pages;
import 'terms_of_service.dart' as terms_pages;
import 'login_tab_page.dart';

const double _kTabWidth = 220;
const double _kEmbeddedTabWidth = 172;
const double _kTabHeight = 42;
const double _kCardFixedWidth = 540;
const double _kCardLeftMargin = 15;
const double _kContentHMargin = 15;
const double _kContentHSubMargin = _kContentHMargin + 33;
const double _kCheckBoxLeftMargin = 10;
const double _kRadioLeftMargin = 10;
const double _kListViewBottomMargin = 15;
const double _kTitleFontSize = 20;
const double _kContentFontSize = 15;
const Color _accentColor = MyTheme.accent;
const String _kSettingPageControllerTag = 'settingPageController';
const String _kSettingPageTabKeyTag = 'settingPageTabKey';

class _TabInfo {
  late final SettingsTabKey key;
  late final String label;
  late final IconData unselected;
  late final IconData selected;
  late final String category;
  _TabInfo(this.key, this.label, this.unselected, this.selected, {this.category = ''});
}

enum SettingsTabKey {
  general,
  safety,
  network,
  display,
  remoteControl,
  plugin,
  account,
  advanced,
  update,
  printer,
  about,
}

class DesktopSettingPage extends StatefulWidget {
  final SettingsTabKey initialTabkey;
  // When true, render without the Scaffold/logo header/home button so the page
  // can be embedded as a sub-page of the desktop home page (shared sidebar).
  final bool embedded;
  static final List<SettingsTabKey> tabKeys = [
    SettingsTabKey.general,
    if (!isWeb &&
        !bind.isOutgoingOnly() &&
        !bind.isDisableSettings() &&
        bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) != 'Y')
      SettingsTabKey.safety,
    if (!bind.isDisableSettings() &&
        !isDesktop &&
        bind.mainGetBuildinOption(key: kOptionHideNetworkSetting) != 'Y')
      SettingsTabKey.network,
    if (!bind.isIncomingOnly()) SettingsTabKey.display,
    if (!bind.isIncomingOnly()) SettingsTabKey.remoteControl,
    if (!isWeb && !bind.isIncomingOnly() && bind.pluginFeatureIsEnabled())
      SettingsTabKey.plugin,
    if (!bind.isDisableAccount()) SettingsTabKey.account,
    if (!isWeb) SettingsTabKey.advanced,
    SettingsTabKey.update,
    if (isWindows &&
        !isDesktop &&
        bind.mainGetBuildinOption(key: kOptionHideRemotePrinterSetting) != 'Y')
      SettingsTabKey.printer,
    SettingsTabKey.about,
  ];

  static SettingsTabKey? pendingTabKey;

  DesktopSettingPage(
      {Key? key, required this.initialTabkey, this.embedded = false})
      : super(key: key);

  @override
  State<DesktopSettingPage> createState() =>
      _DesktopSettingPageState(initialTabkey);

  static void switch2page(SettingsTabKey page) {
    try {
      int index = tabKeys.indexOf(page);
      if (index == -1) {
        return;
      }
      if (Get.isRegistered<PageController>(tag: _kSettingPageControllerTag)) {
        DesktopTabPage.onAddSetting(initialPage: page);
        PageController controller =
            Get.find<PageController>(tag: _kSettingPageControllerTag);
        Rx<SettingsTabKey> selected =
            Get.find<Rx<SettingsTabKey>>(tag: _kSettingPageTabKeyTag);
        selected.value = page;
        controller.jumpToPage(index);
      } else {
        pendingTabKey = page;
        DesktopTabPage.onAddSetting(initialPage: page);
      }
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopSettingPageState extends State<DesktopSettingPage>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver {
  late PageController controller;
  late Rx<SettingsTabKey> selectedTab;

  @override
  bool get wantKeepAlive => true;

  final RxBool _block = false.obs;
  final RxBool _canBeBlocked = false.obs;
  Timer? _videoConnTimer;

  _DesktopSettingPageState(SettingsTabKey initialTabkey) {
    if (DesktopSettingPage.pendingTabKey != null) {
      initialTabkey = DesktopSettingPage.pendingTabKey!;
      DesktopSettingPage.pendingTabKey = null;
    }
    var initialIndex = DesktopSettingPage.tabKeys.indexOf(initialTabkey);
    if (initialIndex == -1) {
      initialIndex = 0;
    }
    selectedTab = DesktopSettingPage.tabKeys[initialIndex].obs;
    Get.put<Rx<SettingsTabKey>>(selectedTab, tag: _kSettingPageTabKeyTag);
    controller = PageController(initialPage: initialIndex);
    Get.put<PageController>(controller, tag: _kSettingPageControllerTag);
    controller.addListener(() {
      if (controller.page != null) {
        int page = controller.page!.toInt();
        if (page < DesktopSettingPage.tabKeys.length) {
          selectedTab.value = DesktopSettingPage.tabKeys[page];
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _videoConnTimer =
        periodic_immediate(Duration(milliseconds: 1000), () async {
      if (!mounted) {
        return;
      }
      _canBeBlocked.value = await canBeBlocked();
    });
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<PageController>(tag: _kSettingPageControllerTag);
    Get.delete<RxInt>(tag: _kSettingPageTabKeyTag);
    WidgetsBinding.instance.removeObserver(this);
    _videoConnTimer?.cancel();
  }

  List<_TabInfo> _settingTabs() {
    final List<_TabInfo> settingTabs = <_TabInfo>[];
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          settingTabs.add(_TabInfo(
              tab, 'General', Icons.settings_outlined, Icons.settings,
              category: 'Common'));
          break;
        case SettingsTabKey.safety:
          settingTabs.add(_TabInfo(tab, 'Security',
              Icons.enhanced_encryption_outlined, Icons.enhanced_encryption,
              category: 'Common'));
          break;
        case SettingsTabKey.network:
          settingTabs
              .add(_TabInfo(tab, 'Network', Icons.link_outlined, Icons.link,
              category: 'Common'));
          break;
        case SettingsTabKey.display:
          settingTabs.add(_TabInfo(tab, 'Display',
              Icons.desktop_windows_outlined, Icons.desktop_windows,
              category: 'Common'));
          break;
        case SettingsTabKey.remoteControl:
          settingTabs.add(_TabInfo(tab, 'Remote control',
              Icons.cast_outlined, Icons.cast,
              category: 'Common'));
          break;
        case SettingsTabKey.plugin:
          settingTabs.add(_TabInfo(
              tab, 'Plugin', Icons.extension_outlined, Icons.extension,
              category: 'Common'));
          break;
        case SettingsTabKey.account:
          settingTabs.add(
              _TabInfo(tab, 'Account', Icons.person_outline, Icons.person,
              category: 'Common'));
          break;
        case SettingsTabKey.advanced:
          settingTabs.add(_TabInfo(tab, 'Advanced features',
              Icons.auto_awesome_outlined, Icons.auto_awesome,
              category: 'Common'));
          break;
        case SettingsTabKey.update:
          settingTabs.add(
              _TabInfo(tab, 'Update', Icons.system_update_outlined, Icons.system_update,
              category: 'Common'));
          break;
        case SettingsTabKey.printer:
          settingTabs
              .add(_TabInfo(tab, 'Printer', Icons.print_outlined, Icons.print,
              category: 'Common'));
          break;
        case SettingsTabKey.about:
          settingTabs
              .add(_TabInfo(tab, 'About', Icons.info_outline, Icons.info,
              category: 'More'));
          break;
      }
    }
    return settingTabs;
  }

  List<Widget> _children() {
    final children = List<Widget>.empty(growable: true);
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          children.add(const _General());
          break;
        case SettingsTabKey.safety:
          children.add(const _Safety());
          break;
        case SettingsTabKey.network:
          children.add(const _Network());
          break;
        case SettingsTabKey.display:
          children.add(const _Display());
          break;
        case SettingsTabKey.remoteControl:
          children.add(const _RemoteControl());
          break;
        case SettingsTabKey.plugin:
          children.add(const _Plugin());
          break;
        case SettingsTabKey.account:
          children.add(const _Account());
          break;
        case SettingsTabKey.advanced:
          children.add(const _Advanced());
          break;
        case SettingsTabKey.update:
          children.add(const _Update());
          break;
        case SettingsTabKey.printer:
          children.add(const _Printer());
          break;
        case SettingsTabKey.about:
          children.add(const _About());
          break;
      }
    }
    return children;
  }

  Widget _buildBlock({required List<Widget> children}) {
    // check both mouseMoveTime and videoConnCount
    return Obx(() {
      final videoConnBlock =
          _canBeBlocked.value && stateGlobal.videoConnCount > 0;
      return Stack(children: [
        buildRemoteBlock(
          block: _block,
          mask: false,
          use: canBeBlocked,
          child: preventMouseKeyBuilder(
            child: Row(children: children),
            block: videoConnBlock,
          ),
        ),
        if (videoConnBlock)
          Container(
            color: Colors.black.withOpacity(0.5),
          )
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final embedded = widget.embedded;
    final sidebar = Container(
      width: embedded ? _kEmbeddedTabWidth : _kTabWidth,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Color(0xFFEDEFF3), width: 1),
        ),
      ),
      child: embedded
          ? Column(
              children: [
                _embeddedHeader(context),
                Flexible(child: _listView(tabs: _settingTabs())),
                const SizedBox(height: 8),
              ],
            )
          : Stack(
              children: [
                Column(
                  children: [
                    _header(context),
                    Flexible(child: _listView(tabs: _settingTabs())),
                    // 为底部返回按钮留出空间
                    const SizedBox(height: 57),
                  ],
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildHomeButton(context),
                ),
              ],
            ),
    );
    final content = _buildBlock(
      children: <Widget>[
        sidebar,
        Expanded(
          child: Container(
            color: const Color(0xFFF3F5F8),
            child: PageView(
              controller: controller,
              physics: NeverScrollableScrollPhysics(),
              children: _children(),
            ),
          ),
        )
      ],
    );
    if (embedded) {
      return Container(
        color: const Color(0xFFF3F5F8),
        child: content,
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F8),
      body: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 600,
          minHeight: 480,
        ),
        child: content,
      ),
    );
  }

  Widget _embeddedHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 16, 14),
      child: Text(
        translate('Settings'),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildHomeButton(BuildContext context) {
    final RxBool hover = false.obs;
    return Obx(() => InkWell(
          onTap: () {
            try {
              DesktopTabController tabController =
                  Get.find<DesktopTabController>();
              tabController.jumpTo(0);
            } catch (e) {
              debugPrintStack(label: '$e');
            }
          },
          onHover: (v) => hover.value = v,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: hover.value ? const Color(0xFFEFF4FF) : Colors.white,
              border: const Border(
                top: BorderSide(color: Color(0xFFEDEFF3), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.home_outlined,
                  size: 20,
                  color:
                      hover.value ? MyTheme.accent : const Color(0xFF6B7280),
                ),
                const SizedBox(width: 8),
                Text(
                  translate('Home'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: hover.value
                        ? MyTheme.accent
                        : const Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
        ));
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 20, bottom: 16),
      child: Column(
        children: [
          if (isWeb)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: IconButton(
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  icon: Icon(Icons.arrow_back),
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/about_logo.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                bind.mainGetAppNameSync(),
                style: const TextStyle(
                  fontSize: _kTitleFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _categoryHeader(String category) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: 16, bottom: 6),
      child: Text(
        translate(category),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );
  }

  Widget _listView({required List<_TabInfo> tabs}) {
    final scrollController = ScrollController();
    final List<Widget> children = [];
    String? lastCategory;
    for (final tab in tabs) {
      if (tab.category.isNotEmpty && tab.category != lastCategory) {
        children.add(_categoryHeader(tab.category));
        lastCategory = tab.category;
      }
      children.add(_listItem(tab: tab));
    }
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 16),
      children: children,
    );
  }

  Widget _listItem({required _TabInfo tab}) {
    return Obx(() {
      bool selected = tab.key == selectedTab.value;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (selectedTab.value != tab.key) {
              int index = DesktopSettingPage.tabKeys.indexOf(tab.key);
              if (index == -1) {
                return;
              }
              controller.jumpToPage(index);
            }
            selectedTab.value = tab.key;
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFEFF4FF) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(
                selected ? tab.selected : tab.unselected,
                size: 19,
                color: selected ? MyTheme.accent : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 12),
              Text(
                translate(tab.label),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.black : const Color(0xFF1F2937),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

//#region pages

class _General extends StatefulWidget {
  const _General({Key? key}) : super(key: key);

  @override
  State<_General> createState() => _GeneralState();
}

class _GeneralState extends State<_General> {
  final RxBool serviceStop =
      isWeb ? RxBool(false) : Get.find<RxBool>(tag: 'stop-service');
  RxBool serviceBtnEnabled = true.obs;

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        if (!isWeb) service(),
        language(),
        if (!isWeb) record(context),
        if (!isWeb) audio(context),
        if (!isWeb) WaylandCard(),
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget theme() {
    final current = MyTheme.getThemeModePreference().toShortString();
    onChanged(String value) async {
      await MyTheme.changeDarkMode(MyTheme.themeModeFromString(value));
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    return _GCard(icon: Icons.palette_outlined, title: 'Theme', children: [
      _Radio<String>(context,
          value: 'light',
          groupValue: current,
          label: 'Light',
          onChanged: isOptFixed ? null : onChanged),
      _Radio<String>(context,
          value: 'dark',
          groupValue: current,
          label: 'Dark',
          onChanged: isOptFixed ? null : onChanged),
      _Radio<String>(context,
          value: 'system',
          groupValue: current,
          label: 'Follow System',
          onChanged: isOptFixed ? null : onChanged),
    ]);
  }

  Widget service() {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    return Obx(() {
      final stopped = serviceStop.value;
      return _GCard(
        icon: Icons.dns_outlined,
        iconColor: const Color(0xFF22C55E),
        title: 'Service',
        subtitle: stopped ? 'Service is not running' : 'Service is running',
        trailing: SizedBox(
          height: 40,
          child: ElevatedButton(
            onPressed: serviceBtnEnabled.value
                ? () async {
                    serviceBtnEnabled.value = false;
                    await start_service(serviceStop.value);
                    // enable the button after 1 second
                    Future.delayed(const Duration(seconds: 1), () {
                      serviceBtnEnabled.value = true;
                    });
                  }
                : null,
            style: _gCardButtonStyle,
            child: Text(
              translate(stopped ? 'Start service' : 'Stop service'),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    });
  }

  Widget audio(BuildContext context) {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    builder(devices, currentDevice, setDevice) {
      final child = SizedBox(
        width: 220,
        child: ComboBox(
          keys: devices,
          values: devices,
          initialKey: currentDevice,
          onChanged: (key) async {
            setDevice(key);
            setState(() {});
          },
        ),
      );
      return _GCard(
          icon: Icons.mic_none_outlined,
          iconColor: const Color(0xFF8B5CF6),
          title: 'Audio Input Device',
          trailing: child);
    }

    return AudioInput(builder: builder, isCm: false, isVoiceCall: false);
  }

  Widget record(BuildContext context) {
    final showRootDir = isWindows && bind.mainIsInstalled();
    return futureBuilder(future: () async {
      String user_dir = bind.mainVideoSaveDirectory(root: false);
      String root_dir =
          showRootDir ? bind.mainVideoSaveDirectory(root: true) : '';
      bool user_dir_exists = await Directory(user_dir).exists();
      bool root_dir_exists =
          showRootDir ? await Directory(root_dir).exists() : false;
      return {
        'user_dir': user_dir,
        'root_dir': root_dir,
        'user_dir_exists': user_dir_exists,
        'root_dir_exists': root_dir_exists,
      };
    }(), hasData: (data) {
      Map<String, dynamic> map = data as Map<String, dynamic>;
      String user_dir = map['user_dir']!;
      String root_dir = map['root_dir']!;
      bool root_dir_exists = map['root_dir_exists']!;
      bool user_dir_exists = map['user_dir_exists']!;

      // Unified directory row used inside the card body: a muted label, the
      // (clickable) path, and an optional trailing control, all sharing the
      // same left alignment as the checkboxes above.
      Widget dirRow(String label, String dir, bool exists, {Widget? trailing}) {
        return Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                  fontSize: _kContentFontSize, color: Color(0xFF6B7280)),
            ),
            Expanded(
              child: GestureDetector(
                onTap: exists ? () => launchUrl(Uri.file(dir)) : null,
                child: Text(
                  dir,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: _kContentFontSize,
                    decoration: exists ? TextDecoration.underline : null,
                  ),
                ),
              ).marginOnly(left: 8),
            ),
            if (trailing != null) trailing.marginOnly(left: 10),
          ],
        ).marginOnly(left: _kCheckBoxLeftMargin);
      }

      return _GCard(
          icon: Icons.videocam_outlined,
          iconColor: const Color(0xFFF59E0B),
          title: 'Recording',
          subtitle: 'recording_card_tip',
          children: [
        if (!bind.isOutgoingOnly())
          _OptionCheckBox(context, 'Automatically record incoming sessions',
              kOptionAllowAutoRecordIncoming),
        if (!bind.isIncomingOnly())
          _OptionCheckBox(context, 'Automatically record outgoing sessions',
              kOptionAllowAutoRecordOutgoing,
              isServer: false),
        if (showRootDir && !bind.isOutgoingOnly())
          dirRow(
              '${translate(bind.isIncomingOnly() ? "Directory" : "Incoming")}:',
              root_dir,
              root_dir_exists),
        if (!(showRootDir && bind.isIncomingOnly()))
          dirRow(
            '${translate((showRootDir && !bind.isOutgoingOnly()) ? "Outgoing" : "Directory")}:',
            user_dir,
            user_dir_exists,
            trailing: ElevatedButton(
              onPressed: isOptionFixed(kOptionVideoSaveDirectory)
                  ? null
                  : () async {
                      String? initialDirectory;
                      if (await Directory.fromUri(Uri.directory(user_dir))
                          .exists()) {
                        initialDirectory = user_dir;
                      }
                      String? selectedDirectory = await FilePicker.platform
                          .getDirectoryPath(initialDirectory: initialDirectory);
                      if (selectedDirectory != null) {
                        await bind.mainSetLocalOption(
                            key: kOptionVideoSaveDirectory,
                            value: selectedDirectory);
                        setState(() {});
                      }
                    },
              style: _gCardButtonStyle,
              child: Text(translate('Change'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
      ]);
    });
  }

  Widget language() {
    return futureBuilder(future: () async {
      String langs = await bind.mainGetLangs();
      return {'langs': langs};
    }(), hasData: (res) {
      Map<String, String> data = res as Map<String, String>;
      List<dynamic> langsList = jsonDecode(data['langs']!);
      Map<String, String> langsMap = {for (var v in langsList) v[0]: v[1]};
      List<String> keys = langsMap.keys.toList();
      List<String> values = langsMap.values.toList();
      keys.insert(0, defaultOptionLang);
      values.insert(0, translate('Default'));
      String currentKey = bind.mainGetLocalOption(key: kCommConfKeyLang);
      if (!keys.contains(currentKey)) {
        currentKey = defaultOptionLang;
      }
      final isOptFixed = isOptionFixed(kCommConfKeyLang);
      return _GCard(
        icon: Icons.language_outlined,
        title: 'Language and region',
        subtitle: 'language_region_tip',
        trailing: SizedBox(
          width: 180,
          child: ComboBox(
            keys: keys,
            values: values,
            initialKey: currentKey,
            onChanged: (key) async {
              await bind.mainSetLocalOption(key: kCommConfKeyLang, value: key);
              if (isWeb) reloadCurrentWindow();
              if (!isWeb) reloadAllWindows();
              if (!isWeb) bind.mainChangeLanguage(lang: key);
            },
            enabled: !isOptFixed,
          ),
        ),
      );
    });
  }

}

enum _AccessMode {
  custom,
  full,
  view,
}

class _Safety extends StatefulWidget {
  const _Safety({Key? key}) : super(key: key);

  @override
  State<_Safety> createState() => _SafetyState();
}

class _SafetyState extends State<_Safety> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool locked = bind.mainIsInstalled();
  // Whether the collapsible "Advanced Permissions" section of the access
  // permissions card is expanded (matches the "高级权限 / 展开" row in the mockup).
  bool _showAdvancedPermissions = false;
  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
        controller: scrollController,
        child: Column(
          children: [
            _securityBanner(),
            preventMouseKeyBuilder(
              block: locked,
              child: Column(children: [
                permissions(context),
                password(context),
                // 隐藏"更改 ID"入口
                // if (!isChangeIdDisabled())
                //   _Card(title: 'ID', children: [changeId()]),
                more(context),
              ]),
            ),
          ],
        )).marginOnly(bottom: _kListViewBottomMargin);
  }

  // Blue status banner shown at the top of the Security page (matching the
  // "8.2-设置-安全" mockup): a shield icon, a short tip and a status pill on
  // the right that doubles as the unlock action when settings are locked.
  Widget _securityBanner() {
    return Container(
      width: double.infinity,
      margin:
          const EdgeInsets.fromLTRB(_kCardLeftMargin, 15, _kContentHMargin, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD3E1FF)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.verified_user, color: _accentColor, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              translate('security_settings_banner_tip'),
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            // Acts as a two-way switch: tap to unlock when locked, tap again to
            // re-lock (re-protect) the security settings when unlocked.
            onTap: locked ? _unlock : () => setState(() => locked = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _accentColor.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(locked ? Icons.lock_outline : Icons.lock_open_outlined,
                      size: 15, color: _accentColor),
                  const SizedBox(width: 5),
                  Text(
                    translate(locked
                        ? 'Unlock Security Settings'
                        : 'Lock Security Settings'),
                    style: const TextStyle(
                        fontSize: 12,
                        color: _accentColor,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Unlock the security settings, sharing the same permission/PIN check as the
  // [_lock] card below the banner.
  Future<void> _unlock() async {
    final unlockPin = bind.mainGetUnlockPin();
    onUnlock() => setState(() => locked = false);
    if (unlockPin.isEmpty || isUnlockPinDisabled()) {
      final checked = await callMainCheckSuperUserPermission();
      if (checked) onUnlock();
    } else {
      checkUnlockPinDialog(unlockPin, onUnlock);
    }
  }

  Widget tfa() {
    return Offstage();
  }

  Widget changeId() {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: ((context, model, child) {
          return _Button('Change ID', changeIdDialog,
              enabled: !locked && model.connectStatus > 0);
        })));
  }

  Widget permissions(context) {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      String accessMode = bind.mainGetOptionSync(key: kOptionAccessMode);
      _AccessMode mode;
      if (accessMode == 'full') {
        mode = _AccessMode.full;
      } else if (accessMode == 'view') {
        mode = _AccessMode.view;
      } else {
        mode = _AccessMode.custom;
      }
      String initialKey;
      bool? fakeValue;
      switch (mode) {
        case _AccessMode.custom:
          initialKey = '';
          fakeValue = null;
          break;
        case _AccessMode.full:
          initialKey = 'full';
          fakeValue = true;
          break;
        case _AccessMode.view:
          initialKey = 'view';
          fakeValue = false;
          break;
      }

      // Primary permissions, laid out in two columns exactly as in the
      // "8.2-设置-安全" mockup:
      //   允许控制键盘/鼠标 | 允许传输音频
      //   允许同步剪贴板    | 允许查看摄像头
      //   允许传输文件      |
      final basicPermissions = <Widget>[
        _OptionCheckBox(context, 'Enable keyboard/mouse', kOptionEnableKeyboard,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(context, 'Enable audio', kOptionEnableAudio,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(context, 'Enable clipboard', kOptionEnableClipboard,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(context, 'Enable camera', kOptionEnableCamera,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(
            context, 'Enable file transfer', kOptionEnableFileTransfer,
            enabled: enabled, fakeValue: fakeValue),
      ];

      // The remaining permissions, hidden behind the "高级权限 / 展开" expander.
      final advancedPermissions = <Widget>[
        _OptionCheckBox(context, 'Enable TCP tunneling', kOptionEnableTunnel,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(
            context, 'Enable remote restart', kOptionEnableRemoteRestart,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(
            context, 'Enable recording session', kOptionEnableRecordSession,
            enabled: enabled, fakeValue: fakeValue),
        if (isWindows)
          _OptionCheckBox(
              context, 'Enable blocking user input', kOptionEnableBlockInput,
              enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(context, 'Enable remote configuration modification',
            kOptionAllowRemoteConfigModification,
            enabled: enabled, fakeValue: fakeValue),
      ];

      // "权限方案" label sitting above the access-mode dropdown.
      final accessModeField = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate('Permission scheme'),
            style: const TextStyle(
                fontSize: _kContentFontSize, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 6),
          ComboBox(
              keys: [
                defaultOptionAccessMode,
                'full',
                'view',
              ],
              values: [
                translate('Custom'),
                translate('Full Access'),
                translate('Screen Share'),
              ],
              enabled: enabled && !isOptionFixed(kOptionAccessMode),
              initialKey: initialKey,
              onChanged: (mode) async {
                await bind.mainSetOption(key: kOptionAccessMode, value: mode);
                setState(() {});
              }),
        ],
      ).marginOnly(left: _kCheckBoxLeftMargin);

      // "高级权限" row with a trailing expand/collapse affordance.
      final advancedHeader = InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(
            () => _showAdvancedPermissions = !_showAdvancedPermissions),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Text(
                translate('Advanced Permissions'),
                style: const TextStyle(
                    fontSize: _kContentFontSize, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                translate(_showAdvancedPermissions ? 'Collapse' : 'Expand'),
                style: const TextStyle(fontSize: 13, color: _accentColor),
              ),
              Icon(
                _showAdvancedPermissions
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 18,
                color: _accentColor,
              ),
            ],
          ),
        ),
      ).marginOnly(left: _kCheckBoxLeftMargin);

      return _GCard(
          icon: Icons.verified_user_outlined,
          iconColor: const Color(0xFF22C55E),
          title: 'Access Permissions',
          subtitle: 'access_permissions_tip',
          children: [
        accessModeField,
        _twoColumnGrid(basicPermissions),
        advancedHeader,
        if (_showAdvancedPermissions) _twoColumnGrid(advancedPermissions),
      ]);
    }

    return tmpWrapper();
  }

  Widget password(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: ((context, model, child) {
          final method = model.verificationMethod;
          final oneTimeOn = method != kUsePermanentPassword; // temporary or both
          final permanentOn =
              method != kUseTemporaryPassword; // permanent or both
          final bothOn = method == kUseBothPasswords;
          final tmpEnabled = oneTimeOn;
          final permEnabled = permanentOn;

          setMethod(String m) async {
            await model.setVerificationMethod(m);
            await model.updatePasswordModel();
          }

          // Apply a verification method, prompting to create a permanent
          // password first when one is required but not yet set.
          applyMethod(String m) async {
            final needsPermanent =
                m == kUsePermanentPassword || m == kUseBothPasswords;
            if (needsPermanent &&
                (await bind.mainGetPermanentPassword()).isEmpty &&
                !isChangePermanentPasswordDisabled()) {
              setPasswordDialog(notEmptyCallback: () => setMethod(m));
            } else {
              await setMethod(m);
            }
          }

          // The three verification methods are mutually exclusive, but the
          // mockup renders them as independent enable switches; keep the
          // underlying single-choice model consistent here.
          onOneTime(bool v) => v
              ? applyMethod(
                  permanentOn ? kUseBothPasswords : kUseTemporaryPassword)
              : applyMethod(kUsePermanentPassword);
          onPermanent(bool v) => v
              ? applyMethod(
                  oneTimeOn ? kUseBothPasswords : kUsePermanentPassword)
              : applyMethod(kUseTemporaryPassword);
          onBoth(bool v) => v
              ? applyMethod(kUseBothPasswords)
              : applyMethod(kUseTemporaryPassword);

          var onLenChanged = tmpEnabled && !locked
              ? (value) {
                  if (value != null) {
                    () async {
                      await model.setTemporaryPasswordLength(value.toString());
                      await model.updatePasswordModel();
                    }();
                  }
                }
              : null;
          List<Widget> lengthRadios = ['6', '8', '10']
              .map((value) => GestureDetector(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Radio(
                            value: value,
                            groupValue: model.temporaryPasswordLength,
                            onChanged: onLenChanged),
                        Text(
                          value,
                          style: TextStyle(
                              color: disabledTextColor(
                                  context, onLenChanged != null)),
                        ),
                      ],
                    ).paddingOnly(right: 10),
                    onTap: () => onLenChanged?.call(value),
                  ))
              .toList();

          final isOptFixedNumOTP =
              isOptionFixed(kOptionAllowNumericOneTimePassword);
          final isNumOPTChangable = !isOptFixedNumOTP && tmpEnabled && !locked;
          final numericOneTimePassword = GestureDetector(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                        value: model.allowNumericOneTimePassword,
                        onChanged: isNumOPTChangable
                            ? (bool? v) =>
                                model.switchAllowNumericOneTimePassword()
                            : null)
                    .marginOnly(right: 5),
                Text(
                  translate('Use numeric'),
                  style: TextStyle(
                      color: disabledTextColor(context, isNumOPTChangable)),
                ),
              ],
            ),
            onTap: isNumOPTChangable
                ? () => model.switchAllowNumericOneTimePassword()
                : null,
          );

          final modeKeys = <String>[
            'password',
            'click',
            defaultOptionApproveMode
          ];
          final modeValues = [
            translate('Accept sessions via password'),
            translate('Accept sessions via click'),
            translate('Accept sessions via both'),
          ];
          var modeInitialKey = model.approveMode;
          if (!modeKeys.contains(modeInitialKey)) {
            modeInitialKey = defaultOptionApproveMode;
          }
          final usePassword = model.approveMode != 'click';
          final isApproveModeFixed = isOptionFixed(kOptionApproveMode);

          // A left-column label with its control on the right, mirroring the
          // "8.2-设置-安全" mockup's access-password form.
          Widget formRow(String label, Widget control,
              {CrossAxisAlignment align = CrossAxisAlignment.center}) {
            return Row(
              crossAxisAlignment: align,
              children: [
                SizedBox(
                  width: 104,
                  child: Text(
                    translate(label),
                    style: const TextStyle(
                        fontSize: _kContentFontSize, color: Color(0xFF6B7280)),
                  ),
                ),
                Expanded(child: control),
              ],
            ).marginOnly(left: _kCheckBoxLeftMargin);
          }

          // A "启用xxx" text with a trailing switch, used inside the right column.
          Widget enableSwitch(
              String label, bool value, Function(bool)? onChanged) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  translate(label),
                  style: TextStyle(
                      fontSize: _kContentFontSize,
                      color: disabledTextColor(context, onChanged != null)),
                ),
                const SizedBox(width: 10),
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: value,
                    activeColor: _accentColor,
                    onChanged: onChanged,
                  ),
                ),
              ],
            );
          }

          final oneTimeControl = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              enableSwitch('Enable one-time password', oneTimeOn,
                  locked ? null : onOneTime),
              if (tmpEnabled) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        translate('Password length'),
                        style: TextStyle(
                            fontSize: _kContentFontSize,
                            color: disabledTextColor(
                                context, tmpEnabled && !locked)),
                      ),
                    ),
                    ...lengthRadios,
                  ],
                ),
                const SizedBox(height: 4),
                numericOneTimePassword,
              ],
            ],
          );

          final permanentControl = Row(
            children: [
              enableSwitch('Enable permanent password', permanentOn,
                  locked ? null : onPermanent),
              const Spacer(),
              if (!isChangePermanentPasswordDisabled())
                ElevatedButton(
                  onPressed: permEnabled && !locked ? setPasswordDialog : null,
                  style: _gCardButtonStyle,
                  child: Text(
                    translate('Set permanent password'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          );

          return _GCard(
              icon: Icons.vpn_key_outlined,
              iconColor: const Color(0xFF8B5CF6),
              title: 'Access Password',
              subtitle: 'access_password_tip',
              children: [
            formRow(
              'Access mode',
              ComboBox(
                enabled: !locked && !isApproveModeFixed,
                keys: modeKeys,
                values: modeValues,
                initialKey: modeInitialKey,
                onChanged: (key) => model.setApproveMode(key),
              ),
            ),
            if (usePassword)
              formRow('One-time password', oneTimeControl,
                  align: CrossAxisAlignment.start),
            if (usePassword) formRow('Permanent password', permanentControl),
            if (usePassword)
              formRow(
                'Use both passwords',
                Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: bothOn,
                      activeColor: _accentColor,
                      onChanged: locked ? null : onBoth,
                    ),
                  ),
                ),
              ),
          ]);
        })));
  }

  Widget more(BuildContext context) {
    bool enabled = !locked;
    return _GCard(
        icon: Icons.shield_outlined,
        iconColor: _accentColor,
        title: 'Connection Protection',
        subtitle: 'connection_protection_tip',
        children: [
      if (isWindows && bind.mainIsInstalled()) shareRdp(context, enabled),
      _OptionSwitch(context, 'Deny LAN discovery', 'enable-lan-discovery',
          reverse: true, enabled: enabled),
      whitelist(),
      ...autoDisconnect(context),
      if (bind.mainIsInstalled())
        _OptionSwitch(context, 'allow-only-conn-window-open-tip',
            'allow-only-conn-window-open',
            reverse: false, enabled: enabled),
      if (bind.mainIsInstalled() && !isUnlockPinDisabled()) unlockPin()
    ]);
  }

  shareRdp(BuildContext context, bool enabled) {
    onChanged(bool b) async {
      await bind.mainSetShareRdp(enable: b);
      setState(() {});
    }

    bool value = bind.mainIsShareRdp();
    return Offstage(
      offstage: !(isWindows && bind.mainIsInstalled()),
      child: _switchRow(context, 'Enable RDP session sharing', value,
          enabled ? (v) => onChanged(v) : null),
    );
  }

  List<Widget> directIp(BuildContext context) {
    return [];
  }

  Widget whitelist() {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      RxBool hasWhitelist = whitelistNotEmpty().obs;
      update() async {
        hasWhitelist.value = whitelistNotEmpty();
      }

      onChanged(bool? checked) async {
        changeWhiteList(callback: update);
      }

      final isOptFixed = isOptionFixed(kOptionWhitelist);
      return Tooltip(
        message: translate('whitelist_tip'),
        child: Obx(() => _switchRow(
              context,
              'Use IP Whitelisting',
              hasWhitelist.value,
              enabled && !isOptFixed ? (v) => onChanged(v) : null,
              leading: hasWhitelist.value
                  ? const Icon(Icons.warning_amber_rounded,
                          color: Color.fromARGB(255, 255, 204, 0), size: 18)
                      .marginOnly(right: 8)
                  : null,
            )),
      );
    }

    return tmpWrapper();
  }

  Widget hide_cm(bool enabled) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: (context, model, child) {
          final enableHideCm = model.approveMode == 'password' &&
              model.verificationMethod == kUsePermanentPassword;
          onHideCmChanged(bool? b) {
            if (b != null) {
              bind.mainSetOption(
                  key: 'allow-hide-cm', value: bool2option('allow-hide-cm', b));
            }
          }

          return Tooltip(
              message: enableHideCm ? "" : translate('hide_cm_tip'),
              child: GestureDetector(
                onTap:
                    enableHideCm ? () => onHideCmChanged(!model.hideCm) : null,
                child: Row(
                  children: [
                    Checkbox(
                            value: model.hideCm,
                            onChanged: enabled && enableHideCm
                                ? onHideCmChanged
                                : null)
                        .marginOnly(right: 5),
                    Expanded(
                      child: Text(
                        translate('Hide connection management window'),
                        style: TextStyle(
                            color: disabledTextColor(
                                context, enabled && enableHideCm)),
                      ),
                    ),
                  ],
                ),
              ));
        }));
  }

  List<Widget> autoDisconnect(BuildContext context) {
    TextEditingController controller = TextEditingController();
    update(bool v) => setState(() {});
    RxBool applyEnabled = false.obs;
    return [
      _OptionSwitch(
          context, 'auto_disconnect_option_tip', kOptionAllowAutoDisconnect,
          update: update, enabled: !locked),
      () {
        bool enabled = option2bool(kOptionAllowAutoDisconnect,
            bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect));
        if (!enabled) applyEnabled.value = false;
        controller.text =
            bind.mainGetOptionSync(key: kOptionAutoDisconnectTimeout);
        final isOptFixed = isOptionFixed(kOptionAutoDisconnectTimeout);
        return Offstage(
          offstage: !enabled,
          child: _SubLabeledWidget(
            context,
            'Timeout in minutes',
            Row(children: [
              SizedBox(
                width: 95,
                child: TextField(
                  controller: controller,
                  enabled: enabled && !locked && !isOptFixed,
                  onChanged: (_) => applyEnabled.value = true,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(
                        r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$')),
                  ],
                  decoration: const InputDecoration(
                    hintText: '10',
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ).workaroundFreezeLinuxMint().marginOnly(right: 15),
              ),
              Obx(() => ElevatedButton(
                    onPressed:
                        applyEnabled.value && enabled && !locked && !isOptFixed
                            ? () async {
                                applyEnabled.value = false;
                                await bind.mainSetOption(
                                    key: kOptionAutoDisconnectTimeout,
                                    value: controller.text);
                              }
                            : null,
                    child: Text(
                      translate('Apply'),
                    ),
                  ))
            ]),
            enabled: enabled && !locked && !isOptFixed,
          ),
        );
      }(),
    ];
  }

  Widget unlockPin() {
    bool enabled = !locked;
    RxString unlockPin = bind.mainGetUnlockPin().obs;
    update() async {
      unlockPin.value = bind.mainGetUnlockPin();
    }

    onChanged(bool? checked) async {
      changeUnlockPinDialog(unlockPin.value, update);
    }

    final isOptFixed = isOptionFixed(kOptionWhitelist);
    return Obx(() => _switchRow(
          context,
          'Unlock with PIN',
          unlockPin.isNotEmpty,
          enabled && !isOptFixed ? (v) => onChanged(v) : null,
        ));
  }
}

class _Network extends StatefulWidget {
  const _Network({Key? key}) : super(key: key);

  @override
  State<_Network> createState() => _NetworkState();
}

class _NetworkState extends State<_Network> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool locked = !isWeb && bind.mainIsInstalled();

  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(controller: scrollController, children: [
      _lock(locked, 'Unlock Network Settings', () {
        locked = false;
        setState(() => {});
      }),
      preventMouseKeyBuilder(
        block: locked,
        child: Column(children: [
          network(context),
        ]),
      ),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget network(BuildContext context) {
    final hideServer =
        bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
    final hideProxy =
        isWeb || bind.mainGetBuildinOption(key: kOptionHideProxySetting) == 'Y';
    final hideWebSocket = isWeb ||
        bind.mainGetBuildinOption(key: kOptionHideWebSocketSetting) == 'Y';

    if (hideServer && hideProxy && hideWebSocket) {
      return Offstage();
    }

    // Helper function to create network setting ListTiles
    Widget listTile({
      required IconData icon,
      required String title,
      VoidCallback? onTap,
      Widget? trailing,
      bool showTooltip = false,
      String tooltipMessage = '',
    }) {
      final titleWidget = showTooltip
          ? Row(
              children: [
                Tooltip(
                  waitDuration: Duration(milliseconds: 1000),
                  message: translate(tooltipMessage),
                  child: Row(
                    children: [
                      Text(
                        translate(title),
                        style: TextStyle(fontSize: _kContentFontSize),
                      ),
                      SizedBox(width: 5),
                      Icon(
                        Icons.help_outline,
                        size: 14,
                        color: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Text(
              translate(title),
              style: TextStyle(fontSize: _kContentFontSize),
            );

      return ListTile(
        leading: Icon(icon, color: _accentColor),
        title: titleWidget,
        enabled: !locked,
        onTap: onTap,
        trailing: trailing,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        minLeadingWidth: 0,
        horizontalTitleGap: 10,
      );
    }

    Widget switchWidget(IconData icon, String title, String tooltipMessage,
            String optionKey) =>
        listTile(
          icon: icon,
          title: title,
          showTooltip: true,
          tooltipMessage: tooltipMessage,
          trailing: Switch(
            value: mainGetBoolOptionSync(optionKey),
            onChanged: locked || isOptionFixed(optionKey)
                ? null
                : (value) {
                    mainSetBoolOption(optionKey, value);
                    setState(() {});
                  },
          ),
        );

    final outgoingOnly = bind.isOutgoingOnly();

    final divider = const Divider(height: 1, indent: 16, endIndent: 16);
    return _Card(
      title: 'Network',
      children: [
        Container(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hideServer)
                listTile(
                  icon: Icons.dns_outlined,
                  title: 'ID/Relay Server',
                  onTap: () => showServerSettings(gFFI.dialogManager, setState),
                ),
              if (!hideProxy && !hideServer) divider,
              if (!hideProxy)
                listTile(
                  icon: Icons.network_ping_outlined,
                  title: 'Socks5/Http(s) Proxy',
                  onTap: changeSocks5Proxy,
                ),
              if (!hideWebSocket && (!hideServer || !hideProxy)) divider,
              if (!hideWebSocket)
                switchWidget(
                    Icons.web_asset_outlined,
                    'Use WebSocket',
                    '${translate('websocket_tip')}\n\n${translate('server-oss-not-support-tip')}',
                    kOptionAllowWebSocket),
              if (!isWeb)
                futureBuilder(
                  future: bind.mainIsUsingPublicServer(),
                  hasData: (isUsingPublicServer) {
                    if (isUsingPublicServer) {
                      return Offstage();
                    } else {
                      return Column(
                        children: [
                          if (!hideServer || !hideProxy || !hideWebSocket)
                            divider,
                          switchWidget(
                              Icons.no_encryption_outlined,
                              'Allow insecure TLS fallback',
                              'allow-insecure-tls-fallback-tip',
                              kOptionAllowInsecureTLSFallback),
                          if (!outgoingOnly) divider,
                          if (!outgoingOnly)
                            listTile(
                              icon: Icons.lan_outlined,
                              title: 'Disable UDP',
                              showTooltip: true,
                              tooltipMessage:
                                  '${translate('disable-udp-tip')}\n\n${translate('server-oss-not-support-tip')}',
                              trailing: Switch(
                                value: bind.mainGetOptionSync(
                                        key: kOptionDisableUdp) ==
                                    'Y',
                                onChanged:
                                    locked || isOptionFixed(kOptionDisableUdp)
                                        ? null
                                        : (value) async {
                                            await bind.mainSetOption(
                                                key: kOptionDisableUdp,
                                                value: value ? 'Y' : 'N');
                                            setState(() {});
                                          },
                              ),
                            ),
                        ],
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Display extends StatefulWidget {
  const _Display({Key? key}) : super(key: key);

  @override
  State<_Display> createState() => _DisplayState();
}

class _DisplayState extends State<_Display> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(controller: scrollController, children: [
      _settingsPageHeader('Display', 'display_settings_tip'),
      theme(context),
      viewStyle(context),
      scrollStyle(context),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget theme(BuildContext context) {
    final current = MyTheme.getThemeModePreference().toShortString();
    onChanged(String value) async {
      await MyTheme.changeDarkMode(MyTheme.themeModeFromString(value));
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    return _GCard(
        icon: Icons.brightness_6_outlined,
        iconColor: const Color(0xFF8B5CF6),
        title: 'Theme',
        children: [
      _Radio<String>(context,
          value: 'light',
          groupValue: current,
          label: 'Light',
          onChanged: isOptFixed ? null : onChanged),
      _Radio<String>(context,
          value: 'dark',
          groupValue: current,
          label: 'Dark',
          onChanged: isOptFixed ? null : onChanged),
      _Radio<String>(context,
          value: 'system',
          groupValue: current,
          label: 'Follow System',
          onChanged: isOptFixed ? null : onChanged),
    ]);
  }

  Widget viewStyle(BuildContext context) {
    final isOptFixed = isOptionFixed(kOptionViewStyle);
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(key: kOptionViewStyle, value: value);
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(key: kOptionViewStyle);
    return _GCard(
        icon: Icons.aspect_ratio_outlined,
        iconColor: const Color(0xFF3B82F6),
        title: 'Default View Style',
        children: [
      _Radio(context,
          value: kRemoteViewStyleOriginal,
          groupValue: groupValue,
          label: 'Scale original',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteViewStyleAdaptive,
          groupValue: groupValue,
          label: 'Scale adaptive',
          onChanged: isOptFixed ? null : onChanged),
    ]);
  }

  Widget scrollStyle(BuildContext context) {
    final isOptFixed = isOptionFixed(kOptionScrollStyle);
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionScrollStyle, value: value);
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(key: kOptionScrollStyle);

    onEdgeScrollEdgeThicknessChanged(double value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionEdgeScrollEdgeThickness, value: value.round().toString());
      setState(() {});
    }

    return _GCard(
        icon: Icons.swap_vert_outlined,
        iconColor: const Color(0xFF22C55E),
        title: 'Default Scroll Style',
        children: [
      _Radio(context,
          value: kRemoteScrollStyleAuto,
          groupValue: groupValue,
          label: 'ScrollAuto',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteScrollStyleBar,
          groupValue: groupValue,
          label: 'Scrollbar',
          onChanged: isOptFixed ? null : onChanged),
      if (!isWeb) ...[
        _Radio(context,
            value: kRemoteScrollStyleEdge,
            groupValue: groupValue,
            label: 'ScrollEdge',
            onChanged: isOptFixed ? null : onChanged),
        Offstage(
            offstage: groupValue != kRemoteScrollStyleEdge,
            child: EdgeThicknessControl(
              value: double.tryParse(bind.mainGetUserDefaultOption(
                      key: kOptionEdgeScrollEdgeThickness)) ??
                  100.0,
              onChanged: isOptionFixed(kOptionEdgeScrollEdgeThickness)
                  ? null
                  : onEdgeScrollEdgeThicknessChanged,
            )),
      ],
    ]);
  }

}

class _RemoteControl extends StatefulWidget {
  const _RemoteControl({Key? key}) : super(key: key);

  @override
  State<_RemoteControl> createState() => _RemoteControlState();
}

class _RemoteControlState extends State<_RemoteControl> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(controller: scrollController, children: [
      imageQuality(context),
      codec(context),
      operationsAndInput(context),
      clipboardAndFileTransfer(context),
      if (isDesktop) multipleMonitors(context),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  // A single toggle row used inside the cards below: colored icon + title +
  // optional description + switch.
  Widget _toggleRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate(title),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(translate(subtitle),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF))),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          activeColor: MyTheme.accent,
          onChanged: onChanged,
        ),
      ],
    );
  }

  // A toggle row bound to a per-session "user default" option.
  Widget _defaultOptionToggle({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required String key,
  }) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    final isOptFixed = isOptionFixed(key);
    return _toggleRow(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: isOptFixed
          ? null
          : (b) async {
              await bind.mainSetUserDefaultOption(
                key: key,
                value: b
                    ? 'Y'
                    : (key == kOptionEnableFileCopyPaste
                        ? 'N'
                        : defaultOptionNo),
              );
              setState(() {});
            },
    );
  }

  // 操作与输入
  Widget operationsAndInput(BuildContext context) {
    return _GCard(
        icon: Icons.touch_app_outlined,
        title: 'Operations and input',
        children: [
          if (isDesktop) _trackpadSpeedRow(context),
          _defaultOptionToggle(
            icon: Icons.mouse_outlined,
            iconColor: Colors.orange,
            title: 'Show remote cursor',
            subtitle: 'adv_show_cursor_sub',
            key: kOptionShowRemoteCursor,
          ),
        ]);
  }

  // 剪贴板与文件传输
  Widget clipboardAndFileTransfer(BuildContext context) {
    return _GCard(
        icon: Icons.content_paste_outlined,
        title: 'Clipboard and file transfer',
        children: [
          _defaultOptionToggle(
            icon: Icons.content_paste_off_outlined,
            iconColor: Colors.orange,
            title: 'Disable clipboard',
            subtitle: 'adv_disable_clipboard_sub',
            key: kOptionDisableClipboard,
          ),
          if (isDesktop)
            _defaultOptionToggle(
              icon: Icons.file_copy_outlined,
              iconColor: Colors.orange,
              title: 'Enable file copy and paste',
              subtitle: 'adv_file_copy_sub',
              key: kOptionEnableFileCopyPaste,
            ),
        ]);
  }

  // 多显示器
  Widget multipleMonitors(BuildContext context) {
    return _GCard(
        icon: Icons.desktop_windows_outlined,
        title: 'Multiple monitors',
        children: [
          _defaultOptionToggle(
            icon: Icons.web_asset_outlined,
            iconColor: Colors.orange,
            title: 'Show displays as individual windows',
            subtitle: 'adv_individual_windows_sub',
            key: kKeyShowDisplaysAsIndividualWindows,
          ),
          _defaultOptionToggle(
            icon: Icons.desktop_windows_outlined,
            iconColor: Colors.orange,
            title: 'Use all my displays for the remote session',
            subtitle: 'adv_all_displays_sub',
            key: kKeyUseAllMyDisplaysForTheRemoteSession,
          ),
          _defaultOptionToggle(
            icon: Icons.monitor_outlined,
            iconColor: Colors.blue,
            title: 'Show monitors in toolbar',
            subtitle: 'adv_show_monitors_sub',
            key: kKeyShowMonitorsToolbar,
          ),
        ]);
  }

  Widget imageQuality(BuildContext context) {
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionImageQuality, value: value);
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kOptionImageQuality);
    final groupValue = bind.mainGetUserDefaultOption(key: kOptionImageQuality);
    final tiles = <Widget>[
      _qualityTile(
        icon: Icons.image_outlined,
        title: 'Clarity priority',
        subtitle: 'img_quality_best_sub',
        value: kRemoteImageQualityBest,
        groupValue: groupValue,
        onChanged: isOptFixed ? null : onChanged,
      ),
      _qualityTile(
        icon: Icons.balance_outlined,
        title: 'Balanced',
        subtitle: 'img_quality_balanced_sub',
        value: kRemoteImageQualityBalanced,
        groupValue: groupValue,
        onChanged: isOptFixed ? null : onChanged,
      ),
      _qualityTile(
        icon: Icons.bolt_outlined,
        title: 'Smoothness priority',
        subtitle: 'img_quality_low_sub',
        value: kRemoteImageQualityLow,
        groupValue: groupValue,
        onChanged: isOptFixed ? null : onChanged,
      ),
      _qualityTile(
        icon: Icons.tune_outlined,
        title: 'Custom',
        subtitle: 'img_quality_custom_sub',
        value: kRemoteImageQualityCustom,
        groupValue: groupValue,
        onChanged: isOptFixed ? null : onChanged,
      ),
    ];
    return _GCard(
        icon: Icons.high_quality_outlined,
        title: 'Default Image Quality',
        children: [
          Row(
            children: [
              for (int i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
          Offstage(
            offstage: groupValue != kRemoteImageQualityCustom,
            child: customImageQualitySetting(),
          ),
        ]);
  }

  // A single selectable image-quality tile: radio indicator (top-left),
  // centered icon, title and subtitle. Highlighted when selected.
  Widget _qualityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required ValueChanged<String>? onChanged,
  }) {
    final selected = value == groupValue;
    final accent = MyTheme.accent;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onChanged == null ? null : () => onChanged(value),
      child: Container(
        height: 118,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: selected ? accent : const Color(0xFFC2C7D0),
              ),
            ),
            const SizedBox(height: 2),
            Icon(icon,
                size: 24,
                color: selected ? accent : const Color(0xFF6B7280)),
            const SizedBox(height: 6),
            Text(
              translate(title),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? accent : const Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                translate(subtitle),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: selected
                      ? accent.withOpacity(0.8)
                      : const Color(0xFF9CA3AF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackpadSpeedRow(BuildContext context) {
    final initSpeed =
        (int.tryParse(bind.mainGetUserDefaultOption(key: kKeyTrackpadSpeed)) ??
            kDefaultTrackpadSpeed);
    final curSpeed = SimpleWrapper(initSpeed);
    void onDebouncer(int v) {
      bind.mainSetUserDefaultOption(
          key: kKeyTrackpadSpeed, value: v.toString());
      // It's better to notify all sessions that the default speed is changed.
      // But it may also be ok to take effect in the next connection.
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.mouse_outlined,
                  size: 20, color: Colors.teal),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translate('Default trackpad speed'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(translate('rc_trackpad_speed_sub'),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
          ],
        ),
        TrackpadSpeedWidget(
          value: curSpeed,
          onDebouncer: onDebouncer,
        ),
      ],
    );
  }

  Widget codec(BuildContext context) {
    onChanged(String? value) async {
      if (value == null) return;
      await bind.mainSetUserDefaultOption(
          key: kOptionCodecPreference, value: value);
      setState(() {});
    }

    var groupValue =
        bind.mainGetUserDefaultOption(key: kOptionCodecPreference);
    final isOptFixed = isOptionFixed(kOptionCodecPreference);
    // value -> display label
    final items = <MapEntry<String, String>>[
      const MapEntry('auto', 'Auto (recommended)'),
      const MapEntry('vp8', 'VP8'),
      const MapEntry('vp9', 'VP9'),
      const MapEntry('av1', 'AV1'),
    ];
    try {
      final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
      if (codecsJson['h264'] ?? false) {
        items.add(const MapEntry('h264', 'H264'));
      }
      if (codecsJson['h265'] ?? false) {
        items.add(const MapEntry('h265', 'H265'));
      }
    } catch (e) {
      debugPrint("failed to parse supported hwdecodings, err=$e");
    }
    if (!items.any((e) => e.key == groupValue)) {
      groupValue = 'auto';
    }
    return _GCard(
        icon: Icons.video_settings_outlined,
        title: 'Default Codec',
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: groupValue,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF9CA3AF)),
                borderRadius: BorderRadius.circular(8),
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151)),
                onChanged: isOptFixed ? null : onChanged,
                items: items
                    .map((e) => DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(translate(e.value)),
                        ))
                    .toList(),
              ),
            ),
          ),
        ]);
  }

}

class _Account extends StatefulWidget {
  const _Account({Key? key}) : super(key: key);

  @override
  State<_Account> createState() => _AccountState();
}

class _AccountState extends State<_Account> {
  Map<String, dynamic>? _userInfo;
  bool _loadingUserInfo = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final info = await AppAuthService().getUserInfo();
    if (mounted) {
      setState(() {
        _userInfo = info;
        _loadingUserInfo = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: _kCardLeftMargin + _kContentHMargin,
              top: 20,
              bottom: 8),
          child: Text(
            translate('Account'),
            style: const TextStyle(
              fontSize: _kTitleFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (!kAppModeShareOnly) ...[
          _userInfoCard(context),
          _accountSecurityCard(context),
          _accountActionsCard(context),
        ],
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  /// 用户信息卡片（仅显示用户名与手机号）
  Widget _userInfoCard(BuildContext context) {
    if (_loadingUserInfo) {
      return _GCard(
        icon: Icons.account_circle_outlined,
        title: 'Account Info',
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      );
    }

    final username = _userInfo?['username']?.toString() ?? '';
    final phone = _userInfo?['phone']?.toString() ?? '';
    // 手机号脱敏: 138****1234
    final maskedPhone = phone.length >= 7
        ? '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}'
        : phone;

    return _GCard(
      icon: Icons.account_circle_outlined,
      title: 'Account Info',
      trailing: OutlinedButton.icon(
        onPressed: () => _doEditProfile(),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: Text(translate('Edit profile')),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accentColor,
          side: BorderSide(color: _accentColor.withOpacity(0.5)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              // 头像圆圈
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      _accentColor,
                      _accentColor.withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 用户名 + 手机号
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoLine(
                        'Username',
                        username.isNotEmpty
                            ? username
                            : translate('No user info')),
                    const SizedBox(height: 10),
                    _infoLine(
                        'Phone Number', maskedPhone.isNotEmpty ? maskedPhone : '-'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  /// 账户信息中的「标签: 值」一行
  Widget _infoLine(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, height: 1.2),
        children: [
          TextSpan(
              text: translate(label) + ': ',
              style: const TextStyle(color: Color(0xFF9CA3AF))),
          TextSpan(
              text: value,
              style: const TextStyle(
                  color: Color(0xFF374151), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// 账户安全中的可点击行：标题 + 副标题 + 右侧箭头（无前置图标）
  Widget _accountLinkRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(translate(title),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(translate(subtitle),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFFC2C7D0)),
            ],
          ),
        ),
      ),
    );
  }

  /// 账户操作中的一行：标题 + 副标题 + 右侧按钮
  Widget _accountActionRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget button,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(translate(title),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(translate(subtitle),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          button,
        ],
      ),
    );
  }

  Future<void> _doEditProfile() async {
    final currentUsername = _userInfo?['username']?.toString() ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _EditProfileDialog(currentUsername: currentUsername),
    );
    if (!mounted) return;
    if (ok == true) {
      showToast(translate('change_username_success'));
      // 重新加载用户信息以刷新卡片中显示的用户名
      await _loadUserInfo();
    }
  }

  Future<void> _doChangePassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => desktop_login.DesktopChangeOwnPasswordDialog(
        title: translate('Change Password'),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginTabPage(
              windowSize: kDesktopMainWindowSize,
              child: desktop_login.AppLoginPage()),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (route) => false,
      );
    }
  }

  Future<void> _doForgotPassword() async {
    // Reuses the public phone + SMS reset-password dialog from the login page.
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => desktop_login.DesktopChangePasswordDialog(
        title: translate('Forgot Password'),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      // Password changed; force re-login.
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginTabPage(
              windowSize: kDesktopMainWindowSize,
              child: desktop_login.AppLoginPage()),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (route) => false,
      );
    }
  }

  Future<void> _doLogout() async {
    final confirmed = await gFFI.dialogManager.show<bool>(
      (setState, close, context) {
        return CustomAlertDialog(
          title: Text(translate('Sign out of your account')),
          content: Text(translate('confirm_to_logout')),
          actions: [
            dialogButton(translate('Cancel'), onPressed: () => close(false)),
            dialogButton(translate('Confirm_logout'), onPressed: () => close(true)),
          ],
        );
      },
    );
    if (confirmed == true) {
      await AppAuthService().logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
              pageBuilder: (_, __, ___) => const LoginTabPage(
                  windowSize: kDesktopMainWindowSize,
                  child: desktop_login.AppLoginPage()),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero),
          (route) => false,
        );
      }
    }
  }

  Future<void> _doDeregister() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeregisterAccountDialog(),
    );
    if (!mounted) return;
    if (ok == true) {
      // 账号已注销并登出，返回登录页
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginTabPage(
              windowSize: kDesktopMainWindowSize,
              child: desktop_login.AppLoginPage()),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (route) => false,
      );
    }
  }

  Widget _accountSecurityCard(BuildContext context) {
    return _GCard(
      icon: Icons.shield_outlined,
      iconColor: Colors.blue,
      title: 'Account Security',
      children: [
        _accountLinkRow(
          context,
          title: 'Change Password',
          subtitle: 'acc_change_pwd_sub',
          onTap: () => _doChangePassword(),
        ),
        _accountLinkRow(
          context,
          title: 'Forgot Password',
          subtitle: 'acc_forgot_pwd_sub',
          onTap: () => _doForgotPassword(),
        ),
      ],
    );
  }

  Widget _accountActionsCard(BuildContext context) {
    return _GCard(
      icon: Icons.manage_accounts_outlined,
      iconColor: Colors.green,
      title: 'Account Actions',
      children: [
        _accountActionRow(
          context,
          title: 'Sign out of your account',
          subtitle: 'acc_logout_sub',
          button: OutlinedButton(
            onPressed: () => _doLogout(),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accentColor,
              side: BorderSide(color: _accentColor.withOpacity(0.6)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(translate('Sign out of your account')),
          ),
        ),
        _accountActionRow(
          context,
          title: 'Deregister account',
          subtitle: 'acc_deregister_sub',
          button: OutlinedButton(
            onPressed: () => _doDeregister(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              side: const BorderSide(color: Color(0xFFEF4444)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(translate('Deregister account')),
          ),
        ),
      ],
    );
  }
}

/// 注销账号对话框：需先验证绑定手机号与短信验证码，确认后永久删除账号。
/// 编辑资料对话框：当前仅支持修改用户名（凭登录密码验证身份）。
class _EditProfileDialog extends StatefulWidget {
  final String currentUsername;
  const _EditProfileDialog({Key? key, required this.currentUsername})
      : super(key: key);

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AppAuthService();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 取服务端校验（中文/英文/数字）与客户端习惯的交集：1-20 位英文或数字，
  // 既能通过服务端 isValidUsername，又避免输入法叠字问题。
  bool _isUsernameValid(String value) {
    if (value.length < 1 || value.length > 20) return false;
    return RegExp(r'^[A-Za-z0-9]+$').hasMatch(value);
  }

  Future<void> _submit() async {
    final newUsername = _usernameController.text.trim();
    final password = _passwordController.text;

    if (newUsername.isEmpty) {
      setState(() => _errorMsg = translate('please_enter_username'));
      return;
    }
    if (!_isUsernameValid(newUsername)) {
      setState(() => _errorMsg = translate('username_rule_tip'));
      return;
    }
    if (newUsername == widget.currentUsername) {
      setState(() => _errorMsg = translate('username_unchanged'));
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMsg = translate('please_enter_password'));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final error = await _authService.changeUsername(
      newUsername: newUsername,
      password: password,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (error != null) {
      setState(() => _errorMsg = error);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(translate('Edit profile')),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.currentUsername.isNotEmpty) ...[
                Text(
                  '${translate('current_username_label')}: ${widget.currentUsername}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                decoration: InputDecoration(
                  labelText: translate('new_username_label'),
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[一-鿿]')),
                ],
                decoration: InputDecoration(
                  labelText: translate('verify_identity_password'),
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorMsg!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isLoading ? null : () => Navigator.of(context).pop(false),
          child: Text(translate('Cancel')),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentColor,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : Text(translate('confirm_change_btn')),
        ),
      ],
    );
  }
}

class _DeregisterAccountDialog extends StatefulWidget {
  const _DeregisterAccountDialog({Key? key}) : super(key: key);

  @override
  State<_DeregisterAccountDialog> createState() =>
      _DeregisterAccountDialogState();
}

class _DeregisterAccountDialogState extends State<_DeregisterAccountDialog> {
  static const Color _dangerColor = Color(0xFFEF4444);

  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  final _authService = AppAuthService();

  bool _isLoading = false;
  bool _isSendingSms = false;
  String? _errorMsg;
  int _countdown = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadBoundPhone();
  }

  Future<void> _loadBoundPhone() async {
    final info = await _authService.getUserInfo();
    final phone = info?['phone']?.toString().trim() ?? '';
    if (mounted && phone.isNotEmpty) {
      setState(() => _phoneController.text = phone);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _smsCodeController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _countdown = 0);
      } else {
        if (mounted) setState(() => _countdown--);
      }
    });
  }

  Future<void> _sendSmsCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMsg = translate('please_enter_phone'));
      return;
    }
    if (phone.length != 11) {
      setState(() => _errorMsg = translate('phone_must_be_11_digits'));
      return;
    }
    setState(() {
      _isSendingSms = true;
      _errorMsg = null;
    });
    final error = await _authService.sendSmsCode(phone: phone);
    if (!mounted) return;
    setState(() => _isSendingSms = false);
    if (error != null) {
      setState(() => _errorMsg = error);
      return;
    }
    _startCountdown();
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    final smsCode = _smsCodeController.text.trim();

    if (phone.isEmpty) {
      setState(() => _errorMsg = translate('please_enter_phone'));
      return;
    }
    if (phone.length != 11) {
      setState(() => _errorMsg = translate('phone_must_be_11_digits'));
      return;
    }
    if (smsCode.isEmpty) {
      setState(() => _errorMsg = translate('please_enter_sms_code'));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final error = await _authService.deleteAccount(
      phone: phone,
      smsCode: smsCode,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (error != null) {
      setState(() => _errorMsg = error);
      return;
    }
    showToast(translate('deregister_success'));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: Text(translate('Deregister account')),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _dangerColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: _dangerColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        translate('deregister_warning'),
                        style: const TextStyle(
                            color: _dangerColor, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: InputDecoration(
                  labelText: translate('Phone Number'),
                  prefixIcon: const Icon(Icons.phone_android, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _smsCodeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(
                        labelText: translate('Verification code'),
                        prefixIcon: const Icon(Icons.sms_outlined, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed:
                          (_countdown > 0 || _isSendingSms || _isLoading)
                              ? null
                              : _sendSmsCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        elevation: 0,
                      ),
                      child: Text(
                        _countdown > 0
                            ? '${_countdown}s'
                            : translate('get_sms_code'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMsg!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                translate('sms_hint'),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isLoading ? null : () => Navigator.of(context).pop(false),
          child: Text(translate('Cancel')),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _dangerColor,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : Text(translate('confirm_deregister')),
        ),
      ],
    );
  }
}

class _Advanced extends StatefulWidget {
  const _Advanced({Key? key}) : super(key: key);

  @override
  State<_Advanced> createState() => _AdvancedState();
}

class _AdvancedState extends State<_Advanced> {
  // A single toggle row: title + optional description + switch. Rows carry no
  // icon of their own; they are indented to line up under the card's section
  // header title. (`icon`/`iconColor` are accepted for call-site convenience
  // but are not rendered.)
  Widget _toggleRow({
    IconData? icon,
    Color? iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
      child: Row(
        children: [
          // Indent to align with the section header title (icon 38 + gap 14).
          const SizedBox(width: 52),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(translate(title),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(translate(subtitle),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9CA3AF))),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            activeColor: MyTheme.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // A toggle row bound to a config option (server or local).
  Widget _optionToggle({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required String key,
    bool isServer = true,
    bool Function()? optGetter,
    Future<void> Function(String, bool)? optSetter,
    void Function(bool)? update,
  }) {
    final value = optGetter != null
        ? optGetter()
        : (isServer
            ? mainGetBoolOptionSync(key)
            : mainGetLocalBoolOptionSync(key));
    final isOptFixed = isOptionFixed(key);
    return _toggleRow(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: isOptFixed
          ? null
          : (b) async {
              final setter = optSetter ??
                  (isServer ? mainSetBoolOption : mainSetLocalBoolOption);
              await setter(key, b);
              update?.call(b);
              setState(() {});
            },
    );
  }

  // A toggle row bound to a per-session "user default" option (moved here from
  // the Remote control panel's "Other default options").
  Widget _defaultOptionToggle({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required String key,
  }) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    final isOptFixed = isOptionFixed(key);
    return _toggleRow(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: isOptFixed
          ? null
          : (b) async {
              await bind.mainSetUserDefaultOption(
                key: key,
                value: b
                    ? 'Y'
                    : (key == kOptionEnableFileCopyPaste
                        ? 'N'
                        : defaultOptionNo),
              );
              setState(() {});
            },
    );
  }

  Widget _wallpaperToggle() {
    return futureBuilder(
      future: bind.mainSupportRemoveWallpaper(),
      hasData: (support) {
        if (support is bool && support) {
          return _optionToggle(
            icon: Icons.wallpaper_outlined,
            iconColor: Colors.redAccent,
            title: 'Remove wallpaper during incoming sessions',
            subtitle: 'remove_wallpaper_tip',
            key: kOptionAllowRemoveWallpaper,
          );
        }
        return const Offstage();
      },
    );
  }

  // The section header that sits as the first row inside a card: a colored
  // rounded-square icon followed by the bold section title.
  Widget _cardHeader(IconData icon, Color iconColor, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              translate(title),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      margin:
          const EdgeInsets.fromLTRB(_kCardLeftMargin, 14, _kContentHMargin, 0),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // Per-session "user default" options rendered on this page. Resetting one to
  // an empty value removes the override and falls back to its built-in default.
  static const List<String> _userDefaultKeys = [
    kOptionViewOnly,
    kOptionPrivacyMode,
    kOptionDisableAudio,
    kOptionCollapseToolbar,
    kOptionLockAfterSessionEnd,
    kKeyReverseMouseWheel,
    kOptionSwapLeftRightMouse,
    kOptionShowRemoteCursor,
    kOptionShowQualityMonitor,
    kOptionI444,
    kKeyUseAllMyDisplaysForTheRemoteSession,
    kOptionEnableFileCopyPaste,
    kOptionDisableClipboard,
  ];

  // Shared (server) options rendered on this page.
  static const List<String> _serverOptionKeys = [
    kOptionAllowRemoveWallpaper,
    kOptionEnableHwcodec,
    kOptionEnableAbr,
    kOptionAllowAlwaysSoftwareRender,
    kOptionDirectxCapture,
    kOptionAllowAutoUpdate,
    kOptionAllowLinuxHeadless,
  ];

  // Local (this device) options rendered on this page.
  static const List<String> _localOptionKeys = [
    kOptionEnableConfirmClosingTabs,
    kOptionOpenNewConnInTabs,
    kOptionTextureRender,
    kOptionD3DRender,
    kOptionEnableUdpPunch,
    kOptionEnableIpv6Punch,
    kOptionKeepAwakeDuringOutgoingSessions,
  ];

  // Restore every option shown on this page back to its built-in default. An
  // empty value removes the stored override for each config scope. Skips
  // options that are fixed/locked by the deployment.
  Future<void> _restoreDefaults() async {
    final confirmed = await gFFI.dialogManager.show<bool>(
      (setState, close, context) {
        return CustomAlertDialog(
          title: Text(translate('Restore defaults')),
          content: Text(translate('restore_defaults_tip')),
          actions: [
            dialogButton('Cancel', onPressed: () => close(false), isOutline: true),
            dialogButton('OK', onPressed: () => close(true)),
          ],
        );
      },
    );
    if (confirmed != true) return;
    for (final k in _userDefaultKeys) {
      if (!isOptionFixed(k)) {
        await bind.mainSetUserDefaultOption(key: k, value: '');
      }
    }
    for (final k in _serverOptionKeys) {
      if (!isOptionFixed(k)) {
        await bind.mainSetOption(key: k, value: '');
      }
    }
    for (final k in _localOptionKeys) {
      if (!isOptionFixed(k)) {
        await bind.mainSetLocalOption(key: k, value: '');
      }
    }
    // Re-validate hardware codec availability since its option may have changed.
    if (bind.mainHasHwcodec() || bind.mainHasVram()) {
      bind.mainCheckHwcodec();
    }
    if (!mounted) return;
    setState(() {});
    showToast(translate('Restored to default'));
  }

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    final hasHwcodec = bind.mainHasHwcodec() || bind.mainHasVram();
    final showAutoUpdate =
        isWindows && bind.mainIsInstalled() && !bind.isCustomClient();
    final outgoingOk = !bind.isIncomingOnly();
    final incomingOk = !bind.isOutgoingOnly();

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
            _kCardLeftMargin + 4, 20, _kContentHMargin, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translate('Advanced features'),
              style: const TextStyle(
                  fontSize: _kTitleFontSize, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              translate('advanced_features_tip'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    ];

    void section(
        String title, IconData icon, Color iconColor, List<Widget> toggles) {
      if (toggles.isEmpty) return;
      children.add(_card([_cardHeader(icon, iconColor, title), ...toggles]));
    }

    // 会话与隐私
    section('Session and privacy', Icons.shield_outlined, Colors.blue, [
      _defaultOptionToggle(
        icon: Icons.screen_share_outlined,
        iconColor: Colors.blue,
        title: 'Screen sharing mode',
        subtitle: 'adv_screen_share_sub',
        key: kOptionViewOnly,
      ),
      _defaultOptionToggle(
        icon: Icons.visibility_off_outlined,
        iconColor: Colors.redAccent,
        title: 'Privacy mode',
        subtitle: 'adv_privacy_mode_sub',
        key: kOptionPrivacyMode,
      ),
      // 图片以外保留的功能
      _defaultOptionToggle(
        icon: Icons.volume_off_outlined,
        iconColor: Colors.redAccent,
        title: 'Mute',
        subtitle: 'adv_mute_sub',
        key: kOptionDisableAudio,
      ),
      if (incomingOk) _wallpaperToggle(),
    ]);

    // 窗口与工具栏
    section('Window and toolbar', Icons.web_asset_outlined, Colors.blue, [
      _defaultOptionToggle(
        icon: Icons.unfold_less,
        iconColor: Colors.blue,
        title: 'Collapse toolbar',
        subtitle: 'adv_collapse_toolbar_sub',
        key: kOptionCollapseToolbar,
      ),
      _defaultOptionToggle(
        icon: Icons.lock_clock_outlined,
        iconColor: Colors.indigo,
        title: 'Lock after session end',
        subtitle: 'adv_lock_after_sub',
        key: kOptionLockAfterSessionEnd,
      ),
      // 图片以外保留的功能
      if (outgoingOk)
        _optionToggle(
          icon: Icons.tab_outlined,
          iconColor: Colors.indigo,
          title: 'Confirm before closing multiple tabs',
          subtitle: 'confirm_close_tabs_tip',
          key: kOptionEnableConfirmClosingTabs,
          isServer: false,
        ),
      if (outgoingOk)
        _optionToggle(
          icon: Icons.open_in_new_outlined,
          iconColor: Colors.indigo,
          title: 'Open connection in new tab',
          subtitle: 'open_new_tab_tip',
          key: kOptionOpenNewConnInTabs,
          isServer: false,
        ),
    ]);

    // 输入增强
    section('Input enhancement', Icons.mouse_outlined, Colors.purple, [
      _defaultOptionToggle(
        icon: Icons.swap_vert,
        iconColor: Colors.teal,
        title: 'Reverse mouse wheel',
        subtitle: 'adv_reverse_wheel_sub',
        key: kKeyReverseMouseWheel,
      ),
      _defaultOptionToggle(
        icon: Icons.swap_horiz,
        iconColor: Colors.teal,
        title: 'swap-left-right-mouse',
        subtitle: 'adv_swap_mouse_sub',
        key: kOptionSwapLeftRightMouse,
      ),
    ]);

    // 显示与性能
    section('Display and performance', Icons.desktop_windows_outlined,
        Colors.green, [
      _defaultOptionToggle(
        icon: Icons.mouse_outlined,
        iconColor: Colors.green,
        title: 'Show remote cursor',
        subtitle: 'adv_show_cursor_sub',
        key: kOptionShowRemoteCursor,
      ),
      _defaultOptionToggle(
        icon: Icons.analytics_outlined,
        iconColor: Colors.green,
        title: 'Show quality monitor',
        subtitle: 'adv_quality_monitor_sub',
        key: kOptionShowQualityMonitor,
      ),
      // 图片以外保留的功能
      if (hasHwcodec)
        _optionToggle(
          icon: Icons.memory_outlined,
          iconColor: Colors.green,
          title: 'Enable hardware codec',
          subtitle: 'hwcodec_advanced_tip',
          key: kOptionEnableHwcodec,
          update: (v) {
            if (v) bind.mainCheckHwcodec();
          },
        ),
      _optionToggle(
        icon: Icons.speed_outlined,
        iconColor: Colors.green,
        title: 'Adaptive bitrate',
        subtitle: 'adaptive_bitrate_tip',
        key: kOptionEnableAbr,
      ),
      if (outgoingOk)
        _optionToggle(
          icon: Icons.texture_outlined,
          iconColor: Colors.teal,
          title: 'Use texture rendering',
          subtitle: 'texture_render_tip',
          key: kOptionTextureRender,
          optGetter: bind.mainGetUseTextureRender,
          optSetter: (k, v) async =>
              await bind.mainSetLocalOption(key: k, value: v ? 'Y' : 'N'),
        ),
      if (outgoingOk && isWindows)
        _optionToggle(
          icon: Icons.view_in_ar_outlined,
          iconColor: Colors.teal,
          title: 'Use D3D rendering',
          subtitle: 'd3d_render_tip',
          key: kOptionD3DRender,
          isServer: false,
        ),
      if (outgoingOk && isLinux)
        _optionToggle(
          icon: Icons.developer_board_outlined,
          iconColor: Colors.teal,
          title: 'Always use software rendering',
          subtitle: 'software_render_tip',
          key: kOptionAllowAlwaysSoftwareRender,
        ),
      if (isWindows && incomingOk)
        _optionToggle(
          icon: Icons.videocam_outlined,
          iconColor: Colors.blue,
          title: 'Capture screen using DirectX',
          subtitle: 'directx_capture_tip',
          key: kOptionDirectxCapture,
        ),
      _defaultOptionToggle(
        icon: Icons.palette_outlined,
        iconColor: Colors.green,
        title: 'True color (4:4:4)',
        subtitle: 'adv_true_color_sub',
        key: kOptionI444,
      ),
    ]);

    // 网络与性能
    section('Network and performance', Icons.public_outlined, Colors.orange, [
      _defaultOptionToggle(
        icon: Icons.content_copy_outlined,
        iconColor: Colors.orange,
        title: 'Enable file copy and paste',
        subtitle: 'adv_file_copy_sub',
        key: kOptionEnableFileCopyPaste,
      ),
      _defaultOptionToggle(
        icon: Icons.content_paste_off_outlined,
        iconColor: Colors.orange,
        title: 'Disable clipboard',
        subtitle: 'adv_disable_clipboard_sub',
        key: kOptionDisableClipboard,
      ),
    ]);

    // 实验功能
    section('Experimental features', Icons.science_outlined, Colors.purple, [
      _defaultOptionToggle(
        icon: Icons.desktop_windows_outlined,
        iconColor: Colors.purple,
        title: 'Open displays in a single window',
        subtitle: 'adv_single_window_sub',
        key: kKeyUseAllMyDisplaysForTheRemoteSession,
      ),
      if (outgoingOk)
        _optionToggle(
          icon: Icons.bolt_outlined,
          iconColor: Colors.purple,
          title: 'Enable UDP connection',
          subtitle: 'adv_udp_sub',
          key: kOptionEnableUdpPunch,
          isServer: false,
        ),
      if (outgoingOk)
        _optionToggle(
          icon: Icons.lan_outlined,
          iconColor: Colors.purple,
          title: 'Enable IPv6 connection',
          subtitle: 'adv_ipv6_sub',
          key: kOptionEnableIpv6Punch,
          isServer: false,
        ),
      // 图片以外保留的功能
      if (showAutoUpdate)
        _optionToggle(
          icon: Icons.autorenew,
          iconColor: Colors.purple,
          title: 'Auto update',
          subtitle: 'auto_update_tip',
          key: kOptionAllowAutoUpdate,
        ),
      if (outgoingOk)
        _optionToggle(
          icon: Icons.bedtime_outlined,
          iconColor: Colors.purple,
          title: 'keep-awake-during-outgoing-sessions-label',
          subtitle: 'keep_awake_tip',
          key: kOptionKeepAwakeDuringOutgoingSessions,
          isServer: false,
        ),
      if (bind.mainShowOption(key: kOptionAllowLinuxHeadless))
        _optionToggle(
          icon: Icons.terminal_outlined,
          iconColor: Colors.purple,
          title: 'Allow linux headless',
          subtitle: 'linux_headless_tip',
          key: kOptionAllowLinuxHeadless,
        ),
    ]);

    children.add(
      Padding(
        padding:
            const EdgeInsets.fromLTRB(_kCardLeftMargin, 16, _kContentHMargin, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: _restoreDefaults,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF374151),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(translate('Restore defaults')),
            ),
          ],
        ),
      ),
    );

    return ListView(
      controller: scrollController,
      children: children,
    ).marginOnly(bottom: _kListViewBottomMargin);
  }
}

class _Checkbox extends StatefulWidget {
  final String label;
  final bool Function() getValue;
  final Future<void> Function(bool) setValue;

  const _Checkbox(
      {Key? key,
      required this.label,
      required this.getValue,
      required this.setValue})
      : super(key: key);

  @override
  State<_Checkbox> createState() => _CheckboxState();
}

class _CheckboxState extends State<_Checkbox> {
  var value = false;

  @override
  initState() {
    super.initState();
    value = widget.getValue();
  }

  @override
  Widget build(BuildContext context) {
    onChanged(bool b) async {
      await widget.setValue(b);
      setState(() {
        value = widget.getValue();
      });
    }

    return GestureDetector(
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (_) => onChanged(!value),
          ).marginOnly(right: 5),
          Expanded(
            child: Text(translate(widget.label)),
          )
        ],
      ).marginOnly(left: _kCheckBoxLeftMargin),
      onTap: () => onChanged(!value),
    );
  }
}

class _Plugin extends StatefulWidget {
  const _Plugin({Key? key}) : super(key: key);

  @override
  State<_Plugin> createState() => _PluginState();
}

class _PluginState extends State<_Plugin> {
  @override
  Widget build(BuildContext context) {
    bind.pluginListReload();
    final scrollController = ScrollController();
    return ChangeNotifierProvider.value(
      value: pluginManager,
      child: Consumer<PluginManager>(builder: (context, model, child) {
        return ListView(
          controller: scrollController,
          children: model.plugins.map((entry) => pluginCard(entry)).toList(),
        ).marginOnly(bottom: _kListViewBottomMargin);
      }),
    );
  }

  Widget pluginCard(PluginInfo plugin) {
    return ChangeNotifierProvider.value(
      value: plugin,
      child: Consumer<PluginInfo>(
        builder: (context, model, child) => DesktopSettingsCard(plugin: model),
      ),
    );
  }

  Widget accountAction() {
    return Obx(() => _Button(
        gFFI.userModel.userName.value.isEmpty
            ? 'Login'
            : '${translate('Logout')} (${gFFI.userModel.accountLabelWithHandle})',
        () => {
              gFFI.userModel.userName.value.isEmpty
                  ? loginDialog()
                  : logOutConfirmDialog()
            }));
  }
}

class _Update extends StatefulWidget {
  const _Update({Key? key}) : super(key: key);

  @override
  State<_Update> createState() => _UpdateState();
}

class _UpdateState extends State<_Update> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        _settingsPageHeader('Update', 'Keep your software up to date'),
        _updateStatusCard(context),
        _checkUpdateCard(context),
        _releasesCard(context),
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  // Top card: reacts to the global update state, showing either an
  // "up to date" status or an "update available" call-to-action. Uses the
  // shared [_GCard] so it matches the other settings pages.
  Widget _updateStatusCard(BuildContext context) {
    return Obx(() {
      final updateUrl = stateGlobal.updateUrl.value;
      if (updateUrl.isEmpty) {
        // Up to date — calm, reassuring status card with the current version.
        return FutureBuilder<String>(
          future: bind.mainGetVersion(),
          builder: (context, snapshot) {
            final version = snapshot.data ?? '';
            return _GCard(
              icon: Icons.check_circle_outline,
              iconColor: const Color(0xFF22C55E),
              title: 'Your version is up to date',
              subtitle:
                  version.isEmpty ? null : '${translate('Version')}: $version',
            );
          },
        );
      }

      // Update available — highlighted card with a call-to-action button.
      final serverDownloadUrl = stateGlobal.serverDownloadUrl.value;
      final serverLatestVersion = stateGlobal.serverLatestVersion.value;
      final versionText = serverLatestVersion.isNotEmpty
          ? serverLatestVersion
          : bind.mainGetNewVersion();
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      final btnText = isToUpdate ? 'Update' : 'Download';

      return _GCard(
        icon: Icons.rocket_launch_outlined,
        iconColor: MyTheme.accent,
        title: 'New version available',
        subtitle:
            '${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} ($versionText).',
        trailing: SizedBox(
          height: 40,
          child: ElevatedButton(
            onPressed: () async {
              final url =
                  serverDownloadUrl.isNotEmpty ? serverDownloadUrl : updateUrl;
              if (isToUpdate) {
                handleUpdate(updateUrl, directDownloadUrl: serverDownloadUrl);
              } else if (url.isNotEmpty) {
                await launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication);
              }
            },
            style: _gCardButtonStyle,
            child: Text(translate(btnText),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      );
    });
  }

  // "Check for updates on startup" preference, rendered as a trailing switch
  // exactly like the other toggle cards (e.g. the General → Service card).
  Widget _checkUpdateCard(BuildContext context) {
    final value = mainGetLocalBoolOptionSync(kOptionEnableCheckUpdate);
    final isOptFixed = isOptionFixed(kOptionEnableCheckUpdate);
    return _GCard(
      icon: Icons.system_update_outlined,
      iconColor: const Color(0xFF8B5CF6),
      title: 'Check for software update on startup',
      subtitle: 'check_update_tip',
      trailing: Switch(
        value: value,
        activeColor: MyTheme.accent,
        onChanged: isOptFixed
            ? null
            : (b) async {
                await mainSetLocalBoolOption(kOptionEnableCheckUpdate, b);
                setState(() {});
              },
      ),
    );
  }

  // Downloadable editions grouped in a single card body, each a row with its
  // own colored icon badge and a download button.
  Widget _releasesCard(BuildContext context) {
    return _GCard(
      icon: Icons.download_outlined,
      iconColor: const Color(0xFF3B82F6),
      title: 'Releases',
      subtitle: 'Download different versions of LinkEase',
      children: [
        _releaseRow(
          context,
          icon: Icons.people_outline,
          accent: const Color(0xFF3B82F6),
          title: 'User Edition',
          subtitle: 'Tools for regular users',
          url: 'https://jyyxt.cloud/releases/share',
        ),
        _releaseRow(
          context,
          icon: Icons.support_agent_outlined,
          accent: const Color(0xFF16A34A),
          title: 'Support Edition',
          subtitle: 'Dedicated tools for support staff',
          url: 'https://jyyxt.cloud/releases/tech',
        ),
      ],
    );
  }

  Widget _releaseRow(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required String url,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translate(title),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  translate(subtitle),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: () => launchUrlString(url),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: Text(translate('Go to Download'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              style: _gCardButtonStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _Printer extends StatefulWidget {
  const _Printer({super.key});

  @override
  State<_Printer> createState() => __PrinterState();
}

class __PrinterState extends State<_Printer> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(controller: scrollController, children: [
      outgoing(context),
      incoming(context),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget outgoing(BuildContext context) {
    final isSupportPrinterDriver =
        bind.mainGetCommonSync(key: 'is-support-printer-driver') == 'true';

    Widget tipOsNotSupported() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-os-requirement-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipClientNotInstalled() {
      return Align(
        alignment: Alignment.topLeft,
        child:
            Text(translate('printer-requires-installed-{$appName}-client-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipPrinterNotInstalled() {
      final failedMsg = ''.obs;
      platformFFI.registerEventHandler(
          'install-printer-res', 'install-printer-res', (evt) async {
        if (evt['success'] as bool) {
          setState(() {});
        } else {
          failedMsg.value = evt['msg'] as String;
        }
      }, replace: true);
      return Column(children: [
        Obx(
          () => failedMsg.value.isNotEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(translate('printer-{$appName}-not-installed-tip'))
                      .marginOnly(bottom: 10.0),
                ),
        ),
        Obx(
          () => failedMsg.value.isEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(failedMsg.value,
                          style: DefaultTextStyle.of(context)
                              .style
                              .copyWith(color: Colors.red))
                      .marginOnly(bottom: 10.0)),
        ),
        _Button('Install {$appName} Printer', () {
          failedMsg.value = '';
          bind.mainSetCommon(key: 'install-printer', value: '');
        })
      ]).marginOnly(left: _kCardLeftMargin, bottom: 2.0);
    }

    Widget tipReady() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-{$appName}-ready-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    final installed = bind.mainIsInstalled();
    // `is-printer-installed` may fail, but it's rare case.
    // Add additional error message here if it's really needed.
    final isPrinterInstalled =
        bind.mainGetCommonSync(key: 'is-printer-installed') == 'true';

    final List<Widget> children = [];
    if (!isSupportPrinterDriver) {
      children.add(tipOsNotSupported());
    } else {
      children.addAll([
        if (!installed) tipClientNotInstalled(),
        if (installed && !isPrinterInstalled) tipPrinterNotInstalled(),
        if (installed && isPrinterInstalled) tipReady()
      ]);
    }
    return _Card(title: 'Outgoing Print Jobs', children: children);
  }

  Widget incoming(BuildContext context) {
    onRadioChanged(String value) async {
      await bind.mainSetLocalOption(
          key: kKeyPrinterIncomingJobAction, value: value);
      setState(() {});
    }

    PrinterOptions printerOptions = PrinterOptions.load();
    return _Card(title: 'Incoming Print Jobs', children: [
      _Radio(context,
          value: kValuePrinterIncomingJobDismiss,
          groupValue: printerOptions.action,
          label: 'Dismiss',
          onChanged: onRadioChanged),
      _Radio(context,
          value: kValuePrinterIncomingJobDefault,
          groupValue: printerOptions.action,
          label: 'use-the-default-printer-tip',
          onChanged: onRadioChanged),
      _Radio(context,
          value: kValuePrinterIncomingJobSelected,
          groupValue: printerOptions.action,
          label: 'use-the-selected-printer-tip',
          onChanged: onRadioChanged),
      if (printerOptions.printerNames.isNotEmpty)
        ComboBox(
          initialKey: printerOptions.printerName,
          keys: printerOptions.printerNames,
          values: printerOptions.printerNames,
          enabled: printerOptions.action == kValuePrinterIncomingJobSelected,
          onChanged: (value) async {
            await bind.mainSetLocalOption(
                key: kKeyPrinterSelected, value: value);
            setState(() {});
          },
        ).marginOnly(left: 10),
      _OptionCheckBox(
        context,
        'auto-print-tip',
        kKeyPrinterAllowAutoPrint,
        isServer: false,
        enabled: printerOptions.action != kValuePrinterIncomingJobDismiss,
      )
    ]);
  }
}

class _About extends StatefulWidget {
  const _About({Key? key}) : super(key: key);

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  /// Single info row: icon-wrap on left, label, monospace value on right.
  /// Mirrors HTML .info-row structure.
  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final secondaryBg = Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon wrap — 28×28 rounded square with secondary bg
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: secondaryBg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 13, color: const Color(0xFF3b82f6)),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              label,
              style: TextStyle(
                fontSize: _kContentFontSize,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectionArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pill-shaped link button — mirrors HTML .link-pill
  Widget _linkPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final borderColor = Theme.of(context).dividerColor.withOpacity(0.5);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12,
                color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
  return futureBuilder(future: () async {
    final license = await bind.mainGetLicense();
    final version = await bind.mainGetVersion();
    final buildDate = await bind.mainGetBuildDate();
    final fingerprint = await bind.mainGetFingerprint();
    return {
      'license': license,
      'version': version,
      'buildDate': buildDate,
      'fingerprint': fingerprint,
    };
  }(), hasData: (data) {
    final version = data['version'].toString();
    final buildDate = data['buildDate'].toString();
    final fingerprint = data['fingerprint'].toString();
    final scrollController = ScrollController();
    final borderColor = Theme.of(context).dividerColor.withOpacity(0.5);
    final secondaryBg =
        Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4);

    return SingleChildScrollView(
      controller: scrollController,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Logo ──
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.transparent,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/about_logo.png',
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.important_devices_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── App name ──
                Text(
                  bind.mainGetAppNameSync(),
                  style: const TextStyle(
                    fontSize: _kTitleFontSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),

                // ── Tagline ──
                Text(
                  translate('Remote Control Tagline'), // ✅ 原来是 'Remote Control · 远程控制工具'
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Info block ──
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      _infoRow(context,
                          icon: Icons.info_outline,
                          label: translate('Version'),
                          value: version),
                      Divider(height: 0.5, thickness: 0.5, color: borderColor),
                      _infoRow(context,
                          icon: Icons.calendar_today_outlined,
                          label: translate('Build Date'),
                          value: buildDate),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // ── Link pills ──
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    _linkPill(context,
                        icon: Icons.privacy_tip_outlined,
                        label: translate('Privacy Statement'),
                        onTap: () {
                          Navigator.of(context).push(PageRouteBuilder(
                              pageBuilder: (_, __, ___) =>
                                  const privacy_pages.PrivacyPolicyPage(),
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero));
                        }),
                    _linkPill(context,
                        icon: Icons.description_outlined,
                        label: translate('Terms of Service'), // ✅ 原来是 '用户服务协议'
                        onTap: () {
                          Navigator.of(context).push(PageRouteBuilder(
                              pageBuilder: (_, __, ___) =>
                                  const terms_pages.TermsOfServicePage(),
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero));
                        }),
                    _linkPill(context,
                        icon: Icons.language,
                        label: translate('Website'),
                        onTap: () => launchUrlString('https://jygamwing.com/')),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Footer block ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: secondaryBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/brand.jpg',
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        translate('Slogan_tip'),
                        style: TextStyle(
                          fontSize: _kContentFontSize,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        translate('Copyright Notice'),
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.8,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withOpacity(0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  });
}
}

//#endregion

//#region components

// ignore: non_constant_identifier_names
Widget _Card(
    {required String title,
    required List<Widget> children,
    List<Widget>? title_suffix,
    double topMargin = 15}) {
  return Row(
    children: [
      Flexible(
        child: SizedBox(
          width: _kCardFixedWidth,
          child: Card(
            child: Column(
              children: [
                if (title.isNotEmpty || (title_suffix != null && title_suffix.isNotEmpty))
                  Row(
                    children: [
                      Expanded(
                          child: Text(
                        translate(title),
                        textAlign: TextAlign.start,
                        style: const TextStyle(
                          fontSize: _kTitleFontSize,
                        ),
                      )),
                      ...?title_suffix
                    ],
                  ).marginOnly(left: _kContentHMargin, top: 10, bottom: 10),
                ...children
                    .map((e) => e.marginOnly(top: 4, right: _kContentHMargin)),
              ],
            ).marginOnly(bottom: 10),
          ).marginOnly(left: _kCardLeftMargin, top: topMargin),
        ),
      ),
    ],
  );
}

// Shared accent button style for controls inside [_GCard] (e.g. the Service
// start/stop button and the Recording "Change" button), so all card buttons
// look identical.
final ButtonStyle _gCardButtonStyle = ElevatedButton.styleFrom(
  backgroundColor: MyTheme.accent,
  foregroundColor: Colors.white,
  elevation: 0,
  padding: const EdgeInsets.symmetric(horizontal: 22),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
);

// Image-style card used by the General settings page: a white rounded card
// with a colored icon, title, optional subtitle and an optional trailing
// control (or a vertical body of [children]).
// ignore: non_constant_identifier_names
// A page-level header rendered at the top of a settings page: a bold title
// with a muted descriptive subtitle below it.
Widget _settingsPageHeader(String title, String subtitle) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(_kCardLeftMargin, 18, _kContentHMargin, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translate(title),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          translate(subtitle),
          style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
        ),
      ],
    ),
  );
}

Widget _GCard({
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? trailing,
  List<Widget> children = const [],
  Color iconColor = _accentColor,
}) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(_kCardLeftMargin, 15, _kContentHMargin, 0),
    padding: const EdgeInsets.all(18),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    translate(title),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      translate(subtitle),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: trailing,
              ),
          ],
        ),
        if (children.isNotEmpty) ...[
          const Divider(height: 28, color: Color(0xFFF0F1F4)),
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ],
    ),
  );
}

// ignore: non_constant_identifier_names
Widget _OptionCheckBox(
  BuildContext context,
  String label,
  String key, {
  Function(bool)? update,
  bool reverse = false,
  bool enabled = true,
  Icon? checkedIcon,
  bool? fakeValue,
  bool isServer = true,
  bool Function()? optGetter,
  Future<void> Function(String, bool)? optSetter,
}) {
  getOpt() => optGetter != null
      ? optGetter()
      : (isServer
          ? mainGetBoolOptionSync(key)
          : mainGetLocalBoolOptionSync(key));
  bool value = getOpt();
  final isOptFixed = isOptionFixed(key);
  if (reverse) value = !value;
  var ref = value.obs;
  onChanged(option) async {
    if (option != null) {
      if (reverse) option = !option;
      final setter =
          optSetter ?? (isServer ? mainSetBoolOption : mainSetLocalBoolOption);
      await setter(key, option);
      final readOption = getOpt();
      if (reverse) {
        ref.value = !readOption;
      } else {
        ref.value = readOption;
      }
      update?.call(readOption);
    }
  }

  if (fakeValue != null) {
    ref.value = fakeValue;
    enabled = false;
  }

  return GestureDetector(
    child: Obx(
      () => Row(
        children: [
          Checkbox(
                  value: ref.value,
                  onChanged: enabled && !isOptFixed ? onChanged : null)
              .marginOnly(right: 5),
          Offstage(
            offstage: !ref.value || checkedIcon == null,
            child: checkedIcon?.marginOnly(right: 5),
          ),
          Expanded(
              child: Text(
            translate(label),
            style: TextStyle(color: disabledTextColor(context, enabled)),
          ))
        ],
      ),
    ).marginOnly(left: _kCheckBoxLeftMargin),
    onTap: enabled && !isOptFixed
        ? () {
            onChanged(!ref.value);
          }
        : null,
  );
}

// A label + trailing iOS-style switch row used by the redesigned Security
// page: text on the left, a [Switch] on the right. Mirrors the visual style
// of the "8.2-设置-安全" mockup where connection-protection options are toggles.
Widget _switchRow(
  BuildContext context,
  String label,
  bool value,
  Function(bool)? onChanged, {
  Widget? leading,
}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onChanged != null ? () => onChanged(!value) : null,
    child: Row(
      children: [
        if (leading != null) leading,
        Expanded(
          child: Text(
            translate(label),
            style: TextStyle(
                fontSize: _kContentFontSize,
                color: disabledTextColor(context, onChanged != null)),
          ),
        ),
        const SizedBox(width: 12),
        Transform.scale(
          scale: 0.85,
          child: Switch(
            value: value,
            activeColor: _accentColor,
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  ).marginOnly(left: _kCheckBoxLeftMargin);
}

// Option-backed variant of [_switchRow]: reads/writes a boolean option key,
// mirroring [_OptionCheckBox] semantics but rendered as a switch.
// ignore: non_constant_identifier_names
Widget _OptionSwitch(
  BuildContext context,
  String label,
  String key, {
  Function(bool)? update,
  bool reverse = false,
  bool enabled = true,
  bool isServer = true,
  String? tooltip,
}) {
  getOpt() =>
      isServer ? mainGetBoolOptionSync(key) : mainGetLocalBoolOptionSync(key);
  bool value = getOpt();
  final isOptFixed = isOptionFixed(key);
  if (reverse) value = !value;
  final ref = value.obs;
  onChanged(bool option) async {
    if (reverse) option = !option;
    final setter = isServer ? mainSetBoolOption : mainSetLocalBoolOption;
    await setter(key, option);
    final readOption = getOpt();
    ref.value = reverse ? !readOption : readOption;
    update?.call(readOption);
  }

  final row = Obx(() => _switchRow(
        context,
        label,
        ref.value,
        enabled && !isOptFixed ? (v) => onChanged(v) : null,
      ));
  if (tooltip != null) {
    return Tooltip(message: translate(tooltip), child: row);
  }
  return row;
}

// Lays out [items] in a responsive two-column grid, matching the access-control
// checkbox grid in the Security mockup.
Widget _twoColumnGrid(List<Widget> items) {
  final rows = <Widget>[];
  for (int i = 0; i < items.length; i += 2) {
    rows.add(Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: items[i]),
        const SizedBox(width: 8),
        Expanded(
          child: i + 1 < items.length ? items[i + 1] : const SizedBox(),
        ),
      ],
    ));
    if (i + 2 < items.length) rows.add(const SizedBox(height: 6));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
}

// ignore: non_constant_identifier_names
Widget _Radio<T>(BuildContext context,
    {required T value,
    required T groupValue,
    required String label,
    required Function(T value)? onChanged,
    bool autoNewLine = true}) {
  final onChange2 = onChanged != null
      ? (T? value) {
          if (value != null) {
            onChanged(value);
          }
        }
      : null;
  return GestureDetector(
    child: Row(
      children: [
        Radio<T>(value: value, groupValue: groupValue, onChanged: onChange2),
        Expanded(
          child: Text(translate(label),
                  overflow: autoNewLine ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: _kContentFontSize,
                      color: disabledTextColor(context, onChange2 != null)))
              .marginOnly(left: 5),
        ),
      ],
    ).marginOnly(left: _kRadioLeftMargin),
    onTap: () => onChange2?.call(value),
  );
}

class WaylandCard extends StatefulWidget {
  const WaylandCard({Key? key}) : super(key: key);

  @override
  State<WaylandCard> createState() => _WaylandCardState();
}

class _WaylandCardState extends State<WaylandCard> {
  final restoreTokenKey = 'wayland-restore-token';
  static const _kClearShortcutsInhibitorEventKey =
      'clear-gnome-shortcuts-inhibitor-permission-res';
  final _clearShortcutsInhibitorFailedMsg = ''.obs;
  // Don't show the shortcuts permission reset button for now.
  // Users can change it manually:
  //   "Settings" -> "Apps" -> "RustDesk" -> "Permissions" -> "Inhibit Shortcuts".
  // For resetting(clearing) the permission from the portal permission store, you can
  // use (replace <desktop-id> with the RustDesk desktop file ID):
  //   busctl --user call org.freedesktop.impl.portal.PermissionStore \
  //   /org/freedesktop/impl/portal/PermissionStore org.freedesktop.impl.portal.PermissionStore \
  //   DeletePermission sss "gnome" "shortcuts-inhibitor" "<desktop-id>"
  // On a native install this is typically "rustdesk.desktop"; on Flatpak it is usually
  // the exported desktop ID derived from the Flatpak app-id (e.g. "com.rustdesk.RustDesk.desktop").
  //
  // We may add it back in the future if needed.
  final showResetInhibitorPermission = false;

  @override
  void initState() {
    super.initState();
    if (showResetInhibitorPermission) {
      platformFFI.registerEventHandler(
          _kClearShortcutsInhibitorEventKey, _kClearShortcutsInhibitorEventKey,
          (evt) async {
        if (!mounted) return;
        if (evt['success'] == true) {
          setState(() {});
        } else {
          _clearShortcutsInhibitorFailedMsg.value =
              evt['msg'] as String? ?? 'Unknown error';
        }
      });
    }
  }

  @override
  void dispose() {
    if (showResetInhibitorPermission) {
      platformFFI.unregisterEventHandler(
          _kClearShortcutsInhibitorEventKey, _kClearShortcutsInhibitorEventKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return futureBuilder(
      future: bind.mainHandleWaylandScreencastRestoreToken(
          key: restoreTokenKey, value: "get"),
      hasData: (restoreToken) {
        final hasShortcutsPermission = showResetInhibitorPermission &&
            bind.mainGetCommonSync(
                    key: "has-gnome-shortcuts-inhibitor-permission") ==
                "true";

        final children = [
          if (restoreToken.isNotEmpty)
            _buildClearScreenSelection(context, restoreToken),
          if (hasShortcutsPermission)
            _buildClearShortcutsInhibitorPermission(context),
        ];
        return Offstage(
          offstage: children.isEmpty,
          child: _Card(title: 'Wayland', children: children),
        );
      },
    );
  }

  Widget _buildClearScreenSelection(BuildContext context, String restoreToken) {
    onConfirm() async {
      final msg = await bind.mainHandleWaylandScreencastRestoreToken(
          key: restoreTokenKey, value: "clear");
      gFFI.dialogManager.dismissAll();
      if (msg.isNotEmpty) {
        msgBox(gFFI.sessionId, 'custom-nocancel', 'Error', msg, '',
            gFFI.dialogManager);
      } else {
        setState(() {});
      }
    }

    showConfirmMsgBox() => msgBoxCommon(
            gFFI.dialogManager,
            'Confirmation',
            Text(
              translate('confirm_clear_Wayland_screen_selection_tip'),
            ),
            [
              dialogButton('OK', onPressed: onConfirm),
              dialogButton('Cancel',
                  onPressed: () => gFFI.dialogManager.dismissAll())
            ]);

    return _Button(
      'Clear Wayland screen selection',
      showConfirmMsgBox,
      tip: 'clear_Wayland_screen_selection_tip',
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.all<Color>(
            Theme.of(context).colorScheme.error.withOpacity(0.75)),
      ),
    );
  }

  Widget _buildClearShortcutsInhibitorPermission(BuildContext context) {
    onConfirm() {
      _clearShortcutsInhibitorFailedMsg.value = '';
      bind.mainSetCommon(
          key: "clear-gnome-shortcuts-inhibitor-permission", value: "");
      gFFI.dialogManager.dismissAll();
    }

    showConfirmMsgBox() => msgBoxCommon(
            gFFI.dialogManager,
            'Confirmation',
            Text(
              translate('confirm-clear-shortcuts-inhibitor-permission-tip'),
            ),
            [
              dialogButton('OK', onPressed: onConfirm),
              dialogButton('Cancel',
                  onPressed: () => gFFI.dialogManager.dismissAll())
            ]);

    return Column(children: [
      Obx(
        () => _clearShortcutsInhibitorFailedMsg.value.isEmpty
            ? Offstage()
            : Align(
                alignment: Alignment.topLeft,
                child: Text(_clearShortcutsInhibitorFailedMsg.value,
                        style: DefaultTextStyle.of(context)
                            .style
                            .copyWith(color: Colors.red))
                    .marginOnly(bottom: 10.0)),
      ),
      _Button(
        'Reset keyboard shortcuts permission',
        showConfirmMsgBox,
        tip: 'clear-shortcuts-inhibitor-permission-tip',
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.all<Color>(
              Theme.of(context).colorScheme.error.withOpacity(0.75)),
        ),
      ),
    ]);
  }
}

// ignore: non_constant_identifier_names
Widget _Button(String label, Function() onPressed,
    {bool enabled = true, String? tip, ButtonStyle? style}) {
  var button = ElevatedButton(
    onPressed: enabled ? onPressed : null,
    child: Text(
      translate(label),
    ).marginSymmetric(horizontal: 15),
    style: style,
  );
  StatefulWidget child;
  if (tip == null) {
    child = button;
  } else {
    child = Tooltip(message: translate(tip), child: button);
  }
  return Row(children: [
    child,
  ]).marginOnly(left: _kContentHMargin);
}

// ignore: non_constant_identifier_names
Widget _SubButton(String label, Function() onPressed, [bool enabled = true]) {
  return Row(
    children: [
      ElevatedButton(
        onPressed: enabled ? onPressed : null,
        child: Text(
          translate(label),
        ).marginSymmetric(horizontal: 15),
      ),
    ],
  ).marginOnly(left: _kContentHSubMargin);
}

// ignore: non_constant_identifier_names
Widget _SubLabeledWidget(BuildContext context, String label, Widget child,
    {bool enabled = true}) {
  return Row(
    children: [
      Text(
        '${translate(label)}: ',
        style: TextStyle(color: disabledTextColor(context, enabled)),
      ),
      SizedBox(
        width: 10,
      ),
      child,
    ],
  ).marginOnly(left: _kContentHSubMargin);
}

Widget _lock(
  bool locked,
  String label,
  Function() onUnlock,
) {
  return Offstage(
      offstage: !locked,
      child: Row(
        children: [
          Flexible(
            child: SizedBox(
              width: _kCardFixedWidth,
              child: Card(
                child: ElevatedButton(
                  child: SizedBox(
                      height: 25,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.security_sharp,
                              size: 20,
                            ),
                            Text(translate(label)).marginOnly(left: 5),
                          ]).marginSymmetric(vertical: 2)),
                  onPressed: () async {
                    final unlockPin = bind.mainGetUnlockPin();
                    if (unlockPin.isEmpty || isUnlockPinDisabled()) {
                      bool checked = await callMainCheckSuperUserPermission();
                      if (checked) {
                        onUnlock();
                      }
                    } else {
                      checkUnlockPinDialog(unlockPin, onUnlock);
                    }
                  },
                ).marginSymmetric(horizontal: 2, vertical: 4),
              ).marginOnly(left: _kCardLeftMargin),
            ).marginOnly(top: 10),
          ),
        ],
      ));
}

_LabeledTextField(
    BuildContext context,
    String label,
    TextEditingController controller,
    String errorText,
    bool enabled,
    bool secure) {
  return Table(
    columnWidths: const {
      0: FixedColumnWidth(150),
      1: FlexColumnWidth(),
    },
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    children: [
      TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              '${translate(label)}:',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                color: disabledTextColor(context, enabled),
              ),
            ),
          ),
          TextField(
            controller: controller,
            enabled: enabled,
            obscureText: secure,
            autocorrect: false,
            decoration: InputDecoration(
              errorText: errorText.isNotEmpty ? errorText : null,
            ),
            style: TextStyle(
              color: disabledTextColor(context, enabled),
            ),
          ).workaroundFreezeLinuxMint(),
        ],
      ),
    ],
  ).marginOnly(bottom: 8);
}

class _CountDownButton extends StatefulWidget {
  _CountDownButton({
    Key? key,
    required this.text,
    required this.second,
    required this.onPressed,
  }) : super(key: key);
  final String text;
  final VoidCallback? onPressed;
  final int second;

  @override
  State<_CountDownButton> createState() => _CountDownButtonState();
}

class _CountDownButtonState extends State<_CountDownButton> {
  bool _isButtonDisabled = false;

  late int _countdownSeconds = widget.second;

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_countdownSeconds <= 0) {
        setState(() {
          _isButtonDisabled = false;
        });
        timer.cancel();
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isButtonDisabled
          ? null
          : () {
              widget.onPressed?.call();
              setState(() {
                _isButtonDisabled = true;
                _countdownSeconds = widget.second;
              });
              _startCountdownTimer();
            },
      child: Text(
        _isButtonDisabled ? '$_countdownSeconds s' : translate(widget.text),
      ),
    );
  }
}

//#endregion

//#region dialogs

void changeSocks5Proxy() async {
  var socks = await bind.mainGetSocks();

  String proxy = '';
  String proxyMsg = '';
  String username = '';
  String password = '';
  if (socks.length == 3) {
    proxy = socks[0];
    username = socks[1];
    password = socks[2];
  }
  var proxyController = TextEditingController(text: proxy);
  var userController = TextEditingController(text: username);
  var pwdController = TextEditingController(text: password);
  RxBool obscure = true.obs;

  // proxy settings
  // The following option is a not real key, it is just used for custom client advanced settings.
  const String optionProxyUrl = "proxy-url";
  final isOptFixed = isOptionFixed(optionProxyUrl);

  var isInProgress = false;
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      setState(() {
        proxyMsg = '';
        isInProgress = true;
      });
      cancel() {
        setState(() {
          isInProgress = false;
        });
      }

      proxy = proxyController.text.trim();
      username = userController.text.trim();
      password = pwdController.text.trim();

      if (proxy.isNotEmpty) {
        String domainPort = proxy;
        if (domainPort.contains('://')) {
          domainPort = domainPort.split('://')[1];
        }
        proxyMsg = translate(await bind.mainTestIfValidServer(
            server: domainPort, testWithProxy: false));
        if (proxyMsg.isEmpty) {
          // ignore
        } else {
          cancel();
          return;
        }
      }
      await bind.mainSetSocks(
          proxy: proxy, username: username, password: password);
      close();
    }

    return CustomAlertDialog(
      title: Text(translate('Socks5/Http(s) Proxy')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 140),
                    child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          children: [
                            Text(
                              translate('Server'),
                            ).marginOnly(right: 4),
                            Tooltip(
                              waitDuration: Duration(milliseconds: 0),
                              message: translate("default_proxy_tip"),
                              child: Icon(
                                Icons.help_outline_outlined,
                                size: 16,
                                color: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.color
                                    ?.withOpacity(0.5),
                              ),
                            ),
                          ],
                        )).marginOnly(right: 10),
                  ),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      errorText: proxyMsg.isNotEmpty ? proxyMsg : null,
                      labelText: isMobile ? translate('Server') : null,
                      helperText:
                          isMobile ? translate("default_proxy_tip") : null,
                      helperMaxLines: isMobile ? 3 : null,
                    ),
                    controller: proxyController,
                    autofocus: true,
                    enabled: !isOptFixed,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ).marginOnly(bottom: 8),
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 140),
                      child: Text(
                        '${translate("Username")}:',
                        textAlign: TextAlign.right,
                      ).marginOnly(right: 10)),
                Expanded(
                  child: TextField(
                    controller: userController,
                    decoration: InputDecoration(
                      labelText: isMobile ? translate('Username') : null,
                    ),
                    enabled: !isOptFixed,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ).marginOnly(bottom: 8),
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 140),
                      child: Text(
                        '${translate("Password")}:',
                        textAlign: TextAlign.right,
                      ).marginOnly(right: 10)),
                Expanded(
                  child: Obx(() => TextField(
                        obscureText: obscure.value,
                        decoration: InputDecoration(
                            labelText: isMobile ? translate('Password') : null,
                            suffixIcon: IconButton(
                                onPressed: () => obscure.value = !obscure.value,
                                icon: Icon(obscure.value
                                    ? Icons.visibility_off
                                    : Icons.visibility))),
                        controller: pwdController,
                        enabled: !isOptFixed,
                        maxLength: bind.mainMaxEncryptLen(),
                      ).workaroundFreezeLinuxMint()),
                ),
              ],
            ),
            // NOT use Offstage to wrap LinearProgressIndicator
            if (isInProgress)
              const LinearProgressIndicator().marginOnly(top: 8),
          ],
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        if (!isOptFixed) dialogButton('OK', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

//#endregion