import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/app_auth_service.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/login.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../widgets/dialog.dart';
import 'app_login_page.dart';
import 'home_page.dart';
import 'scan_page.dart';

class SettingsPage extends StatefulWidget implements PageShape {
  @override
  final title = translate("Settings");

  @override
  final icon = Icon(Icons.settings);

  @override
  final appBarActions = bind.isDisableSettings() ? [] : [ScanButton()];

  @override
  State<SettingsPage> createState() => _SettingsState();
}

const url = 'https://jygamwing.com/';

enum KeepScreenOn {
  never,
  duringControlled,
  serviceOn,
}

String _keepScreenOnToOption(KeepScreenOn value) {
  switch (value) {
    case KeepScreenOn.never:
      return 'never';
    case KeepScreenOn.duringControlled:
      return 'during-controlled';
    case KeepScreenOn.serviceOn:
      return 'service-on';
  }
}

KeepScreenOn optionToKeepScreenOn(String value) {
  switch (value) {
    case 'never':
      return KeepScreenOn.never;
    case 'service-on':
      return KeepScreenOn.serviceOn;
    default:
      return KeepScreenOn.duringControlled;
  }
}

class _SettingsState extends State<SettingsPage> with WidgetsBindingObserver {
  final _hasIgnoreBattery =
      false; //androidVersion >= 26; // remove because not work on every device
  var _ignoreBatteryOpt = false;
  var _enableStartOnBoot = false;
  var _checkUpdateOnStartup = false;
  var _showTerminalExtraKeys = false;
  var _floatingWindowDisabled = false;
  var _keepScreenOn = KeepScreenOn.duringControlled; // relay on floating window
  var _enableAbr = false;
  var _denyLANDiscovery = false;
  var _onlyWhiteList = false;
  var _enableDirectIPAccess = false;
  var _enableRecordSession = false;
  var _enableHardwareCodec = false;
  var _allowWebSocket = false;
  var _autoRecordIncomingSession = false;
  var _autoRecordOutgoingSession = false;
  var _allowAutoDisconnect = false;
  var _localIP = "";
  var _directAccessPort = "";
  var _fingerprint = "";
  var _buildDate = "";
  var _autoDisconnectTimeout = "";
  var _hideServer = false;
  var _hideProxy = false;
  var _hideNetwork = false;
  var _hideWebSocket = true;
  var _enableTrustedDevices = false;
  var _enableUdpPunch = true;
  var _allowInsecureTlsFallback = false;
  var _disableUdp = false;
  var _enableIpv6Punch = true;
  var _isUsingPublicServer = false;
  var _allowAskForNoteAtEndOfConnection = false;
  var _preventSleepWhileConnected = true;
  var _appLoggedIn = false;
  var _loginStatusDialogShowing = false;
  var _deviceModel = '';
  var _memoryUsage = '';

  _SettingsState() {
    _enableAbr = option2bool(
        kOptionEnableAbr, bind.mainGetOptionSync(key: kOptionEnableAbr));
    _denyLANDiscovery = !option2bool(kOptionEnableLanDiscovery,
        bind.mainGetOptionSync(key: kOptionEnableLanDiscovery));
    _onlyWhiteList = whitelistNotEmpty();
    _enableDirectIPAccess = option2bool(
        kOptionDirectServer, bind.mainGetOptionSync(key: kOptionDirectServer));
    _enableRecordSession = option2bool(kOptionEnableRecordSession,
        bind.mainGetOptionSync(key: kOptionEnableRecordSession));
    _enableHardwareCodec = option2bool(kOptionEnableHwcodec,
        bind.mainGetOptionSync(key: kOptionEnableHwcodec));
    _allowWebSocket = mainGetBoolOptionSync(kOptionAllowWebSocket);
    _allowInsecureTlsFallback =
        mainGetBoolOptionSync(kOptionAllowInsecureTLSFallback);
    _disableUdp = bind.mainGetOptionSync(key: kOptionDisableUdp) == 'Y';
    _autoRecordIncomingSession = option2bool(kOptionAllowAutoRecordIncoming,
        bind.mainGetOptionSync(key: kOptionAllowAutoRecordIncoming));
    _autoRecordOutgoingSession = option2bool(kOptionAllowAutoRecordOutgoing,
        bind.mainGetLocalOption(key: kOptionAllowAutoRecordOutgoing));
    _localIP = bind.mainGetOptionSync(key: 'local-ip-addr');
    _directAccessPort = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    _allowAutoDisconnect = option2bool(kOptionAllowAutoDisconnect,
        bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect));
    _autoDisconnectTimeout =
        bind.mainGetOptionSync(key: kOptionAutoDisconnectTimeout);
    _hideServer =
        bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
    _hideProxy = bind.mainGetBuildinOption(key: kOptionHideProxySetting) == 'Y';
    _hideNetwork =
        bind.mainGetBuildinOption(key: kOptionHideNetworkSetting) == 'Y';
    _hideWebSocket =
        bind.mainGetBuildinOption(key: kOptionHideWebSocketSetting) == 'Y' ||
            isWeb;
    _enableTrustedDevices = mainGetBoolOptionSync(kOptionEnableTrustedDevices);
    _enableUdpPunch = mainGetLocalBoolOptionSync(kOptionEnableUdpPunch);
    _enableIpv6Punch = mainGetLocalBoolOptionSync(kOptionEnableIpv6Punch);
    _allowAskForNoteAtEndOfConnection =
        mainGetLocalBoolOptionSync(kOptionAllowAskForNoteAtEndOfConnection);
    _preventSleepWhileConnected =
        mainGetLocalBoolOptionSync(kOptionKeepAwakeDuringOutgoingSessions);
    _showTerminalExtraKeys =
        mainGetLocalBoolOptionSync(kOptionEnableShowTerminalExtraKeys);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAppLoginStatus();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var update = false;

