import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/log_collector.dart';

class DebugLogsDialog extends StatefulWidget {
  const DebugLogsDialog({super.key});

  @override
  State<DebugLogsDialog> createState() => _DebugLogsDialogState();
}

class _DebugLogsDialogState extends State<DebugLogsDialog> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    LogCollector.instance.onLog = _onNewLog;
    // 自动滚到最底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    LogCollector.instance.onLog = null;
    _scrollController.dispose();
    super.dispose();
  }

  void _onNewLog() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final logs = LogCollector.instance.logs;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.terminal, color: colorScheme.primary),
          const SizedBox(width: 12),
          const Text('调试诊断日志'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: logs.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无运行日志',
                          style: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: logs.length,
                        itemBuilder: (context, idx) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: SelectableText(
                              logs[idx],
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            LogCollector.instance.clear();
            setState(() {});
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('清空'),
        ),
        TextButton.icon(
          onPressed: () {
            final allLogs = logs.join('\n');
            Clipboard.setData(ClipboardData(text: allLogs));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('调试日志已复制到剪贴板！')),
            );
          },
          icon: const Icon(Icons.copy),
          label: const Text('复制全部'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
