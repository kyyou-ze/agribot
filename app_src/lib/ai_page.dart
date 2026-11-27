import 'package:flutter/material.dart';
import 'ai.dart';
import 'state.dart';
import 'widgets.dart';

/// Hapus format markdown yang kadang tetap dikeluarkan model.
String _clean(String t) =>
    t.replaceAll('**', '').replaceAll(RegExp(r'^\s*[\*\-]\s+', multiLine: true), '• ').trim();

void openAi(BuildContext c, AppState s, {String? prompt}) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => AiPage(s, initialPrompt: prompt)));

class AiPage extends StatefulWidget {
  final AppState s;
  final String? initialPrompt;
  const AiPage(this.s, {super.key, this.initialPrompt});
  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _tab = 0, _left = -1;
  bool _busy = false, _adviceBusy = false;
  String? _note, _adviceErr;
  AiAdvice? _advice;

  AppState get s => widget.s;

  @override
  void initState() {
    super.initState();
    final svc = s.aiService();
    if (svc == null) {
      _note = 'Isi URL server, kunci API, dan ID alat di Setelan > Koneksi dulu.';
      return;
    }
    svc.status().then((j) {
      if (mounted && j['enabled'] != true) setState(() => _note = 'AI belum diaktifkan di server (isi GEMINI_API_KEY).');
    }).catchError((e) {
      if (mounted) setState(() => _note = aiErr(e));
    });
    final p = widget.initialPrompt;
    if (p != null) WidgetsBinding.instance.addPostFrameCallback((_) => _send(p));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send(String text) async {
    text = text.trim();
    final svc = s.aiService();
    if (text.isEmpty || svc == null || _busy) return;
    setState(() {
      s.aiMsgs.add(AiMsg(true, text));
      _busy = true;
      _input.clear();
    });
    _toEnd();
    try {
      final a = await svc.chat(s.aiMsgs, s.aiContext());
      if (!mounted) return;
      setState(() {
        s.aiMsgs.add(AiMsg(false, a.text));
        _left = a.left;
      });
    } catch (e) {
      if (mounted) setState(() => s.aiMsgs.add(AiMsg(false, aiErr(e), error: true)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _toEnd();
  }

  Future<void> _runAdvice() async {
    final svc = s.aiService();
    if (svc == null) return;
    setState(() {
      _adviceBusy = true;
      _adviceErr = null;
    });
    try {
      final a = await svc.advice(s.aiContext());
      if (mounted) {
        setState(() {
          _advice = a;
          _left = a.left;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _adviceErr = aiErr(e));
    } finally {
      if (mounted) setState(() => _adviceBusy = false);
    }
  }

  List<(String, String)> get _quick {
    final warn = s.events.where((e) => e.kind == 2).toList();
    return [
      ('Ringkasan 24 jam', 'Buat ringkasan kondisi tanaman dan alat dalam 24 jam terakhir.'),
      ('Kenapa tanah cepat kering?', 'Kenapa tanah saya cepat kering? Apa yang bisa saya periksa atau ubah?'),
      (
        'Saran untuk tanamanku',
        s.plant.isEmpty
            ? 'Beri saran perawatan umum untuk tanaman di pot dengan alat ini.'
            : 'Beri saran perawatan untuk ${s.plant} dengan pengaturan saya sekarang.'
      ),
      if (warn.isNotEmpty)
        ('Jelaskan peringatan terakhir', 'Jelaskan kemungkinan penyebab dan langkah cek untuk peringatan ini: "${warn.first.text}".'),
    ];
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asisten AI'),
        actions: [
          IconButton(
            tooltip: 'Hapus percakapan',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => s.aiMsgs.clear()),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Tanya jawab'), icon: Icon(Icons.chat_bubble_outline)),
                  ButtonSegment(value: 1, label: Text('Saran pengaturan'), icon: Icon(Icons.tune)),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() => _tab = v.first),
              ),
            ),
          ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Panel(color: cs.errorContainer, child: Text(_note!)),
            ),
          Expanded(child: _tab == 0 ? _chat(c) : _advicePane(c)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'Saran AI bisa keliru. Pompa tetap dikendalikan aturan di alat.'
              '${_left >= 0 ? ' Sisa kuota hari ini: $_left.' : ''}',
              style: Theme.of(c).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chat(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final off = _note != null;
    return Column(children: [
      Expanded(
        child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), children: [
          if (s.aiMsgs.isEmpty)
            Panel(
              color: cs.primaryContainer.withValues(alpha: .4),
              child: const Text('Halo! Tanyakan apa saja soal tanamanmu. Saya membaca data alat (kelembaban, suhu, riwayat 24 jam, pengaturan) sebagai bahan jawaban.'),
            ),
          for (final m in s.aiMsgs)
            Align(
              alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(c).size.width * .82),
                decoration: BoxDecoration(
                  color: m.error ? cs.errorContainer : (m.user ? cs.primaryContainer : cs.surfaceContainerHigh),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SelectableText(m.user ? m.text : _clean(m.text)),
              ),
            ),
          if (_busy)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ]),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final q in _quick)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(label: Text(q.$1), onPressed: off || _busy ? null : () => _send(q.$2)),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !off,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: const InputDecoration(hintText: 'Tulis pertanyaan...', counterText: ''),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: off || _busy ? null : () => _send(_input.text), icon: const Icon(Icons.send)),
        ]),
      ),
    ]);
  }

  Widget _advicePane(BuildContext c) {
    final a = _advice, cs = Theme.of(c).colorScheme, tt = Theme.of(c).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('AI membaca data 24 jam terakhir lalu menyarankan pengaturan. Kamu yang memutuskan: tekan Terapkan bila setuju.'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _adviceBusy || _note != null ? null : _runAdvice,
              icon: _adviceBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: const Text('Analisis & beri saran'),
            ),
          ),
        ]),
      ),
      if (_adviceErr != null) Panel(color: cs.errorContainer, child: Text(_adviceErr!)),
      if (a != null) ...[
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ringkasan', style: tt.titleMedium),
          const SizedBox(height: 6),
          Text(_clean(a.summary)),
        ])),
        if (a.tips.isNotEmpty)
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Yang bisa dilakukan', style: tt.titleMedium),
            const SizedBox(height: 6),
            for (final t in a.tips) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• ${_clean(t)}')),
          ])),
        if (a.hasSuggestion)
          Panel(
            color: cs.tertiaryContainer.withValues(alpha: .5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Usulan pengaturan', style: tt.titleMedium),
              const SizedBox(height: 6),
              Text('Batas siram: ${a.minSoil ?? s.minSoil}% (sekarang ${s.minSoil}%)'),
              Text('Lama siram: ${a.runSec ?? s.run} dtk (sekarang ${s.run} dtk)'),
              Text('Jeda: ${a.waitSec ?? s.wait} dtk (sekarang ${s.wait} dtk)'),
              if (a.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_clean(a.reason), style: tt.bodySmall)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: s.connected
                      ? () {
                          s.tune(a.minSoil ?? s.minSoil, a.runSec ?? s.run, a.waitSec ?? s.wait);
                          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Pengaturan dikirim ke alat')));
                        }
                      : null,
                  child: Text(s.connected ? 'Terapkan ke alat' : 'Hubungkan ke alat untuk menerapkan'),
                ),
              ),
            ]),
          ),
      ],
    ]);
  }
}
