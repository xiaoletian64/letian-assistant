part of 'main.dart';

/// Flyer Chat owns message layout, Markdown rendering, composer and scrolling.
/// The parent retains the authenticated, durable 106 conversation protocol.
class LobsterFrameworkChat extends StatefulWidget {
  const LobsterFrameworkChat({
    super.key,
    required this.messages,
    required this.input,
    required this.loading,
    required this.busy,
    required this.onSend,
    required this.emptyBuilder,
    required this.status,
  });
  final List<Map<String, dynamic>> messages;
  final TextEditingController input;
  final bool loading, busy;
  final VoidCallback onSend;
  final WidgetBuilder emptyBuilder;
  final Widget status;
  @override
  State<LobsterFrameworkChat> createState() => _LobsterFrameworkChatState();
}

class _LobsterFrameworkChatState extends State<LobsterFrameworkChat> {
  late final chat_core.InMemoryChatController controller;
  String fingerprint = '';
  final streamScroll = ScrollController();
  bool unread = false;
  void onScroll() {
    if (streamScroll.hasClients &&
        streamScroll.offset <= 60 &&
        unread &&
        mounted) {
      setState(() => unread = false);
    }
  }

  List<chat_core.Message> converted() {
    final ids = <String>{};
    return [
      for (var i = 0; i < widget.messages.length; i++)
        buildMessage(widget.messages[i], i, ids),
    ];
  }

  chat_core.TextMessage buildMessage(
    Map<String, dynamic> m,
    int index,
    Set<String> ids,
  ) {
    final text = '${m['content'] ?? m['text'] ?? ''}';
    final base =
        '${m['id'] ?? 'message-$index-${cryptoSha256(utf8.encode(text))}'}';
    final id = ids.add(base) ? base : '$base-$index';
    return chat_core.TextMessage(
      id: id,
      authorId: m['role'] == 'user' ? 'me' : 'lobster',
      text: text,
      createdAt: sceneDate(m['created_at']),
      metadata: {'state': m['status']},
    );
  }

  @override
  void initState() {
    super.initState();
    streamScroll.addListener(onScroll);
    fingerprint = jsonEncode(widget.messages);
    controller = chat_core.InMemoryChatController(messages: converted());
  }

  @override
  void didUpdateWidget(covariant LobsterFrameworkChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = jsonEncode(widget.messages);
    if (next != fingerprint) {
      fingerprint = next;
      if (streamScroll.hasClients && streamScroll.offset > 60) unread = true;
      final nextMessages = converted();
      final previous = [...controller.messages];
      if (previous.length == nextMessages.length &&
          List.generate(
            previous.length,
            (i) => previous[i].id == nextMessages[i].id,
          ).every((same) => same)) {
        for (var i = 0; i < previous.length; i++) {
          if (previous[i] != nextMessages[i]) {
            controller.updateMessage(previous[i], nextMessages[i]);
          }
        }
      } else {
        controller.setMessages(nextMessages, animated: false);
      }
    }
  }