      if (_hasIgnoreBattery) {
        if (await checkAndUpdateIgnoreBatteryStatus()) {
          update = true;
        }
      }

      if (await checkAndUpdateStartOnBoot()) {
        update = true;
      }

      // start on boot depends on ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS and SYSTEM_ALERT_WINDOW
      var enableStartOnBoot =
          await gFFI.invokeMethod(AndroidChannel.kGetStartOnBootOpt);
      if (enableStartOnBoot) {
        if (!await canStartOnBoot()) {
          enableStartOnBoot = false;
          gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
        }
      }

      if (enableStartOnBoot != _enableStartOnBoot) {
        update = true;
        _enableStartOnBoot = enableStartOnBoot;
      }

      var checkUpdateOnStartup =
          mainGetLocalBoolOptionSync(kOptionEnableCheckUpdate);
      if (checkUpdateOnStartup != _checkUpdateOnStartup) {
        update = true;
        _checkUpdateOnStartup = checkUpdateOnStartup;
      }

      var floatingWindowDisabled =
          bind.mainGetLocalOption(key: kOptionDisableFloatingWindow) == "Y" ||
              !await AndroidPermissionManager.check(kSystemAlertWindow);
      if (floatingWindowDisabled != _floatingWindowDisabled) {
        update = true;
        _floatingWindowDisabled = floatingWindowDisabled;
      }

      final keepScreenOn = _floatingWindowDisabled
          ? KeepScreenOn.never
          : optionToKeepScreenOn(
              bind.mainGetLocalOption(key: kOptionKeepScreenOn));
      if (keepScreenOn != _keepScreenOn) {
        update = true;
        _keepScreenOn = keepScreenOn;
      }

      final fingerprint = await bind.mainGetFingerprint();
      if (_fingerprint != fingerprint) {
        update = true;
        _fingerprint = fingerprint;
      }

      final buildDate = await bind.mainGetBuildDate();
      if (_buildDate != buildDate) {
        update = true;
        _buildDate = buildDate;
      }

