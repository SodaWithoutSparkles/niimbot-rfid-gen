// The main screen: roll details, tag, write button, result.

import 'package:flutter/material.dart';

import '../../core/generator.dart';
import '../../core/log.dart';
import '../../core/nfc/write_plan.dart';
import '../decoder/decoder_page.dart';
import '../log/log_page.dart';
import 'roll_form.dart';
import 'tag_form.dart';
import 'write_controller.dart';
import 'write_progress_bar.dart';
import 'write_result_view.dart';

class WritePage extends StatefulWidget {
  const WritePage({super.key, this.controller});

  /// Injectable so tests can drive the same controller the screen uses.
  final WriteController? controller;

  @override
  State<WritePage> createState() => _WritePageState();
}

class _WritePageState extends State<WritePage> {
  late final WriteController _controller = widget.controller ?? WriteController();

  @override
  void initState() {
    super.initState();
    _controller.refreshAvailability();
    log.i('app ready');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Validates, generates, then asks before anything is written. Writing the
  /// config page changes the tag permanently, so the user sees the page list.
  Future<void> _startWrite() async {
    final prepared = await _controller.prepare();
    if (!mounted) return;

    if (prepared == null) {
      setState(() {});
      return;
    }

    final confirmed = await _confirm(prepared.plan);
    if (confirmed != true || !mounted) return;

    setState(() {});
    await _controller.writePlan(prepared.plan);
    if (mounted) setState(() {});
  }

  Future<bool?> _confirm(List<PagePlan> plan) {
    final pages = plan.map((p) => p.page).toList();
    final summary = pages.length <= 12
        ? pages.join(', ')
        : '${pages.take(6).join(', ')} … ${pages.skip(pages.length - 6).join(', ')}';
    final spec = getTagTypeSpec(_controller.tagType);

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Write this tag?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${plan.length} pages will be written:'),
              const SizedBox(height: 8),
              Text(summary, style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 16),
              Text(
                'Page ${spec.configPage} holds lock bits. This app only ever '
                'clears them, never sets them, so it cannot lock a page. The '
                'config byte is left as it is on the tag.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Pages ${spec.passwordPage} and ${spec.packPage} carry the '
                'password and pack bytes. Real NTAG21x hardware rejects '
                'writes to them; that is expected and comes back as a '
                'warning, not a failure.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Write tag'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final controller = _controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text('NIIMBOT NFC Writer'),
            actions: [
              IconButton(
                tooltip: 'Transaction log',
                icon: const Icon(Icons.receipt_long),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LogPage()),
                ),
              ),
            ],
          ),
          drawer: const _Menu(),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (!controller.nfcAvailable)
                const _Banner('NFC is not available on this device.'),
              if (controller.banner != null)
                _Banner(
                  controller.banner!,
                  onDismiss: controller.clearBanner,
                ),
              RollForm(controller: controller),
              const SizedBox(height: 12),
              TagForm(controller: controller),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('write-button'),
                onPressed: controller.canWrite ? _startWrite : null,
                icon: controller.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.nfc),
                label: Text(controller.busy ? 'Writing…' : 'Write tag'),
              ),
              if (controller.progress != null) ...[
                const SizedBox(height: 12),
                WriteProgressBar(progress: controller.progress!),
              ],
              if (controller.report != null) ...[
                const SizedBox(height: 12),
                WriteResultView(report: controller.report!),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu();

  void _open(BuildContext context, Widget page) {
    Navigator.of(context)
      ..pop() // close the drawer
      ..push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Center(
              child: Text(
                'NIIMBOT NFC',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Writer'),
            selected: true,
            onTap: () => Navigator.of(context).pop(),
          ),
          ListTile(
            leading: const Icon(Icons.travel_explore),
            title: const Text('Decoder'),
            onTap: () => _open(context, const DecoderPage()),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Transaction log'),
            onTap: () => _open(context, const LogPage()),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;

  const _Banner(this.message, {this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: const Icon(Icons.close),
                color: scheme.onErrorContainer,
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}