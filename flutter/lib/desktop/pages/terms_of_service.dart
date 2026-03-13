import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'login_tab_page.dart';

// ── 主题色 ──────────────────────────────────────────────
const _bg = Color(0xFF0F0F12);
const _surface = Color(0xFF1A1A20);
const _border = Color(0xFF2A2A35);
const _accent = Color(0xFF5B8FFF);
const _accentSoft = Color(0x1F5B8FFF);
const _textPrimary = Color(0xFFE8E8F0);
const _textSecondary = Color(0xFF8888A0);
const _textMuted = Color(0xFF55556A);
const _accentText = Color(0xFFA0B8FF);
const _warningBg = Color(0x14FFB43C);
const _warningBorder = Color(0x33FFB43C);
const _warningText = Color(0xFFC8A060);

const String termsOfServiceVersion = '1.0';

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return LoginTabPage(
      showBackButton: true,
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(
          children: [
            _Header(),
            Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 60),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionOne(),
                      _Divider(),
                      _SectionTwo(),
                      _Divider(),
                      _SectionThree(),
                      _Divider(),
                      _SectionFour(),
                      _Divider(),
                      _SectionFive(),
                      _Divider(),
                      _SectionSix(),
                      _Divider(),
                      _SectionSeven(),
                      _Divider(),
                      _SectionEight(),
                      _Divider(),
                      _SectionNine(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _Footer(),
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      padding: EdgeInsets.fromLTRB(
        20, MediaQuery.of(context).padding.top + 16, 20, 16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GAMWING · 佳影寰球科技有限公司',
            style: TextStyle(
              fontSize: 11, letterSpacing: 2, color: _accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '用户协议',
            style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700,
              color: _textPrimary, letterSpacing: -0.4,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '生效日期：2026-02-27',
            style: TextStyle(fontSize: 12, color: _textMuted),
          ),
        ],
      ),
    );
  }
}

// ── Footer ───────────────────────────────────────────────
class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.all(20),
      child: const Text(
        '© 2026 佳影寰球科技有限公司 版权所有',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: _textMuted),
      ),
    );
  }
}

// ── 通用组件 ─────────────────────────────────────────────
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: _border, margin: const EdgeInsets.symmetric(vertical: 28));
  }
}

class _SectionHeader extends StatelessWidget {
  final String num;
  final String title;
  const _SectionHeader({required this.num, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.center,
            child: Text(num, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary, letterSpacing: -0.2)),
        ],
      ),
    );
  }
}

class _SubTitle extends StatelessWidget {
  final String text;
  const _SubTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accent, letterSpacing: 0.3)),
    );
  }
}

class _BodyText extends StatelessWidget {
  final String text;
  final EdgeInsets? padding;
  const _BodyText(this.text, {this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(fontSize: 14, color: _textSecondary, height: 1.85)),
    );
  }
}