      // Fetch device model
      try {
        final deviceInfo = DeviceInfoPlugin();
        String model = '';
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          model = '${androidInfo.brand} ${androidInfo.model}';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          model = iosInfo.utsname.machine;
        } else if (Platform.isWindows) {
          final winInfo = await deviceInfo.windowsInfo;
          model = winInfo.computerName;
        } else if (Platform.isMacOS) {
          final macInfo = await deviceInfo.macOsInfo;
          model = macInfo.model;
        } else if (Platform.isLinux) {
          final linuxInfo = await deviceInfo.linuxInfo;
          model = linuxInfo.prettyName;
        }
        if (model != _deviceModel) {
          update = true;
          _deviceModel = model;
        }
      } catch (e) {
        debugPrint('Failed to get device info: $e');
      }

      // Fetch memory usage
      try {
        final rss = ProcessInfo.currentRss;
        final rssInMB = (rss / (1024 * 1024)).toStringAsFixed(1);
        final memStr = '$rssInMB MB';
        if (memStr != _memoryUsage) {
          update = true;
          _memoryUsage = memStr;
        }
      } catch (e) {
        debugPrint('Failed to get memory info: $e');
      }

      final isUsingPublicServer = await bind.mainIsUsingPublicServer();
      if (_isUsingPublicServer != isUsingPublicServer) {
        update = true;
        _isUsingPublicServer = isUsingPublicServer;
      }

      if (update) {
        setState(() {});
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
      _refreshAppLoginStatus();
      () async {
        final ibs = await checkAndUpdateIgnoreBatteryStatus();
        final sob = await checkAndUpdateStartOnBoot();
        if (ibs || sob) {
          setState(() {});
        }
      }();
    }
  }

  Future<bool> checkAndUpdateIgnoreBatteryStatus() async {
    final res = await AndroidPermissionManager.check(
        kRequestIgnoreBatteryOptimizations);
    if (_ignoreBatteryOpt != res) {
      _ignoreBatteryOpt = res;
      return true;
    } else {
      return false;
    }
  }

  Future<bool> checkAndUpdateStartOnBoot() async {
    if (!await canStartOnBoot() && _enableStartOnBoot) {
      _enableStartOnBoot = false;
      debugPrint(
          "checkAndUpdateStartOnBoot and set _enableStartOnBoot -> false");
      gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
      return true;
    } else {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    final outgoingOnly = bind.isOutgoingOnly();
    final incomingOnly = bind.isIncomingOnly();
    final customClientSection = Column(
      children: [
        if (bind.isCustomClient())
          Align(
            alignment: Alignment.center,
            child: loadPowered(context),
          ),
        Align(
          alignment: Alignment.center,
          child: loadLogo(),
        )
      ],
    );
    final List<Widget> enhancementsTiles = [];
    final enable2fa = bind.mainHasValid2FaSync();
    // ignore: unused_local_variable
    final List<Widget> tfaTiles = [
      _cardSwitchRow(
        title: Text(translate('enable-2fa-title')),
        value: enable2fa,
        onChanged: (v) async {
          update() async {
            setState(() {});
          }

          if (v == false) {
            CommonConfirmDialog(
                gFFI.dialogManager, translate('cancel-2fa-confirm-tip'), () {
              change2fa(callback: update);
            });
          } else {
            change2fa(callback: update);
          }
        },
      ),
      if (enable2fa)
        _cardSwitchRow(
          title: Text(translate('Telegram bot')),
          value: bind.mainHasValidBotSync(),
          onChanged: (v) async {
            update() async {
              setState(() {});
            }

            if (v == false) {
              CommonConfirmDialog(
                  gFFI.dialogManager, translate('cancel-bot-confirm-tip'), () {
                changeBot(callback: update);
              });
            } else {
              changeBot(callback: update);
            }
          },
        ),
      if (enable2fa)
        _cardSwitchRow(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('Enable trusted devices')),
              Text('* ${translate('enable-trusted-devices-tip')}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          value: _enableTrustedDevices,
          onChanged: isOptionFixed(kOptionEnableTrustedDevices)
              ? null
              : (v) async {
                  mainSetBoolOption(kOptionEnableTrustedDevices, v);
                  setState(() {
                    _enableTrustedDevices = v;
                  });
                },
        ),
      if (enable2fa && _enableTrustedDevices)
        _cardNavRow(
            title: Text(translate('Manage trusted devices')),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return _ManageTrustedDevices();
              }));
            })
    ];
    final List<Widget> shareScreenTiles = [
      _cardSwitchRow(
        title: Text(translate('Deny LAN discovery')),
        value: _denyLANDiscovery,
        onChanged: isOptionFixed(kOptionEnableLanDiscovery)
            ? null
            : (v) async {
                await bind.mainSetOption(
                    key: kOptionEnableLanDiscovery,
                    value: bool2option(kOptionEnableLanDiscovery, !v));
                final newValue = !option2bool(kOptionEnableLanDiscovery,
                    await bind.mainGetOption(key: kOptionEnableLanDiscovery));
                setState(() {
                  _denyLANDiscovery = newValue;
                });
              },
      ),
      _cardSwitchRow(
        title: Row(children: [
          Expanded(child: Text(translate('Use IP Whitelisting'))),
          Offstage(
                  offstage: !_onlyWhiteList,
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Color.fromARGB(255, 255, 204, 0)))
              .marginOnly(left: 5)
        ]),
        value: _onlyWhiteList,
        onChanged: (_) async {
          update() async {
            final onlyWhiteList = whitelistNotEmpty();
            if (onlyWhiteList != _onlyWhiteList) {
              setState(() {
                _onlyWhiteList = onlyWhiteList;
              });
            }
          }

          changeWhiteList(callback: update);
        },
      ),
      _cardSwitchRow(
        title: Text(translate('Adaptive bitrate')),
        value: _enableAbr,
        onChanged: isOptionFixed(kOptionEnableAbr)
            ? null
            : (v) async {
                await mainSetBoolOption(kOptionEnableAbr, v);
                final newValue = await mainGetBoolOption(kOptionEnableAbr);
                setState(() {
                  _enableAbr = newValue;
                });
              },
      ),
      _cardSwitchRow(
        title: Text(translate('Enable recording session')),
        value: _enableRecordSession,
        onChanged: isOptionFixed(kOptionEnableRecordSession)
            ? null
            : (v) async {
                await mainSetBoolOption(kOptionEnableRecordSession, v);
                final newValue =
                    await mainGetBoolOption(kOptionEnableRecordSession);
                setState(() {
                  _enableRecordSession = newValue;
                });
              },
      ),

      _cardSwitchRow(
        title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(translate("auto_disconnect_option_tip")),
                    Offstage(
                        offstage: !_allowAutoDisconnect,
                        child: Text(
                          '${_autoDisconnectTimeout.isEmpty ? '10' : _autoDisconnectTimeout} min',
                          style: Theme.of(context).textTheme.bodySmall,
                        )),
                  ])),
              Offstage(
                  offstage: !_allowAutoDisconnect,
                  child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.edit,
                        size: 20,
                      ),
                      onPressed: isOptionFixed(kOptionAutoDisconnectTimeout)
                          ? null
                          : () async {
                              final timeout = await changeAutoDisconnectTimeout(
                                  _autoDisconnectTimeout);
                              setState(() {
                                _autoDisconnectTimeout = timeout;
                              });
                            }))
            ]),
        value: _allowAutoDisconnect,
        onChanged: isOptionFixed(kOptionAllowAutoDisconnect)
            ? null
            : (_) async {
                _allowAutoDisconnect = !_allowAutoDisconnect;
                String value = bool2option(
                    kOptionAllowAutoDisconnect, _allowAutoDisconnect);
                await bind.mainSetOption(
                    key: kOptionAllowAutoDisconnect, value: value);
                setState(() {});
              },
      )
    ];
    if (_hasIgnoreBattery) {
      enhancementsTiles.insert(
          0,
          _cardSwitchRow(
              value: _ignoreBatteryOpt,
              title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(translate('Keep RustDesk background service')),
                    Text('* ${translate('Ignore Battery Optimizations')}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
              onChanged: (v) async {
                if (v) {
                  await AndroidPermissionManager.request(
                      kRequestIgnoreBatteryOptimizations);
                } else {
                  final res = await gFFI.dialogManager.show<bool>(
                      (setState, close, context) => CustomAlertDialog(
                            title: Text(translate("Open System Setting")),
                            content: Text(translate(
                                "android_open_battery_optimizations_tip")),
                            actions: [
                              dialogButton("Cancel",
                                  onPressed: () => close(), isOutline: true),
                              dialogButton(
                                "Open System Setting",
                                onPressed: () => close(true),
                              ),
                            ],
                          ));
                  if (res == true) {
                    AndroidPermissionManager.startAction(
                        kActionApplicationDetailsSettings);
                  }
                }
              }));
    }
    enhancementsTiles.add(_cardSwitchRow(
        value: _enableStartOnBoot,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(translate('Start on boot')),
          Text(
              '* ${translate('Start the screen sharing service on boot, requires special permissions')}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        onChanged: (toValue) async {
          if (toValue) {
            // 1. request kIgnoreBatteryOptimizations
            if (!await AndroidPermissionManager.check(
                kRequestIgnoreBatteryOptimizations)) {
              if (!await AndroidPermissionManager.request(
                  kRequestIgnoreBatteryOptimizations)) {
                return;
              }
            }

            // 2. request kSystemAlertWindow
            if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
              if (!await AndroidPermissionManager.request(kSystemAlertWindow)) {
                return;
              }
            }

            // (Optional) 3. request input permission
          }
          setState(() => _enableStartOnBoot = toValue);

          gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, toValue);
        }));

    if (!bind.isCustomClient()) {
      enhancementsTiles.add(
        _cardSwitchRow(
          value: _checkUpdateOnStartup,
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(translate('Check for software update on startup')),
          ]),
          onChanged: (bool toValue) async {
            await mainSetLocalBoolOption(kOptionEnableCheckUpdate, toValue);
            setState(() => _checkUpdateOnStartup = toValue);
          },
        ),
      );
    }



    onFloatingWindowChanged(bool toValue) async {
      if (toValue) {
        if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
          if (!await AndroidPermissionManager.request(kSystemAlertWindow)) {
            return;
          }
        }
      }
      final disable = !toValue;
      bind.mainSetLocalOption(
          key: kOptionDisableFloatingWindow,
          value: disable ? 'Y' : defaultOptionNo);
      setState(() => _floatingWindowDisabled = disable);
      gFFI.serverModel.androidUpdatekeepScreenOn();
    }

    enhancementsTiles.add(_cardSwitchRow(
        value: !_floatingWindowDisabled,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(translate('Floating window')),
          Text('* ${translate('floating_window_tip')}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        onChanged: bind.mainIsOptionFixed(key: kOptionDisableFloatingWindow)
            ? null
            : onFloatingWindowChanged));

    enhancementsTiles.add(_getPopupDialogRadioEntry(
      title: 'Keep screen on',
      list: [
        _RadioEntry('Never', _keepScreenOnToOption(KeepScreenOn.never)),
        _RadioEntry('During controlled',
            _keepScreenOnToOption(KeepScreenOn.duringControlled)),
        _RadioEntry('During service is on',
            _keepScreenOnToOption(KeepScreenOn.serviceOn)),
      ],
      getter: () => _keepScreenOnToOption(_floatingWindowDisabled
          ? KeepScreenOn.never
          : optionToKeepScreenOn(
              bind.mainGetLocalOption(key: kOptionKeepScreenOn))),
      asyncSetter: isOptionFixed(kOptionKeepScreenOn) || _floatingWindowDisabled
          ? null
          : (value) async {
              await bind.mainSetLocalOption(
                  key: kOptionKeepScreenOn, value: value);
              setState(() => _keepScreenOn = optionToKeepScreenOn(value));
              gFFI.serverModel.androidUpdatekeepScreenOn();
            },
    ));

    final disabledSettings = bind.isDisableSettings();
    final hideSecuritySettings =
        bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) == 'Y';
    final settings = Container(
      color: MyTheme.pageBg,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          customClientSection,
          if (_appLoggedIn)
            _settingCard(
              icon: Icons.person_outline,
              title: 'Account',
              children: [
                _cardNavRow(
                  leading: Icons.logout,
                  title: Text(translate('Sign out of your account')),
                  onTap: () {
                    _confirmLogout();
                  },
                ),
              ],
            ),
          // 隐藏账户登录入口
          // if (!bind.isDisableAccount())
          //   SettingsSection(
          //     title: Text(translate('Account')),
          //     tiles: [
          //       SettingsTile(
          //         title: Obx(() => Text(gFFI.userModel.userName.value.isEmpty
          //             ? translate('Login')
          //             : '${translate('Logout')} (${gFFI.userModel.accountLabelWithHandle})')),
          //         leading: Icon(Icons.person),
          //         onPressed: (context) {
          //           if (gFFI.userModel.userName.value.isEmpty) {
          //             loginDialog();
          //           } else {
          //             logOutConfirmDialog();
          //           }
          //         },
          //       ),
          //     ],
          //   ),
          _settingCard(
              icon: Icons.settings_outlined,
              title: 'Settings',
              children: [
                if (!kAppModeShareOnly &&
                    !disabledSettings &&
                    !_hideNetwork &&
                    !_hideServer &&
                    false)
                  _cardNavRow(
                      leading: Icons.cloud,
                      title: Text(translate('ID/Relay Server')),
                      onTap: () {
                        showServerSettings(gFFI.dialogManager,
                            (callback) async {
                          _isUsingPublicServer =
                              await bind.mainIsUsingPublicServer();
                          setState(callback);
                        });
                      }),
                if (!kAppModeShareOnly && !_hideNetwork && !_hideProxy && false)
                  _cardNavRow(
                      leading: Icons.network_ping,
                      title: Text(translate('Socks5/Http(s) Proxy')),
                      onTap: () {
                        changeSocks5Proxy();
                      }),
                if (!disabledSettings &&
                    !_hideNetwork &&
                    !_hideWebSocket &&
                    false)
                  _cardSwitchRow(
                    title: Text(translate('Use WebSocket')),
                    value: _allowWebSocket,
                    onChanged: isOptionFixed(kOptionAllowWebSocket)
                        ? null
                        : (v) async {
                            await mainSetBoolOption(kOptionAllowWebSocket, v);
                            final newValue =
                                await mainGetBoolOption(kOptionAllowWebSocket);
                            setState(() {
                              _allowWebSocket = newValue;
                            });
                          },
                  ),
                if (!_isUsingPublicServer)
                  _cardSwitchRow(
                    title: Text(translate('Allow insecure TLS fallback')),
                    value: _allowInsecureTlsFallback,
                    onChanged: isOptionFixed(kOptionAllowInsecureTLSFallback)
                        ? null
                        : (v) async {
                            await mainSetBoolOption(
                                kOptionAllowInsecureTLSFallback, v);
                            final newValue = mainGetBoolOptionSync(
                                kOptionAllowInsecureTLSFallback);
                            setState(() {
                              _allowInsecureTlsFallback = newValue;
                            });
                          },
                  ),
                if (isAndroid && !outgoingOnly && !_isUsingPublicServer)
                  _cardSwitchRow(
                    title: Text(translate('Disable UDP')),
                    value: _disableUdp,
                    onChanged: isOptionFixed(kOptionDisableUdp)
                        ? null
                        : (v) async {
                            await bind.mainSetOption(
                                key: kOptionDisableUdp, value: v ? 'Y' : 'N');
                            final newValue =
                                bind.mainGetOptionSync(key: kOptionDisableUdp) ==
                                    'Y';
                            setState(() {
                              _disableUdp = newValue;
                            });
                          },
                  ),
                if (!incomingOnly)
                  _cardSwitchRow(
                    title: Text(translate('Enable UDP hole punching')),
                    value: _enableUdpPunch,
                    onChanged: (v) async {
                      await mainSetLocalBoolOption(kOptionEnableUdpPunch, v);
                      final newValue =
                          mainGetLocalBoolOptionSync(kOptionEnableUdpPunch);
                      setState(() {
                        _enableUdpPunch = newValue;
                      });
                    },
                  ),
                if (!incomingOnly)
                  _cardSwitchRow(
                    title: Text(translate('Enable IPv6 P2P connection')),
                    value: _enableIpv6Punch,
                    onChanged: (v) async {
                      await mainSetLocalBoolOption(kOptionEnableIpv6Punch, v);
                      final newValue =
                          mainGetLocalBoolOptionSync(kOptionEnableIpv6Punch);
                      setState(() {
                        _enableIpv6Punch = newValue;
                      });
                    },
                  ),
                _cardNavRow(
                    leading: Icons.translate,
                    title: Text(translate('Language')),
                    onTap: () {
                      showLanguageSettings(gFFI.dialogManager);
                    }),
                _cardNavRow(
                  leading: Theme.of(context).brightness == Brightness.light
                      ? Icons.dark_mode
                      : Icons.light_mode,
                  title: Text(translate(
                      Theme.of(context).brightness == Brightness.light
                          ? 'Light Theme'
                          : 'Dark Theme')),
                  onTap: () {
                    showThemeSettings(gFFI.dialogManager);
                  },
                ),
                // 隐藏账户相关设置
                // if (!bind.isDisableAccount())
                //   SettingsTile.switchTile(
                //     title: Text(translate('note-at-conn-end-tip')),
                //     initialValue: _allowAskForNoteAtEndOfConnection,
                //     onToggle: (v) async {
                //       if (v && !gFFI.userModel.isLogin) {
                //         final res = await loginDialog();
                //         if (res != true) return;
                //       }
                //       await mainSetLocalBoolOption(
                //           kOptionAllowAskForNoteAtEndOfConnection, v);
                //       final newValue = mainGetLocalBoolOptionSync(
                //           kOptionAllowAskForNoteAtEndOfConnection);
                //       setState(() {
                //         _allowAskForNoteAtEndOfConnection = newValue;
                //       });
                //     },
                //   ),
                if (!incomingOnly)
                  _cardSwitchRow(
                    title: Text(
                        translate('keep-awake-during-outgoing-sessions-label')),
                    value: _preventSleepWhileConnected,
                    onChanged: (v) async {
                      await mainSetLocalBoolOption(
                          kOptionKeepAwakeDuringOutgoingSessions, v);
                      setState(() {
                        _preventSleepWhileConnected = v;
                      });
                    },
                  ),
              ]),
          if (isAndroid)
            _settingCard(
                icon: Icons.memory,
                iconColor: const Color(0xFF8B5CF6),
                title: 'Hardware Codec',
                children: [
                  _cardSwitchRow(
                    title: Text(translate('Enable hardware codec')),
                    value: _enableHardwareCodec,
                    onChanged: isOptionFixed(kOptionEnableHwcodec)
                        ? null
                        : (v) async {
                            await mainSetBoolOption(kOptionEnableHwcodec, v);
                            final newValue =
                                await mainGetBoolOption(kOptionEnableHwcodec);
                            setState(() {
                              _enableHardwareCodec = newValue;
                            });
                          },
                  ),
                ]),
          if (isAndroid)
            _settingCard(
              icon: Icons.videocam_outlined,
              iconColor: const Color(0xFFF59E0B),
              title: 'Recording',
              children: [
                if (!outgoingOnly)
                  _cardSwitchRow(
                    title: Text(
                        translate('Automatically record incoming sessions')),
                    value: _autoRecordIncomingSession,
                    onChanged: isOptionFixed(kOptionAllowAutoRecordIncoming)
                        ? null
                        : (v) async {
                            await bind.mainSetOption(
                                key: kOptionAllowAutoRecordIncoming,
                                value: bool2option(
                                    kOptionAllowAutoRecordIncoming, v));
                            final newValue = option2bool(
                                kOptionAllowAutoRecordIncoming,
                                await bind.mainGetOption(
                                    key: kOptionAllowAutoRecordIncoming));
                            setState(() {
                              _autoRecordIncomingSession = newValue;
                            });
                          },
                  ),
                if (!incomingOnly)
                  _cardSwitchRow(
                    title: Text(
                        translate('Automatically record outgoing sessions')),
                    value: _autoRecordOutgoingSession,
                    onChanged: isOptionFixed(kOptionAllowAutoRecordOutgoing)
                        ? null
                        : (v) async {
                            await bind.mainSetLocalOption(
                                key: kOptionAllowAutoRecordOutgoing,
                                value: bool2option(
                                    kOptionAllowAutoRecordOutgoing, v));
                            final newValue = option2bool(
                                kOptionAllowAutoRecordOutgoing,
                                bind.mainGetLocalOption(
                                    key: kOptionAllowAutoRecordOutgoing));
                            setState(() {
                              _autoRecordOutgoingSession = newValue;
                            });
                          },
                  ),
                _cardNavRow(
                  title: Text(translate("Directory")),
                  description: Text(bind.mainVideoSaveDirectory(root: false)),
                ),
              ],
            ),
          if (!kAppModeShareOnly &&
              isAndroid &&
              !disabledSettings &&
              !outgoingOnly &&
              !hideSecuritySettings)
            if (isAndroid &&
                !disabledSettings &&
                !outgoingOnly &&
                !hideSecuritySettings)
              _settingCard(
                icon: Icons.screen_share_outlined,
                iconColor: const Color(0xFF22C55E),
                title: 'Share screen',
                children: shareScreenTiles,
              ),
          if (!kAppModeShareOnly && !bind.isIncomingOnly())
            defaultDisplaySection(),
          if (isAndroid &&
              !disabledSettings &&
              !outgoingOnly &&
              !hideSecuritySettings)
            _settingCard(
              icon: Icons.auto_awesome_outlined,
              title: 'Enhancements',
              children: enhancementsTiles,
            ),
          _settingCard(
            icon: Icons.info_outline,
            title: 'About',
            children: [
              _cardNavRow(
                  leading: Icons.info,
                  title: Text('${translate("Version")}: $version')),
              _cardNavRow(
                  leading: Icons.query_builder,
                  title: Text(translate("Build Date")),
                  valueWidget: Text(_buildDate)),
              _cardNavRow(
                leading: Icons.description,
                title: Text(translate("Terms of Service")),
                onTap: () async {
                  await launchUrl(Uri.parse(kTermsOfServiceUrl),
                      mode: LaunchMode.externalApplication);
                },
              ),
              _cardNavRow(
                leading: Icons.privacy_tip,
                title: Text(translate("Privacy Statement")),
                onTap: () async {
                  await launchUrl(Uri.parse(kPrivacyPolicyUrl),
                      mode: LaunchMode.externalApplication);
                },
              ),
              _cardNavRow(
                leading: Icons.language,
                title: Text(translate("Website")),
                onTap: () async {
                  await launchUrl(Uri.parse(url));
                },
              )
            ],
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.only(top: 18, bottom: 8),
              child: Column(
                children: [
                  if (_deviceModel.isNotEmpty || _memoryUsage.isNotEmpty)
                    Text(
                      [
                        if (_deviceModel.isNotEmpty) _deviceModel,
                        if (_memoryUsage.isNotEmpty)
                          '${translate("Memory")} $_memoryUsage',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                  SizedBox(height: 2),
                  Text(
                    translate('Copyright Notice')
                        .split('\n')
                        .last
                        .replaceAll('，', ' · '),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return settings;
  }

  Future<void> _refreshAppLoginStatus() async {
    if (kAppModeShareOnly) return;
    final auth = AppAuthService();
    final cachedToken = await auth.getToken();
    final hasCachedLogin = cachedToken.isNotEmpty;
    if (mounted && _appLoggedIn != hasCachedLogin) {
      setState(() => _appLoggedIn = hasCachedLogin);
    }
    final loggedIn = await auth.isLoggedIn();
    if (!mounted) return;
    if (_appLoggedIn != loggedIn) {
      setState(() => _appLoggedIn = loggedIn);
    }
    if (hasCachedLogin && !loggedIn) {
      await _showLoginExpiredDialog();
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(translate('Sign out of your account')),
        content: Text(translate('confirm_to_logout')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(translate('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(translate('OK')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (mounted && _appLoggedIn) {
      setState(() => _appLoggedIn = false);
    }
    unawaited(AppAuthService().logout());
    if (!mounted) return;
    _redirectToLogin();
  }

  void _redirectToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppLoginPage()),
      (route) => false,
    );
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
          title: Text(translate('account_abnormal_title')),
          content: Text(translate('account_kicked_message')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                SystemNavigator.pop();
              },
              child: Text(translate('btn_exit_directly')),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _redirectToLogin();
              },
              child: Text(translate('btn_relogin')),
            ),
          ],
        ),
      ),
    );
    if (mounted) {
      _loginStatusDialogShowing = false;
    }
  }

  Future<bool> canStartOnBoot() async {
    // start on boot depends on ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS and SYSTEM_ALERT_WINDOW
    if (_hasIgnoreBattery && !_ignoreBatteryOpt) {
      return false;
    }
    if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
      return false;
    }
    return true;
  }

  defaultDisplaySection() {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return _DisplayPage();
        }));
      },
      child: _settingCard(
        icon: Icons.desktop_windows_outlined,
        iconColor: const Color(0xFF3B82F6),
        title: 'Display Settings',
        trailing:
            Icon(Icons.arrow_forward_ios, size: 14, color: MyTheme.iconFaint),
      ),
    );
  }
}

