// Decoder page: read a tag and show what roll it carries.

import 'package:flutter/material.dart';

import '../../core/generator.dart';
import '../../core/log.dart';
import '../../core/nfc/commands.dart';
import '../../core/nfc/roll_reader.dart';
import '../../core/nfc/tag_session.dart';

class DecoderPage extends StatefulWidget {
  const DecoderPage({super.key});

  @override
  State<DecoderPage> createState() => _DecoderPageState();
}

class _DecoderPageState extends State<DecoderPage> {
  RollProbe? _result;
  String? _scanning;
  String? _error;

  Future<void> _scan() async {
    setState(() {
      _scanning = 'Waiting for a tag…';
      _error = null;
      _result = null;
    });

    try {
      final probe = await scanRoll();
      if (mounted) setState(() => _result = probe);
    } on NfcException catch (e) {
      log.w('decoder scan failed: $e');
      if (mounted) {
        setState(() => _error = switch (e.kind) {
              NfcErrorKind.timeout => 'No tag was presented.',
              NfcErrorKind.unavailable => 'This device has no NFC adapter.',
              _ => e.message,
            });
      }
    } finally {
      if (mounted) setState(() => _scanning = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Decoder')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _scanning == null ? _scan : null,
            icon: const Icon(Icons.nfc),
            label: Text(_scanning ?? 'Scan tag'),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            _Card(
              title: 'Scan failed',
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_result is RollNotRecognised)
            _Card(
              title: 'Not a NIIMBOT roll tag',
              child: Text((_result! as RollNotRecognised).reason),
            ),
          if (_result is RollFound) _RollCard(info: (_result! as RollFound).info),
        ],
      ),
    );
  }
}

class _RollCard extends StatelessWidget {
  final RollInfo info;

  const _RollCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final spec =
        info.tagType == null ? 'unknown tag' : getTagTypeSpec(info.tagType!).label;
    final entry = info.catalogueEntry;

    return Column(
      children: [
        _Card(
          title: 'NIIMBOT roll tag',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row('UID', formatHex(info.uid)),
              _Row('Tag', '$spec · ${info.pageCount} pages'),
              _Row('Geometry', info.geometryLabel),
              _Row('Media', info.mediaTypeLabel),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Roll',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row('Nominal quantity', '${info.nominalQuantity}'),
              _Row('Usage limit', '${info.usageLimit}'),
              _Row('Catalogue code',
                  info.barcode.isEmpty ? 'none' : info.barcode),
              if (entry != null)
                _Row('Catalogue source', 'src ${entry.sourceId}'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Usage',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row('Printed', info.isPrinted ? '${info.count}' : 'none yet'),
              _Row('Left on the roll',
                  info.rollsLeft < 0 ? '${info.rollsLeft} (over)' : '${info.rollsLeft}'),
              _Row('Capacity left', '${info.capacityLeft}'),
              _Row('Status',
                  info.capacityLeft <= 0 ? 'full' : 'ok'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}