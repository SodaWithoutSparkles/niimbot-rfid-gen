// The full transaction log. Everything the app logged, in order.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/log.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final ScrollController _scroll = ScrollController();

  /// Paused means new lines do not drag the view back to the bottom.
  bool _following = true;

  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = log.stream.listen((_) => _maybeFollow());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _maybeFollow() {
    if (!_following || !mounted) return;
    // After the frame builds the new line, jump to the end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_following && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = log.entries;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction log'),
        actions: [
          IconButton(
            tooltip: _following ? 'Pause auto-scroll' : 'Follow new lines',
            icon: Icon(_following ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              setState(() => _following = !_following);
              if (_following) _maybeFollow();
            },
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_all),
            onPressed: entries.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: entries.join('\n')),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Log copied')),
                      );
                    }
                  },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: entries.isEmpty
                ? null
                : () {
                    log.clear();
                    setState(() {});
                  },
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('Nothing logged yet.'))
          : Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 1,
                    ),
                    child: Text(
                      entry.toString(),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['Courier New', 'monospace'],
                        fontSize: 11,
                        color: switch (entry.level) {
                          LogLevel.debug => scheme.outline,
                          LogLevel.info => scheme.onSurface,
                          LogLevel.warn => scheme.tertiary,
                          LogLevel.error => scheme.error,
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}