void showLanguageSettings(OverlayDialogManager dialogManager) async {
  try {
    final langs = json.decode(await bind.mainGetLangs()) as List<dynamic>;
    var lang = bind.mainGetLocalOption(key: kCommConfKeyLang);
    dialogManager.show((setState, close, context) {
      setLang(v) async {
        if (lang != v) {
          setState(() {
            lang = v;
          });
          await bind.mainSetLocalOption(key: kCommConfKeyLang, value: v);
          HomePage.homeKey.currentState?.refreshPages();
          Future.delayed(Duration(milliseconds: 200), close);
        }
      }

      final isOptFixed = isOptionFixed(kCommConfKeyLang);
      return CustomAlertDialog(
        content: Column(
          children: [
                getRadio(Text(translate('Default')), defaultOptionLang, lang,
                    isOptFixed ? null : setLang),
                Divider(color: MyTheme.border),
              ] +
              langs.map((e) {
                final key = e[0] as String;
                final name = e[1] as String;
                return getRadio(Text(translate(name)), key, lang,
                    isOptFixed ? null : setLang);
              }).toList(),
        ),
      );
    }, backDismiss: true, clickMaskDismiss: true);
  } catch (e) {
    //
  }
}

void showThemeSettings(OverlayDialogManager dialogManager) async {
  var themeMode = MyTheme.getThemeModePreference();

  dialogManager.show((setState, close, context) {
    setTheme(v) {
      if (themeMode != v) {
        setState(() {
          themeMode = v;
        });
        MyTheme.changeDarkMode(themeMode);
        Future.delayed(Duration(milliseconds: 200), close);
      }
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    return CustomAlertDialog(
      content: Column(children: [
        getRadio(Text(translate('Light')), ThemeMode.light, themeMode,
            isOptFixed ? null : setTheme),
        getRadio(Text(translate('Dark')), ThemeMode.dark, themeMode,
            isOptFixed ? null : setTheme),
        getRadio(Text(translate('Follow System')), ThemeMode.system, themeMode,
            isOptFixed ? null : setTheme)
      ]),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}

void showAbout(OverlayDialogManager dialogManager) {
  dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('About RustDesk')),
      content: Wrap(direction: Axis.vertical, spacing: 12, children: [
        Text('Version: $version'),
        InkWell(
            onTap: () async {
              const url = 'https://jygamwing.com/';
              await launchUrl(Uri.parse(url));
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('jygamwing.com',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  )),
            )),
      ]),
      actions: [],
    );
  }, clickMaskDismiss: true, backDismiss: true);
}

class ScanButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.camera_alt),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (BuildContext context) => ScanPage(),
          ),
        );
      },
    );
  }
}

class _DisplayPage extends StatefulWidget {
  const _DisplayPage();

  @override
  State<_DisplayPage> createState() => __DisplayPageState();
}

class __DisplayPageState extends State<_DisplayPage> {
  @override
  Widget build(BuildContext context) {
    final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
    final h264 = codecsJson['h264'] ?? false;
    final h265 = codecsJson['h265'] ?? false;
    var codecList = [
      _RadioEntry('Auto', 'auto'),
      _RadioEntry('VP8', 'vp8'),
      _RadioEntry('VP9', 'vp9'),
      _RadioEntry('AV1', 'av1'),
      if (h264) _RadioEntry('H264', 'h264'),
      if (h265) _RadioEntry('H265', 'h265')
    ];
    RxBool showCustomImageQuality = false.obs;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios)),
        title: Text(translate('Display Settings')),
        centerTitle: true,
      ),
      body: Container(
        color: MyTheme.pageBg,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            _settingCard(
              children: [
                _getPopupDialogRadioEntry(
                  title: 'Default View Style',
                  list: [
                    _RadioEntry('Scale original', kRemoteViewStyleOriginal),
                    _RadioEntry('Scale adaptive', kRemoteViewStyleAdaptive)
                  ],
                  getter: () =>
                      bind.mainGetUserDefaultOption(key: kOptionViewStyle),
                  asyncSetter: isOptionFixed(kOptionViewStyle)
                      ? null
                      : (value) async {
                          await bind.mainSetUserDefaultOption(
                              key: kOptionViewStyle, value: value);
                        },
                ),
                _getPopupDialogRadioEntry(
                  title: 'Default Image Quality',
                  list: [
                    _RadioEntry('Good image quality', kRemoteImageQualityBest),
                    _RadioEntry('Balanced', kRemoteImageQualityBalanced),
                    _RadioEntry(
                        'Optimize reaction time', kRemoteImageQualityLow),
                    _RadioEntry('Custom', kRemoteImageQualityCustom),
                  ],
                  getter: () {
                    final v =
                        bind.mainGetUserDefaultOption(key: kOptionImageQuality);
                    showCustomImageQuality.value =
                        v == kRemoteImageQualityCustom;
                    return v;
                  },
                  asyncSetter: isOptionFixed(kOptionImageQuality)
                      ? null
                      : (value) async {
                          await bind.mainSetUserDefaultOption(
                              key: kOptionImageQuality, value: value);
                          showCustomImageQuality.value =
                              value == kRemoteImageQualityCustom;
                        },
                  tail: customImageQualitySetting(),
                  showTail: showCustomImageQuality,
                  notCloseValue: kRemoteImageQualityCustom,
                ),
                _getPopupDialogRadioEntry(
                  title: 'Default Codec',
                  list: codecList,
                  getter: () => bind.mainGetUserDefaultOption(
                      key: kOptionCodecPreference),
                  asyncSetter: isOptionFixed(kOptionCodecPreference)
                      ? null
                      : (value) async {
                          await bind.mainSetUserDefaultOption(
                              key: kOptionCodecPreference, value: value);
                        },
                ),
              ],
            ),
            _settingCard(
              icon: Icons.tune,
              title: 'Other Default Options',
              children: otherDefaultSettings()
                  .map((e) => otherRow(e.$1, e.$2))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget otherRow(String label, String key) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    final isOptFixed = isOptionFixed(key);
    return _cardSwitchRow(
      value: value,
      title: Text(translate(label)),
      onChanged: isOptFixed
          ? null
          : (b) async {
              await bind.mainSetUserDefaultOption(
                  key: key, value: b ? 'Y' : defaultOptionNo);
              setState(() {});
            },
    );
  }
}