class _Card extends StatelessWidget {
  final List<String> items;
  const _Card(this.items);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: items.asMap().entries.map((e) {
          final isLast = e.key == items.length - 1;
          return Container(
            padding: EdgeInsets.only(top: e.key == 0 ? 8 : 8, bottom: isLast ? 8 : 8),
            decoration: BoxDecoration(
              border: isLast ? null : const Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                  ),
                ),
                Expanded(
                  child: Text(e.value, style: const TextStyle(fontSize: 13.5, color: _textSecondary, height: 1.75)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NumList extends StatelessWidget {
  final List<String> items;
  const _NumList(this.items);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final isLast = e.key == items.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: isLast ? null : const Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20, height: 20, margin: const EdgeInsets.only(top: 2, right: 12),
                  decoration: BoxDecoration(color: _accentSoft, borderRadius: BorderRadius.circular(5)),
                  alignment: Alignment.center,
                  child: Text('${e.key + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _accent)),
                ),
                Expanded(
                  child: Text(e.value, style: const TextStyle(fontSize: 13.5, color: _textSecondary, height: 1.75)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final String text;
  const _NoticeBanner(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accentSoft,
        border: Border.all(color: const Color(0x405B8FFF)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📋', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, color: _accentText, height: 1.7)),
          ),
        ],
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  final String text;
  const _WarningBox(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _warningBg,
        border: Border.all(color: _warningBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, color: _warningText, height: 1.75)),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rows = [
      {'label': '公司名称', 'value': '佳影寰球科技有限公司', 'isLink': false},
      {'label': '应用名称', 'value': 'Gamwing', 'isLink': false},
      {'label': '官网', 'value': 'jygamwing.com', 'isLink': true},
    ];
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: rows.asMap().entries.map((e) {
          final isLast = e.key == rows.length - 1;
          final isLink = e.value['isLink'] as bool;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: isLast ? null : const Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.value['label'] as String, style: const TextStyle(fontSize: 12, color: _textMuted)),
                isLink
                    ? GestureDetector(
                        onTap: () => launchUrl(Uri.parse('https://jygamwing.com/')),
                        child: Text(e.value['value'] as String,
                            style: const TextStyle(fontSize: 13, color: _accent, fontWeight: FontWeight.w500)),
                      )
                    : Text(e.value['value'] as String,
                        style: const TextStyle(fontSize: 13, color: _textPrimary, fontWeight: FontWeight.w500)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── 各章节 ───────────────────────────────────────────────
class _SectionOne extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(num: '一', title: '引言与接受条款'),
        const _BodyText('欢迎使用佳影寰球科技有限公司（以下简称「我们」或「本公司」）提供的 Gamwing 应用程序（以下简称「本应用」）。'),
        const _BodyText('本用户协议（以下简称「本协议」）是您与本公司之间关于使用本应用所订立的法律协议，规定了您在使用本应用时的权利与义务。请在使用本应用前仔细阅读全文。'),
        const _NoticeBanner('您下载、安装或使用本应用，即视为您已阅读、理解并同意受本协议全部条款的约束。如您不同意本协议的任何条款，请立即停止使用并卸载本应用。'),
      ],
    );
  }
}

class _SectionTwo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(num: '二', title: '服务说明'),
        const _BodyText('Gamwing 是一款运行于 Android 设备的远程连接工具，提供以下核心功能：'),
        _NumList(const [
          '远程屏幕查看：实时查看被控设备的屏幕画面',
          '远程操控：在获得对方授权后，对被控设备进行触控与键盘模拟操作',
          '点对点或中继连接：通过网络在两台设备间建立加密通信通道',
        ]),
        const _BodyText('本应用仅供合法、正当的远程协助用途，例如个人设备管理、IT 技术支持等场景。',
            padding: EdgeInsets.only(top: 12, bottom: 10)),
      ],
    );
  }
}

class _SectionThree extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(num: '三', title: '使用规范与禁止行为'),
        const _BodyText('您在使用本应用时，必须遵守以下规范：'),
        const _SubTitle('3.1 合法授权原则'),
        _Card(const [
          '您只能在获得设备所有者明确同意的前提下，对其设备发起远程连接或操控。',
          '您不得在未经授权的情况下访问、监控或控制他人设备。',
          '远程会话期间，被控方有权随时终止连接。',
        ]),
        const _SubTitle('3.2 禁止行为'),
        const _WarningBox('以下行为严格禁止，违者将承担相应法律责任，本公司有权终止您的使用资格。'),
        _Card(const [
          '未经授权擅自连接、监控或控制他人设备',
          '利用本应用实施诈骗、勒索、窃取数据或其他违法犯罪活动',
          '对本应用进行逆向工程、反编译、破解或篡改',
          '传播恶意软件或利用本应用危害第三方设备安全',
          '将本应用用于任何违反适用法律法规的用途',
        ]),
      ],
    );
  }
}

class _SectionFour extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(num: '四', title: '知识产权'),
        const _BodyText('本应用及其所有相关内容（包括但不限于软件代码、界面设计、商标、图标、文档等）的知识产权均归佳影寰球科技有限公司所有，受中华人民共和国及国际知识产权法律的保护。'),
        _Card(const [
          '本公司授予您有限的、非独占的、不可转让的个人使用许可。',
          '您不得复制、修改、分发、出售或以任何方式商业利用本应用的任何部分。',
          '未经本公司书面许可，不得使用本公司的任何商标或品牌标识。',
        ]),
      ],
    );
  }
}

