part of 'main.dart';

const lobsterApi = '/api/hub/lobster/chat';

class ConversationHub extends StatelessWidget {
  const ConversationHub({super.key, required this.chat, required this.mirror});
  final bool chat, mirror;
  @override
  Widget build(BuildContext context) {
    if (!chat) return const SessionsPage();
    if (!mirror) return const LobsterChatPage();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('会话'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '龙虾对话'),
              Tab(text: '会话镜像'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [LobsterChatPage(embedded: true), SessionsPage()],
        ),
      ),
    );
  }
}

class LobsterChatPage extends StatefulWidget {
  const LobsterChatPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<LobsterChatPage> createState() => _LobsterChatPageState();
}

class _LobsterChatPageState extends State<LobsterChatPage>
    with WidgetsBindingObserver {
  final input = TextEditingController();
  List<Map<String, dynamic>> sessions = [], messages = [];
  String? ownerToken, sessionId, jobId, requestKey, requestText;
  String error = '', connection = '正在连接106龙虾…';
  bool loading = true, submitting = false, waiting = false;
  int generation = 0;
  Timer? poll;
  StreamSubscription<void>? eventSubscription;
  Completer<void>? streamAbort;
  Timer? streamOwnerGuard;
  LobsterStreamSnapshot? live;
  int streamEpoch = 0;
  bool reconnecting = false, cancelRequested = false, cancelling = false;
  String jobStatus = '', liveMessageId = '';

  void closeStream() {
    streamEpoch++;
    poll?.cancel();
    streamOwnerGuard?.cancel();
    streamOwnerGuard = null;
    final abort = streamAbort;
    streamAbort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
    eventSubscription?.cancel();
    eventSubscription = null;
  }

  void clearJob() {
    closeStream();
    live = null;
    jobStatus = '';
    liveMessageId = '';
    reconnecting = false;
    cancelRequested = false;
    cancelling = false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    boot();
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    closeStream();
    input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) closeStream();
    if (state == AppLifecycleState.resumed && mounted && !submitting) {
      if (waiting && jobId != null) {
        checkJob();
      } else {
        boot();
      }
    }
  }

  void resetForAccountChange() {
    generation++;
    clearJob();
    input.clear();
    setState(() {
      messages = [];
      sessions = [];
      sessionId = null;
      jobId = null;
      requestKey = null;
      requestText = null;
      ownerToken = null;
      loading = false;
      submitting = false;
      waiting = false;
      connection = '账号已变化';
      error = '已清理原账号内容，请重新连接。';
    });
  }

  Future<bool> valid(String? captured, int version) async {
    final active = await token();
    if (!mounted || generation != version) return false;
    if (active != captured) {
      resetForAccountChange();
      return false;
    }
    return true;
  }

  Future<void> boot() async {
    final captured = await token();
    if (!mounted) return;
    if (ownerToken != null && ownerToken != captured) resetForAccountChange();
    final version = ++generation;
    ownerToken = captured;
    try {
      final data = await Future.wait([
        apiGet('$lobsterApi/status'),
        apiGet('$lobsterApi/sessions'),
      ]);
      if (!await valid(captured, version)) return;
      final state = sceneMap(data[0]);
      sessions = sceneList(data[1]['sessions']);
      setState(() {
        connection = state['connected'] == false ? '龙虾暂未连接' : '106 · 龙虾';
        loading = false;
        error = '';
      });
      if (sessionId != null) {
        await selectSession(sessionId!);
      } else if (sessions.isNotEmpty && input.text.trim().isEmpty) {
        await selectSession('${sessions.first['id']}');
      }
    } catch (e) {
      if (await valid(captured, version)) {
        setState(() {
          loading = false;
          connection = '连接暂不可用';
          clearOnAuthFailure(e);
          error = friendlyError(e);
        });
      }
    }
  }

  Future<void> selectSession(String id) async {
    if (submitting) return;
    clearJob();
    final version = ++generation;
    final captured = await token();
    if (!mounted) return;
    if (ownerToken != null && captured != ownerToken) {
      resetForAccountChange();
      return;
    }
    final switching = sessionId != id;
    setState(() {
      ownerToken = captured;
      sessionId = id;
      messages = [];
      loading = true;
      waiting = false;
      jobId = null;
      error = '';
      if (switching) {
        requestKey = null;
        requestText = null;
        input.clear();
      }
    });
    try {
      final data = await apiGet('$lobsterApi/sessions/$id/messages');
      if (!await valid(captured, version)) return;
      setState(() {
        messages = sceneList(data['messages']);
        loading = false;
      });
      final active = sceneMap(data['active_job']);
      if (active.isNotEmpty &&
          ['queued', 'running'].contains(active['status'])) {
        setState(() {
          jobId = '${active['id']}';
          waiting = true;
        });
        await checkJob();
      }
    } catch (e) {
      if (await valid(captured, version)) {
        setState(() {
          loading = false;
          clearOnAuthFailure(e);
          error = friendlyError(e);
        });
      }
    }
  }

  void clearOnAuthFailure(Object e) {
    if (e is SessionExpired || e is AccessDenied) {
      messages = [];
      sessions = [];
      requestKey = null;
      requestText = null;
      ownerToken = null;
      submitting = false;
      loading = false;
      sessionId = null;
      jobId = null;
      waiting = false;
      clearJob();
      input.clear();
      connection = '登录或权限已变化';
    }
  }

  void updatePartial() {
    final snapshot = live;
    if (snapshot == null || snapshot.content.isEmpty) return;
    final id = liveMessageId.isEmpty ? 'job-${snapshot.jobId}' : liveMessageId;
    final index = messages.indexWhere(
      (m) => m['id'] == id || m['job_id'] == snapshot.jobId,
    );
    final row = <String, dynamic>{
      if (index >= 0) ...messages[index],
      'id': id,
      'job_id': snapshot.jobId,
      'role': 'assistant',
      'content': snapshot.content,
      'status': snapshot.status,
    };
    messages = [...messages];
    if (index >= 0) {
      messages[index] = row;
    } else {
      messages.add(row);
    }
  }

  Future<void> reconcile(String id, String? captured, int version) async {
    closeStream();
    dynamic history;
    try {
      history = await apiGet('$lobsterApi/sessions/$sessionId/messages');
    } catch (e) {
      if (await valid(captured, version) && jobId == id) {
        streamFailed(e, id, captured, version, snapshot: true);
      }
      return;
    }
    if (!await valid(captured, version) || jobId != id) return;
    final state = live?.status ?? jobStatus;
    setState(() {
      messages = sceneList(history['messages']);
      waiting = false;
      jobId = null;
      reconnecting = false;
      cancelling = false;
      cancelRequested = false;
      jobStatus = state;
      error = switch (state) {
        'completed' => '',
        'cancelled' => '已停止，已保留收到的内容。',
        'interrupted' => '任务被中断，已保留内容；未自动重发。',
        _ => '回复失败，已保留内容；可检查历史后重新发送。',
      };
      if (state == 'completed' && input.text.trim() == requestText) {
        input.clear();
      }
      requestKey = null;
      requestText = null;
    });
  }

  /// Reopening a page and recovering a sequence gap both begin with the durable
  /// snapshot. Reconnection itself never resubmits a user message.
  Future<void> checkJob() async {
    final id = jobId, captured = ownerToken, version = generation;
    if (id == null) return;
    closeStream();
    final epoch = streamEpoch;
    try {
      final data = await apiGet('$lobsterApi/jobs/$id');
      if (!await valid(captured, version) ||
          jobId != id ||
          epoch != streamEpoch) {
        return;
      }
      final job = sceneMap(data['job']);
      final previous = live?.jobId == id ? live : null;
      final sequence =
          sceneNumber(job['last_event_id'])?.toInt() ?? previous?.seq ?? 0;
      if (sequence < (previous?.seq ?? 0)) {
        throw const FormatException('任务快照落后，正在重新连接');
      }
      live = LobsterStreamSnapshot(
        id,
        seq: sequence,
        content: job['partial_content'] is String
            ? job['partial_content'] as String
            : previous?.content ?? '',
        status: '${job['status'] ?? previous?.status ?? 'queued'}',
      );
      liveMessageId = '${job['assistant_message_id'] ?? 'job-$id'}';
      setState(() {
        jobStatus = live!.status;
        cancelRequested = job['cancel_requested'] == true;
        reconnecting = false;
        updatePartial();
      });
      if (live!.terminal) {
        await reconcile(id, captured, version);
      } else {
        await subscribeEvents(id, captured, version);
      }
    } catch (e) {
      if (!await valid(captured, version) ||
          jobId != id ||
          epoch != streamEpoch) {
        return;
      }
      streamFailed(e, id, captured, version, snapshot: true);
    }
  }

  void streamFailed(
    Object e,
    String id,
    String? captured,
    int version, {
    bool snapshot = false,
  }) {
    if (!mounted || generation != version || jobId != id) return;
    closeStream();
    if (e is SessionExpired || e is AccessDenied) {
      setState(() {
        clearOnAuthFailure(e);
        error = friendlyError(e);
      });
      return;
    }
    setState(() {
      reconnecting = true;
      error = '连接中断，正在续接已有回复；不会重新生成。';
    });
    poll = Timer(const Duration(seconds: 2), () async {
      if (!await valid(captured, version) || jobId != id) return;
      if (snapshot || e is FormatException) {
        await checkJob();
      } else {
        await subscribeEvents(id, captured, version);
      }
    });
  }

  Future<void> subscribeEvents(String id, String? captured, int version) async {
    closeStream();
    final epoch = streamEpoch;
    final abort = Completer<void>();
    streamAbort = abort;
    streamOwnerGuard = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || generation != version || epoch != streamEpoch) return;
      await valid(captured, version);
    });
    try {
      final request =
          http.AbortableRequest(
              'GET',
              Uri.parse(
                '$baseUrl$lobsterApi/jobs/$id/events?after=${live?.seq ?? 0}',
              ),
              abortTrigger: abort.future,
            )
            ..headers.addAll({
              'Authorization': 'Bearer $captured',
              'Accept': 'text/event-stream',
              'Last-Event-ID': '${live?.seq ?? 0}',
            });
      final response = await apiClient
          .send(request)
          .then((response) {
            // timeout does not own the original Future. Dispose a late body even
            // when an injected/third-party Client ignores abortTrigger.
            if (abort.isCompleted || !mounted || epoch != streamEpoch) {
              response.stream.listen((_) {}, onError: (Object _) {}).cancel();
              throw http.RequestAbortedException(request.url);
            }
            return response;
          })
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException('流式连接建立超时');
            },
          );
      if (!await valid(captured, version) ||
          epoch != streamEpoch ||
          jobId != id) {
        response.stream.listen((_) {}).cancel();
        return;
      }
      if (response.statusCode != 200) {
        await decodeResponse(await http.Response.fromStream(response));
        throw const FormatException('流式连接返回异常');
      }
      if (!(response.headers['content-type'] ?? '').contains(
        'text/event-stream',
      )) {
        response.stream.listen((_) {}).cancel();
        throw const FormatException('未收到流式响应');
      }
      setState(() {
        reconnecting = false;
        error = '';
      });
      eventSubscription = lobsterSseEvents(response.stream)
          .timeout(const Duration(seconds: 45))
          .asyncMap<void>((event) async {
            if (!await valid(captured, version) ||
                epoch != streamEpoch ||
                jobId != id) {
              return;
            }
            final snapshot = live ??= LobsterStreamSnapshot(id);
            if (!snapshot.apply(event)) return;
            setState(() {
              jobStatus = snapshot.status;
              updatePartial();
            });
            if (snapshot.terminal) await reconcile(id, captured, version);
          })
          .listen(
            (_) {},
            onError: (Object e) async {
              if (await valid(captured, version) &&
                  epoch == streamEpoch &&
                  jobId == id) {
                streamFailed(e, id, captured, version);
              }
            },
            onDone: () async {
              if (await valid(captured, version) &&
                  epoch == streamEpoch &&
                  jobId == id &&
                  waiting) {
                streamFailed(StateError('流式连接已断开'), id, captured, version);
              }
            },
          );
    } catch (e) {
      if (!await valid(captured, version) ||
          epoch != streamEpoch ||
          jobId != id) {
        return;
      }
      streamFailed(e, id, captured, version);
    }
  }

  Future<void> stopReply() async {
    final id = jobId, captured = ownerToken, version = generation;
    if (id == null || cancelling || cancelRequested) return;
    setState(() {
      cancelling = true;
      error = '';
    });
    try {
      final data = await apiPost('$lobsterApi/jobs/$id/cancel', {});
      if (!await valid(captured, version) || jobId != id) return;
      final job = sceneMap(data['job']);
      setState(() {
        cancelling = false;
        cancelRequested = job['cancel_requested'] == true;
      });
      await checkJob();
    } catch (e) {
      if (!await valid(captured, version) || jobId != id) return;
      setState(() {
        cancelling = false;
        clearOnAuthFailure(e);
        error = '停止请求未确认，可重试停止；已有回复保留。';
      });
    }
  }

  String get replyState => submitting
      ? '发送中'
      : cancelling || cancelRequested
      ? '正在请求停止…'
      : reconnecting
      ? '连接中断 · 正在续接'
      : switch (jobStatus) {
          'running' => '龙虾正在输出',
          'queued' => '等待回复',
          'cancelled' => '已停止',
          'completed' => '回复完成',
          'failed' => '回复失败',
          'send_unconfirmed' => '发送未确认',
          'interrupted' => '回复中断',
          _ => waiting ? '等待回复' : '106 · 独立对话',
        };

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || submitting || waiting) return;
    final version = generation;
    setState(() {
      submitting = true;
      error = '';
    });
    final captured = await token();
    if (!mounted || generation != version) return;
    if (captured != ownerToken) {
      resetForAccountChange();
      return;
    }
    try {
      if (sessionId == null) {
        final created = await apiPost('$lobsterApi/sessions', {
          'title': '龙虾对话',
        });
        if (!await valid(captured, version)) return;
        final s = sceneMap(created['session'] ?? created);
        sessionId = '${s['id']}';
        if (!RegExp(r'^[a-zA-Z0-9-]{16,64}$').hasMatch(sessionId!)) {
          throw const FormatException('会话创建失败');
        }
      }
      if (requestText != text || requestKey == null) {
        requestText = text;
        requestKey = cryptoSha256(
          utf8.encode(
            '$sessionId|${DateTime.now().microsecondsSinceEpoch}|$text',
          ),
        );
      }
      final data = await apiPost('$lobsterApi/sessions/$sessionId/messages', {
        'text': text,
        'idempotency_key': requestKey,
      });
      if (!await valid(captured, version)) return;
      final job = sceneMap(data['job']);
      if (job['id'] == null || '${job['id']}'.isEmpty) {
        throw const FormatException('发送结果格式异常');
      }
      setState(() {
        jobId = '${job['id']}';
        waiting = true;
        submitting = false;
        jobStatus = '${job['status'] ?? 'queued'}';
      });
      final history = await apiGet('$lobsterApi/sessions/$sessionId/messages');
      if (!await valid(captured, version)) return;
      setState(() {
        messages = sceneList(history['messages']);
      });
      await checkJob();
    } catch (e) {
      if (await valid(captured, version)) {
        if (waiting && jobId != null) {
          streamFailed(e, jobId!, captured, version, snapshot: true);
        } else {
          setState(() {
            submitting = false;
            jobStatus = 'send_unconfirmed';
            clearOnAuthFailure(e);
            error = '${friendlyError(e)}\n草稿已保留；同一内容重试会沿用请求编号，避免重复提交。';
          });
        }
      }
    }
  }

  bool get hasUnsentDraft =>
      input.text.trim().isNotEmpty &&
      (!waiting || input.text.trim() != requestText);

  Future<void> newConversation() async {
    if (submitting) return;
    if (hasUnsentDraft) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('保留当前草稿？'),
          content: const Text('新对话会清空输入框。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('清空并新建'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    generation++;
    clearJob();
    input.clear();
    setState(() {
      sessionId = null;
      jobId = null;
      messages = [];
      loading = false;
      waiting = false;
      error = '';
      requestKey = null;
      requestText = null;
    });
  }

  Future<void> showHistory() async {
    try {
      final captured = ownerToken, version = generation;
      final data = await apiGet('$lobsterApi/sessions');
      if (!await valid(captured, version) || !mounted) return;
      final rows = sceneList(data['sessions']);
      var query = '';
      final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => StatefulBuilder(
          builder: (c, update) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(c).height * .7,
              child: Column(
                children: [
                  const ListTile(title: Text('龙虾对话历史')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '搜索对话标题或预览',
                      ),
                      onChanged: (value) =>
                          update(() => query = value.toLowerCase()),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        if (rows.isEmpty)
                          const ListTile(title: Text('还没有历史对话')),
                        for (final s in rows.where(
                          (s) => '${s['title'] ?? ''} ${s['preview'] ?? ''}'
                              .toLowerCase()
                              .contains(query),
                        ))
                          ListTile(
                            title: Text('${s['title'] ?? '龙虾对话'}'),
                            subtitle: Text(
                              '${s['preview'] ?? ''}\n${sceneTime(s['updated_at'])}',
                            ),
                            onTap: () => Navigator.pop(c, '${s['id']}'),
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
      if (!await valid(captured, version) || !mounted) return;
      if (selected != null && selected != sessionId) {
        if (hasUnsentDraft) {
          final discard = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('切换对话？'),
              content: const Text('当前草稿不会发送到其他对话。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('继续编辑'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('清空并切换'),
                ),
              ],
            ),
          );
          if (discard != true || !await valid(captured, version) || !mounted) {
            return;
          }
        }
        await selectSession(selected);
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.smart_toy_outlined, color: sceneBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    connection,
                    style: const TextStyle(color: sceneMuted),
                  ),
                ),
                IconButton(
                  tooltip: '对话历史',
                  onPressed: submitting ? null : showHistory,
                  icon: const Icon(Icons.history),
                ),
                IconButton(
                  tooltip: '新对话',
                  onPressed: submitting ? null : newConversation,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              ],
            ),
          ),
          Expanded(
            child: LobsterFrameworkChat(
              key: ValueKey(generation),
              messages: messages,
              input: input,
              loading: loading,
              busy: submitting || waiting,
              onSend: send,
              emptyBuilder: (c) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.smart_toy_outlined,
                        size: 48,
                        color: sceneBlue,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '和龙虾聊一聊',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '支持 Markdown 与代码块。',
                        textAlign: TextAlign.center,
                      ),
                      if (error.isNotEmpty)
                        TextButton(onPressed: boot, child: const Text('重试连接')),
                    ],
                  ),
                ),
              ),
              status: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (waiting || submitting)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        Text(
                          replyState,
                          style: const TextStyle(
                            fontSize: 12,
                            color: sceneMuted,
                          ),
                        ),
                        if (waiting)
                          TextButton.icon(
                            onPressed: cancelling || cancelRequested
                                ? null
                                : stopReply,
                            icon: const Icon(
                              Icons.stop_circle_outlined,
                              size: 18,
                            ),
                            label: Text(
                              cancelling || cancelRequested ? '停止请求中' : '停止回复',
                            ),
                          ),
                        if (waiting && reconnecting)
                          TextButton(
                            onPressed: checkJob,
                            child: const Text('检查进度'),
                          ),
                      ],
                    ),
                  ),
                  if (error.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: const Color(0xFFFFF3DF),
                      child: Text(
                        error,
                        style: const TextStyle(color: sceneAmber),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('龙虾对话')),
            body: body,
          );
  }
}