class _ManageTrustedDevices extends StatefulWidget {
  const _ManageTrustedDevices();

  @override
  State<_ManageTrustedDevices> createState() => __ManageTrustedDevicesState();
}

class __ManageTrustedDevicesState extends State<_ManageTrustedDevices> {
  RxList<TrustedDevice> trustedDevices = RxList.empty(growable: true);
  RxList<Uint8List> selectedDevices = RxList.empty();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('Manage trusted devices')),
        centerTitle: true,
        actions: [
          Obx(() => IconButton(
              icon: Icon(Icons.delete, color: Colors.white),
              onPressed: selectedDevices.isEmpty
                  ? null
                  : () {
                      confrimDeleteTrustedDevicesDialog(
                          trustedDevices, selectedDevices);
                    }))
        ],
      ),
      body: FutureBuilder(
          future: TrustedDevice.get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final devices = snapshot.data as List<TrustedDevice>;
            trustedDevices = devices.obs;
            return trustedDevicesTable(trustedDevices, selectedDevices);
          }),
    );
  }
}

// ── 桌面设置页风格组件（视觉对齐 desktop_setting_page.dart 的 _GCard /
// _switchRow / 网络页 listTile，仅表现层，不改任何选项逻辑）──────────────

const double _kCardContentFontSize = 15;

