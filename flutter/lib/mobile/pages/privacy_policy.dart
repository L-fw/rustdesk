import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Theme Colors ───────────────────────────────────────────────────────────
const _bg = Color(0xFF0F0F12);
const _surface = Color(0xFF1A1A20);
const _border = Color(0xFF2A2A35);
const _accent = Color(0xFF5B8FFF);
const _accentSoft = Color(0x1F5B8FFF);
const _textPrimary = Color(0xFFE8E8F0);
const _textSecondary = Color(0xFF8888A0);
const _textMuted = Color(0xFF55556A);
const _warningBg = Color(0x14FFB43C);
const _warningBorder = Color(0x33FFB43C);
const _warningText = Color(0xFFC8A060);
const _accentBorder = Color(0x405B8FFF);

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _Header(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 一、引言
                  _Section(
                    num: '一',
                    title: '引言',
                    children: [
                      _Para('欢迎使用佳影寰球科技有限公司（以下简称「我们」或「本公司」）提供的 Gamwing 应用程序（以下简称「本应用」）。我们非常重视用户的隐私保护，并致力于依法保护您的个人信息。'),
                      _Para('本隐私政策适用于您在 Android 设备上使用本应用时涉及的信息收集、使用和保护行为。请在使用本应用前仔细阅读本政策，使用本应用即表示您同意本政策的内容。'),
                      const SizedBox(height: 4),
                      _WarningBox('我们建议您在使用完本应用后，尽量卸载软件或关闭相关权限，以避免不必要的损失。鉴于互联网的性质，我们希望提醒您注意，在透过互联网传送个人资料（例如透过电子邮件通讯）时，可能会有某些安全漏洞，而要全面保护个人资料、防止第三者接达是不可能的。'),
                    ],
                  ),
                  _Divider(),

                  // 二、收集的信息
                  _Section(
                    num: '二',
                    title: '我们收集的信息',
                    children: [
                      _SubTitle('2.1 设备信息'),
                      _Card(items: [
                        '设备型号、品牌及操作系统版本',
                        '设备唯一标识符（如 Android ID）',
                        '屏幕分辨率及硬件配置信息',
                        '应用版本号及运行状态信息',
                      ]),
                      _SubTitle('2.2 网络与 IP 地址信息'),
                      _Card(items: [
                        '您的 IP 地址（用于建立点对点或中继连接）',
                        '网络类型（Wi-Fi、移动数据等）',
                        '连接状态及网络质量相关数据',
                      ]),
                      _SubTitle('2.3 我们不收集的信息'),
                      _Card(items: [
                        '您的姓名、身份证号、手机号码等个人身份信息',
                        '您的位置信息',
                        '您设备中的照片、文件、通讯录等私人内容（除非您主动在会话中共享）',
                      ]),
                    ],
                  ),
                  _Divider(),

                  // 三、使用目的
                  _Section(
                    num: '三',
                    title: '信息的使用目的',
                    children: [
                      _Para('我们收集上述信息仅用于以下目的：'),
                      _NumList(items: [
                        '建立和维护设备间的远程连接',
                        '优化应用性能，改善用户体验',
                        '诊断并解决技术问题',
                        '保障应用及服务的安全稳定运行',
                      ]),
                      const SizedBox(height: 12),
                      _Para('我们不会将您的信息用于广告推送、营销活动或出售给第三方。'),
                    ],
                  ),
                  _Divider(),

                  // 四、存储与安全
                  _Section(
                    num: '四',
                    title: '信息的存储与安全',
                    children: [
                      _Para('我们采取合理的技术和管理措施保护您的信息安全：'),
                      _Card(items: [
                        '传输过程中使用加密技术保护数据',
                        '限制对用户数据的访问权限，仅授权人员可访问',
                        '定期审查和更新安全措施',
                      ]),
                      const SizedBox(height: 12),
                      _Para('我们仅在实现本政策所述目的所必要的期限内保留您的信息，超过保留期限后将予以删除或匿名化处理。'),
                    ],
                  ),
                  _Divider(),

                  // 五、共享与披露
                  _Section(
                    num: '五',
                    title: '信息的共享与披露',
                    children: [
                      _Para('我们不会将您的个人信息出售、出租或以其他商业方式提供给任何第三方。在以下情况下，我们可能会共享必要的信息：'),
                      _Card(items: [
                        '经您明确同意的情形',
                        '依法配合政府机关、司法机关依法履行职责的情形',
                        '为保护本公司、用户或公众的合法权益而必要披露的情形',
                      ]),
                    ],
                  ),
                  _Divider(),

                  // 六、您的权利
                  _Section(
                    num: '六',
                    title: '您的权利',
                    children: [
                      _Para('根据适用法律，您对自己的个人信息享有以下权利：'),
                      _RightsGrid(),
                      const SizedBox(height: 12),
                      _Para('如需行使上述权利，请通过本政策末尾的联系方式联系我们。'),
                    ],
                  ),
                  _Divider(),

                  // 七、应用权限说明
                  _Section(
                    num: '七',
                    title: '应用权限说明',
                    children: [
                      _Para('本应用在 Android 设备上可能申请以下权限，以实现相应功能：'),
                      _PermCard(),
                      const SizedBox(height: 12),
                      _Para('我们仅在您使用相关功能时请求必要权限，您可在设备设置中随时撤销授权。'),
                    ],
                  ),
                  _Divider(),

                  // 八、隐私政策的更新
                  _Section(
                    num: '八',
                    title: '隐私政策的更新',
                    children: [
                      _Para('我们可能会不时更新本隐私政策。政策更新后，我们将在应用内以显著方式提示您，并更新政策顶部的生效日期。建议您定期查阅本政策，以了解最新内容。'),
                      _Para('重大变更将通过应用内通知或其他合理方式告知您，您继续使用本应用即表示同意更新后的政策。'),
                    ],
                  ),
                  _Divider(),

                  // 九、联系我们
                  _Section(
                    num: '九',
                    title: '联系我们',
                    children: [
                      _Para('如您对本隐私政策有任何疑问、意见或建议，或需要行使您的个人信息权利，请通过以下方式联系我们：'),
                      _ContactCard(),
                      const SizedBox(height: 12),
                      _Para('我们将在收到您的请求后 15 个工作日内予以回复。'),
                    ],
                  ),

                  // Footer
                  const SizedBox(height: 8),
                  const Divider(color: _border, thickness: 1),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      '© 2026 佳影寰球科技有限公司 版权所有',
                      style: TextStyle(fontSize: 12, color: _textMuted),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gamwing · 佳影寰球科技有限公司',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              color: _accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '隐私政策',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '生效日期：2026-02-27',
            style: TextStyle(fontSize: 12, color: _textMuted),
          ),
        ],
      ),
    );
  }
}

