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
                      messagePadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      messageTextBuilder: (message, _, __) {
                        final isOwnMessage = message.user.id.isBlank!;
                        return Column(
                          crossAxisAlignment: isOwnMessage
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(message.text,
                                style: const TextStyle(
                                    color: _wechatTextColor,
                                    fontSize: 14,
                                    height: 1.4)),
                            const SizedBox(height: 4),
                            Text(
                              "${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}",
                              style: const TextStyle(
                                color: _wechatTimeColor,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        );
                      },
                      messageDecorationBuilder:
                          (message, previousMessage, nextMessage) {
                        final isOwnMessage = message.user.id.isBlank!;
                        return BoxDecoration(
                          color: isOwnMessage
                              ? _wechatGreenBubble
                              : _wechatWhiteBubble,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(10),
                            topRight: const Radius.circular(10),
                            bottomLeft: Radius.circular(isOwnMessage ? 10 : 2),
                            bottomRight:
                                Radius.circular(isOwnMessage ? 2 : 10),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
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