Widget _settingCard({
  IconData? icon,
  Color iconColor = MyTheme.accent,
  String? title,
  String? subtitle,
  Widget? trailing,
  List<Widget> children = const [],
}) {
  final hasHeader = icon != null || (title != null && title.isNotEmpty);
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: MyTheme.cardBg,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: MyTheme.cardShadow,
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasHeader)
          Row(
            children: [
              if (icon != null) ...[
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
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      translate(title ?? ''),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        translate(subtitle),
                        style:
                            TextStyle(fontSize: 12, color: MyTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                Padding(
                    padding: const EdgeInsets.only(left: 12), child: trailing),
            ],
          ),
        if (hasHeader && children.isNotEmpty)
          Divider(height: 24, color: MyTheme.dividerSoft),
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          children[i],
        ],
      ],
    ),
  );
}

// 标签 + 右侧 Switch 的行，对齐桌面安全页的 _switchRow 视觉。
Widget _cardSwitchRow({
  required Widget title,
  required bool value,
  ValueChanged<bool>? onChanged,
}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onChanged != null ? () => onChanged(!value) : null,
    child: Row(
      children: [
        Expanded(
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: _kCardContentFontSize),
            child: title,
          ),
        ),
        const SizedBox(width: 12),
        Transform.scale(
          scale: 0.85,
          child: Switch(
            value: value,
            activeColor: MyTheme.accent,
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );
}

// 可点击/展示行：左侧可选图标（accent 色，对齐桌面网络页 listTile）、标题、
// 可选描述、右侧值文本；onTap 非空时自动带 chevron。
Widget _cardNavRow({
  IconData? leading,
  required Widget title,
  Widget? description,
  Widget? valueWidget,
  Widget? trailing,
  VoidCallback? onTap,
}) {
  final content = Row(
    children: [
      if (leading != null) ...[
        Icon(leading, color: MyTheme.accent, size: 20),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefaultTextStyle.merge(
              style: const TextStyle(fontSize: _kCardContentFontSize),
              child: title,
            ),
            if (description != null) ...[
              const SizedBox(height: 3),
              DefaultTextStyle.merge(
                style: TextStyle(fontSize: 12, color: MyTheme.textMuted),
                child: description,
              ),
            ],
          ],
        ),
      ),
      if (valueWidget != null) ...[
        const SizedBox(width: 12),
        DefaultTextStyle.merge(
          style: TextStyle(fontSize: 13, color: MyTheme.textMuted),
          child: valueWidget,
        ),
      ],
      if (trailing != null) ...[
        const SizedBox(width: 8),
        trailing,
      ] else if (onTap != null) ...[
        const SizedBox(width: 8),
        Icon(Icons.arrow_forward_ios, size: 14, color: MyTheme.iconFaint),
      ],
    ],
  );
  final padded = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6), child: content);
  return onTap == null
      ? padded
      : InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: padded,
        );
}