// ─── Section ─────────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String num;
  final String title;
  final List<Widget> children;

  const _Section({
    required this.num,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  num,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

// ─── Sub Title ───────────────────────────────────────────────────────────────
class _SubTitle extends StatelessWidget {
  final String text;
  const _SubTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _accent,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ─── Paragraph ───────────────────────────────────────────────────────────────
class _Para extends StatelessWidget {
  final String text;
  const _Para(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: _textSecondary,
          height: 1.85,
        ),
      ),
    );
  }
}

// ─── Card with dot items ──────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final List<String> items;
  const _Card({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: List.generate(items.length, (i) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: i < items.length - 1
                  ? const Border(bottom: BorderSide(color: _border, width: 1))
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    items[i],
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: _textSecondary,
                      height: 1.75,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─── Numbered List ───────────────────────────────────────────────────────────
class _NumList extends StatelessWidget {
  final List<String> items;
  const _NumList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(items.length, (i) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: i < items.length - 1
                  ? const Border(bottom: BorderSide(color: _border, width: 1))
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 2, right: 12),
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    items[i],
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: _textSecondary,
                      height: 1.75,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─── Warning Box ─────────────────────────────────────────────────────────────
class _WarningBox extends StatelessWidget {
  final String text;
  const _WarningBox(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _warningBg,
        border: Border.all(color: _warningBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: _warningText,
                height: 1.75,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Rights Grid ─────────────────────────────────────────────────────────────
class _RightsGrid extends StatelessWidget {
  const _RightsGrid();

  static const _rights = [
    ('🔍', '查询权', '查询我们持有的您的个人信息'),
    ('✏️', '更正权', '要求更正不准确的个人信息'),
    ('🗑️', '删除权', '要求删除您的个人信息'),
    ('🚪', '撤回同意权', '随时卸载本应用以停止信息收集'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: _rights
          .map((r) => Container(
                decoration: BoxDecoration(
                  color: _surface,
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.$1, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 6),
                    Text(
                      r.$2,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        r.$3,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _textMuted,
                          height: 1.6,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

// ─── Permission Card ─────────────────────────────────────────────────────────
class _PermCard extends StatelessWidget {
  const _PermCard();

  static const _perms = [
    ('🌐', '网络访问权限', '用于建立远程连接'),
    ('♿', '无障碍服务权限', '用于在被控制端模拟触控与键盘操作'),
    ('🪟', '悬浮窗权限', '用于显示远程控制操作工具栏'),
    ('📹', '屏幕录制权限', '用于在被控制端采集屏幕画面'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(_perms.length, (i) {
          final p = _perms[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: i < _perms.length - 1
                  ? const Border(bottom: BorderSide(color: _border, width: 1))
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(p.$1,
                      style: const TextStyle(fontSize: 18),
                      textAlign: TextAlign.center),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.$2,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary)),
                      const SizedBox(height: 2),
                      Text(p.$3,
                          style: const TextStyle(
                              fontSize: 12, color: _textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─── Contact Card ─────────────────────────────────────────────────────────────
class _ContactCard extends StatelessWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _contactRow('公司名称', '佳影寰球科技有限公司', hasBorder: true),
          _contactRow('应用名称', 'Gamwing', hasBorder: true),
          _contactRowLink('官网', 'jygamwing.com', 'https://jygamwing.com/'),
        ],
      ),
    );
  }

  Widget _contactRow(String label, String value, {bool hasBorder = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: hasBorder
          ? const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: _border, width: 1)))
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: _textMuted)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _textPrimary)),
        ],
      ),
    );
  }

  Widget _contactRowLink(String label, String display, String url) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: _textMuted)),
          GestureDetector(
            onTap: () => launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication),
            child: Text(
              display,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _accent,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Divider ─────────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 28),
      child: Divider(color: _border, thickness: 1, height: 1),
    );
  }
}