  @override
  void dispose() {
    streamScroll.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> copy(BuildContext c, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (c.mounted) notice(c, '消息已复制');
  }

  Widget codeBlock(BuildContext c, String language, String code) => Material(
    color: const Color(0xFFF5F7FC),
    borderRadius: BorderRadius.circular(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  language.trim().isEmpty ? '代码' : language.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: sceneMuted),
                ),
              ),
              IconButton(
                tooltip: '复制代码',
                onPressed: () => copy(c, code),
                icon: const Icon(Icons.copy_outlined, size: 18),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Text(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
              color: sceneInk,
            ),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => flyer.Chat(
    currentUserId: 'me',
    chatController: controller,
    resolveUser: (id) async =>
        chat_core.User(id: id, name: id == 'me' ? '我' : '龙虾'),
    theme: chat_core.ChatTheme.fromThemeData(Theme.of(context)),
    backgroundColor: const Color(0xFFF0F6FF),
    onMessageLongPress: (c, message, {required index, required details}) {
      if (message is! chat_core.TextMessage) return;
      showModalBottomSheet<void>(
        context: c,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制原文'),
                onTap: () {
                  Navigator.pop(sheet);
                  copy(c, message.text);
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('选择文本'),
                onTap: () {
                  Navigator.pop(sheet);
                  showModalBottomSheet<void>(
                    context: c,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => SafeArea(
                      child: SizedBox(
                        height: MediaQuery.sizeOf(c).height * .65,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: SelectableText(message.text),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
    onMessageSend: (text) {
      if (!widget.loading && !widget.busy) {
        widget.input.text = text;
        widget.onSend();
      }
    },
    builders: chat_core.Builders(
      chatAnimatedListBuilder: (c, itemBuilder) =>
          flyer.ChatAnimatedListReversed(
            itemBuilder: itemBuilder,
            scrollController: streamScroll,
            handleSafeArea: false,
            insertAnimationDuration: MediaQuery.disableAnimationsOf(c)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            removeAnimationDuration: MediaQuery.disableAnimationsOf(c)
                ? Duration.zero
                : const Duration(milliseconds: 120),
          ),
      emptyChatListBuilder: (c) => widget.loading
          ? const Center(child: CircularProgressIndicator())
          : widget.emptyBuilder(c),
      composerBuilder: (c) => flyer.Composer(
        textEditingController: widget.input,
        maxLength: 12000,
        minLines: 1,
        maxLines: 5,
        hintText: '给龙虾发消息…',
        inputClearMode: flyer.InputClearMode.never,
        sendButtonDisabled: widget.loading || widget.busy,
        sendIcon: Semantics(
          label: '发送消息',
          child: Text(
            widget.busy ? '等待中' : '发送',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        sendIconColor: sceneBlue,
        backgroundColor: const Color(0xFFF0F6FF),
        inputFillColor: Colors.white,
        textColor: sceneInk,
        hintColor: sceneMuted,
        topWidget: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unread)
              TextButton.icon(
                onPressed: () {
                  if (streamScroll.hasClients) {
                    streamScroll.animateTo(
                      0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                    );
                  }
                  setState(() => unread = false);
                },
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: const Text('有新内容 · 回到底部'),
              ),
            widget.status,
          ],
        ),
        handleSafeArea: false,
      ),
      textMessageBuilder:
          (
            c,
            message,
            index, {
            required bool isSentByMe,
            chat_core.MessageGroupStatus? groupStatus,
          }) => SelectionArea(
            child: flyer_text.FlyerChatTextMessage(
              message: message,
              codeBuilder: (c, language, code, closed) =>
                  codeBlock(c, language, code),
              index: index,
              sentBackgroundColor: const Color(0xFFE1EDFF),
              receivedBackgroundColor: Colors.white,
              sentTextStyle: const TextStyle(
                color: sceneInk,
                fontSize: 15,
                height: 1.55,
              ),
              receivedTextStyle: const TextStyle(
                color: sceneInk,
                fontSize: 15,
                height: 1.55,
              ),
              showTime: message.createdAt != null,
              showStatus: false,
              linkPreviewPosition: chat_core.LinkPreviewPosition.none,
              topWidget: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: const Color(0xFFEAF2FF),
                    child: Icon(
                      isSentByMe ? Icons.person : Icons.smart_toy_outlined,
                      size: 14,
                      color: sceneBlue,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isSentByMe ? '我' : '龙虾',
                    style: const TextStyle(fontSize: 12, color: sceneMuted),
                  ),
                  const SizedBox(width: 5),
                  if (message.metadata?['state'] != null)
                    Flexible(
                      child: Text(
                        switch (message.metadata?['state']) {
                          'running' => '输出中',
                          'cancelled' => '已停止',
                          'failed' => '失败',
                          'interrupted' => '中断',
                          _ => '',
                        },
                        style: const TextStyle(fontSize: 10, color: sceneMuted),
                      ),
                    ),
                  IconButton(
                    tooltip: '复制消息',
                    iconSize: 18,
                    onPressed: () => copy(c, message.text),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
              onLinkTap: (url, title) {
                final uri = Uri.tryParse(url);
                if (uri != null &&
                    ['https', 'http'].contains(uri.scheme) &&
                    uri.host.isNotEmpty) {
                  openLink(c, url);
                } else {
                  notice(c, '仅支持打开网页链接');
                }
              },
            ),
          ),
    ),
  );
}