class _RadioEntry {
  final String label;
  final String value;
  _RadioEntry(this.label, this.value);
}

typedef _RadioEntryGetter = String Function();
typedef _RadioEntrySetter = Future<void> Function(String);

Widget _getPopupDialogRadioEntry({
  required String title,
  required List<_RadioEntry> list,
  required _RadioEntryGetter getter,
  required _RadioEntrySetter? asyncSetter,
  Widget? tail,
  RxBool? showTail,
  String? notCloseValue,
}) {
  RxString groupValue = ''.obs;
  RxString valueText = ''.obs;

  init() {
    groupValue.value = getter();
    final e = list.firstWhereOrNull((e) => e.value == groupValue.value);
    if (e != null) {
      valueText.value = e.label;
    }
  }

  init();

  void showDialog() async {
    gFFI.dialogManager.show((setState, close, context) {
      final onChanged = asyncSetter == null
          ? null
          : (String? value) async {
              if (value == null) return;
              await asyncSetter(value);
              init();
              if (value != notCloseValue) {
                close();
              }
            };

      return CustomAlertDialog(
          content: Obx(
        () => Column(children: [
          ...list
              .map((e) => getRadio(Text(translate(e.label)), e.value,
                  groupValue.value, onChanged))
              .toList(),
          Offstage(
            offstage:
                !(tail != null && showTail != null && showTail.value == true),
            child: tail,
          ),
        ]),
      ));
    }, backDismiss: true, clickMaskDismiss: true);
  }

  return _cardNavRow(
    title: Text(translate(title)),
    valueWidget: Obx(() => Text(translate(valueText.value))),
    onTap: asyncSetter == null ? null : showDialog,
  );
}
