import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../mobile/pages/home_page.dart';

enum ChatPageType {
  mobileMain,
  desktopCM,
}

class ChatPage extends StatelessWidget implements PageShape {
  late final ChatModel chatModel;
  final ChatPageType? type;

  ChatPage({ChatModel? chatModel, this.type}) {
    this.chatModel = chatModel ?? gFFI.chatModel;
  }

  @override
  final title = translate("Chat");

  @override
  final icon = unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum);

  @override
  final appBarActions = [
    PopupMenuButton<MessageKey>(
        tooltip: "",
        icon: unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum,
            icon: Icon(Icons.group)),
        itemBuilder: (context) {
          // only mobile need [appBarActions], just bind gFFI.chatModel
          final chatModel = gFFI.chatModel;
          return chatModel.messages.entries.map((entry) {
            final key = entry.key;
            final user = entry.value.chatUser;
            final client = gFFI.serverModel.clients
                .firstWhereOrNull((e) => e.id == key.connId);
            final connected =
                gFFI.serverModel.clients.any((e) => e.id == key.connId);
            return PopupMenuItem<MessageKey>(
              child: Row(
                children: [
                  Icon(
                          key.isOut
                              ? Icons.call_made_rounded
                              : Icons.call_received_rounded,
                          color: MyTheme.accent)
                      .marginOnly(right: 6),
                  Text("${user.firstName}   ${user.id}"),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 46, 205, 139)),
                    ).marginSymmetric(horizontal: 2),
                  if (client != null)
                    unreadMessageCountBuilder(client.unreadChatMessageCount)
                        .marginOnly(left: 4)
                ],
              ),
              value: key,
            );
          }).toList();
        },
        onSelected: (key) {
          gFFI.chatModel.changeCurrentKey(key);
        })
  ];

  // WeChat-style color constants
  static const _wechatBgColor = Color(0xFFEDEDED);
  static const _wechatGreenBubble = Color(0xFF95EC69);
  static const _wechatWhiteBubble = Color(0xFFFFFFFF);
  static const _wechatInputBarBg = Color(0xFFF7F7F7);
  static const _wechatInputFieldBg = Color(0xFFFFFFFF);
  static const _wechatSendBtnColor = Color(0xFF07C160);
  static const _wechatTextColor = Color(0xFF1C1C1E);
  static const _wechatTimeColor = Color(0xFFB2B2B2);
  static const _wechatDateBadgeBg = Color(0xFFCECECE);
  static const _wechatDateTextColor = Color(0xFFFFFFFF);

  /// Build a WeChat-style bubble with a triangular tail
  Widget _buildWeChatBubble({
    required Widget child,
    required bool isOwnMessage,
    required double maxWidth,
  }) {
    final bubbleColor =
        isOwnMessage ? _wechatGreenBubble : _wechatWhiteBubble;
    const tailWidth = 6.0;
    const tailHeight = 10.0;
    const radius = 4.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left tail (for other's messages)
        if (!isOwnMessage)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: CustomPaint(
              size: const Size(tailWidth, tailHeight),
              painter: _BubbleTailPainter(
                color: bubbleColor,
                isOwnMessage: false,
              ),
            ),
          ),
        // Bubble body
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth - tailWidth),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: child,
          ),
        ),
        // Right tail (for own messages)
        if (isOwnMessage)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: CustomPaint(
              size: const Size(tailWidth, tailHeight),
              painter: _BubbleTailPainter(
                color: bubbleColor,
                isOwnMessage: true,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: chatModel,
      child: Container(
        color: _wechatBgColor,
        child: Consumer<ChatModel>(
          builder: (context, chatModel, child) {
            final readOnly = type == ChatPageType.mobileMain &&
                    (chatModel.currentKey.connId == ChatModel.clientModeID ||
                        gFFI.serverModel.clients.every((e) =>
                            e.id != chatModel.currentKey.connId ||
                            chatModel.currentUser == null)) ||
                type == ChatPageType.desktopCM &&
                    gFFI.serverModel.clients
                            .firstWhereOrNull(
                                (e) => e.id == chatModel.currentKey.connId)
                            ?.disconnected ==
                        true;
            return Stack(
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final chat = DashChat(
                    onSend: chatModel.send,
                    currentUser: chatModel.me,
                    messages: chatModel
                            .messages[chatModel.currentKey]?.chatMessages ??
                        [],
                    readOnly: readOnly,
                    inputOptions: InputOptions(
                      focusNode: chatModel.inputNode,
                      textController: chatModel.textController,
                      inputTextStyle: const TextStyle(
                          fontSize: 14,
                          color: _wechatTextColor),
                      inputDecoration: InputDecoration(
                        isDense: true,
                        hintText: translate('Write a message'),
                        hintStyle: TextStyle(
                          color: _wechatTimeColor,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: _wechatInputFieldBg,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6.0),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6.0),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6.0),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      inputToolbarPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      inputToolbarStyle: BoxDecoration(
                        color: _wechatInputBarBg,
                        border: Border(
                          top: BorderSide(
                            color: const Color(0xFFD9D9D9),
                            width: 0.5,
                          ),
                        ),
                      ),
                      sendButtonBuilder: (onSend) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: SizedBox(
                            height: 34,
                            child: ElevatedButton(
                              onPressed: onSend,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _wechatSendBtnColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              child: Text(
                                translate('Send'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    messageListOptions: MessageListOptions(
                      dateSeparatorBuilder: (date) {
                        return Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _wechatDateBadgeBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}",
                              style: const TextStyle(
                                fontSize: 11,
                                color: _wechatDateTextColor,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    messageOptions: MessageOptions(
                      showOtherUsersAvatar: false,
                      showTime: false,
                      showOtherUsersName: false,
                      textColor: _wechatTextColor,
                      maxWidth: constraints.maxWidth * 0.7,
                      messageRowBuilder: (message, previousMessage,
                          nextMessage, isAfterDateSeparator,
                          isBeforeDateSeparator) {
                        final isOwnMessage = message.user.id == chatModel.me.id;
                        final bubbleContent = DefaultTextStyle(
                          style: const TextStyle(
                            decoration: TextDecoration.none,
                            color: _wechatTextColor,
                            fontSize: 14,
                          ),
                          child: Column(
                            crossAxisAlignment: isOwnMessage
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.text,
                                style: const TextStyle(
                                  color: _wechatTextColor,
                                  fontSize: 14,
                                  height: 1.4,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}",
                                style: const TextStyle(
                                  color: _wechatTimeColor,
                                  fontSize: 10,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        );

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          child: Row(
                            mainAxisAlignment: isOwnMessage
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: _buildWeChatBubble(
                                  child: bubbleContent,
                                  isOwnMessage: isOwnMessage,
                                  maxWidth: constraints.maxWidth * 0.7,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ).workaroundFreezeLinuxMint();
                  return SelectionArea(child: chat);
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Paints a small triangular tail for WeChat-style chat bubbles.
class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isOwnMessage;

  _BubbleTailPainter({required this.color, required this.isOwnMessage});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (isOwnMessage) {
      // Right-pointing tail
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height * 0.3);
      path.lineTo(0, size.height);
      path.close();
    } else {
      // Left-pointing tail
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height * 0.3);
      path.lineTo(size.width, size.height);
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      color != oldDelegate.color || isOwnMessage != oldDelegate.isOwnMessage;
}