class _SectionFive extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _SectionHeader(num: '五', title: '免责声明'),
        _SubTitle('5.1 服务稳定性'),
        _BodyText('本应用按「现状」提供，我们不对服务的不间断性、无错误性或完全安全性作出保证。因网络故障、设备异常或不可抗力导致的服务中断，本公司不承担责任。'),
        _SubTitle('5.2 用户行为责任'),
        _BodyText('您须对自己使用本应用的一切行为及后果承担全部责任。因您违反本协议或滥用本应用所造成的任何损失，由您自行承担，本公司不承担连带责任。'),
        _SubTitle('5.3 第三方内容'),
        _BodyText('在远程会话过程中传输或涉及的第三方内容，均与本公司无关，本公司不对其合法性、准确性或安全性负责。'),
      ],
    );
  }
}

class _SectionSix extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _SectionHeader(num: '六', title: '协议的变更与终止'),
        _SubTitle('6.1 协议变更'),
        _BodyText('本公司有权在必要时修订本协议，修订后的协议将在应用内以显著方式提示，并更新顶部的生效日期。您继续使用本应用即表示接受修订后的协议。'),
        _SubTitle('6.2 服务终止'),
        _BodyText('您可随时卸载本应用以终止本协议。本公司在发现您违反本协议时，有权在不另行通知的情况下终止您的使用资格，并保留追究法律责任的权利。'),
      ],
    );
  }
}

class _SectionSeven extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _SectionHeader(num: '七', title: '适用法律与争议解决'),
        _BodyText('本协议的订立、履行及解释均适用中华人民共和国法律。如因本协议产生任何争议，双方应首先友好协商解决；协商不成的，任何一方均可向本公司所在地有管辖权的人民法院提起诉讼。'),
      ],
    );
  }
}

class _SectionEight extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(num: '八', title: '联系我们'),
        const _BodyText('如您对本用户协议有任何疑问或建议，请通过以下方式联系我们：'),
        _ContactCard(),
        const _BodyText('我们将在收到您的请求后 15 个工作日内予以回复。',
            padding: EdgeInsets.only(top: 12, bottom: 10)),
      ],
    );
  }
}

class _SectionNine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(num: '九', title: '开源声明'),
        const _BodyText('本应用客户端基于 RustDesk 开源项目二次开发，遵循 GNU Affero 通用公共许可证第 3 版（AGPL-3.0）发布。'),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _OpenSourceRow(label: '原始项目', value: 'github.com/rustdesk/rustdesk', url: 'https://github.com/rustdesk/rustdesk', isLast: false),
              _OpenSourceRow(label: '版权归属', value: 'RustDesk, Inc.', isLast: false),
              _OpenSourceRow(label: '许可证', value: 'AGPL-3.0 License', isLast: false),
              _OpenSourceRow(label: '本软件修改版本源码', value: 'github.com/L-fw/rustdesk', url: 'https://github.com/L-fw/rustdesk', isLast: true),
            ],
          ),
        ),
        const _BodyText(
          '依据 AGPL-3.0 协议，您有权获取、使用及修改上述源代码。如需进一步了解开源许可详情，请访问上方源码仓库。',
          padding: EdgeInsets.only(top: 12, bottom: 10),
        ),
      ],
    );
  }
}

class _OpenSourceRow extends StatelessWidget {
  final String label;
  final String value;
  final String? url;
  final bool isLast;

  const _OpenSourceRow({required this.label, required this.value, this.url, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: _textMuted)),
          const SizedBox(width: 12),
          Flexible(
            child: url != null
                ? GestureDetector(
                    onTap: () => launchUrl(Uri.parse(url!)),
                    child: Text(value, textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13, color: _accent, fontWeight: FontWeight.w500)),
                  )
                : Text(value, textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13, color: _textPrimary, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}