import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'state.dart';
import 'widgets.dart';

/// Pemasangan alat baru, 3 langkah. Alat dideteksi otomatis; pengguna hanya mengisi WiFi rumah.
class SetupPage extends StatefulWidget {
  final AppState s;
  const SetupPage(this.s, {super.key});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  late final TextEditingController _ssid, _pass;
  Timer? _poll;
  bool _found = false, _sending = false, _waiting = false, _hide = true;
  String? _err;

  AppState get s => widget.s;

  @override
  void initState() {
    super.initState();
    _ssid = TextEditingController(text: s.ssid);
    _pass = TextEditingController(text: s.pass);
    _probe();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _probe());
  }

  @override
  void dispose() {
    _poll?.cancel();
    s.cancelWait();
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    if (_found || _sending || _waiting) return;
    final f = await s.probeSetup();
    if (mounted && f) setState(() => _found = true);
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _sending = true;
      _err = null;
    });
    final err = await s.provisionFromWizard(_ssid.text.trim(), _pass.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _sending = false;
        _err = err;
      });
      return;
    }
    setState(() {
      _sending = false;
      _waiting = true;
    });
    final ok = await s.waitForDevice();
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Alat terpasang dan terhubung 🎉')));
      nav.pop(true);
    } else {
      setState(() {
        _waiting = false;
        _found = false;
        _err = 'Alat belum terhubung. Periksa nama & sandi WiFi, lalu sambungkan HP lagi ke "AkarSiaga-XXXX" dan ulangi.';
      });
    }
  }

  Widget _step(BuildContext c, int n, String title, Widget body, {bool done = false, bool dim = false}) {
    final cs = Theme.of(c).colorScheme;
    return Opacity(
      opacity: dim ? .5 : 1,
      child: Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: done ? cs.primary : cs.primaryContainer,
              child: done
                  ? Icon(Icons.check, size: 18, color: cs.onPrimary)
                  : Text('$n', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          body,
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme, tt = Theme.of(c).textTheme;
    final canSend = _found && !_sending && !_waiting && _ssid.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Pasang alat baru')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          _step(c, 1, 'Nyalakan alat', const Text('Colokkan alat ke listrik. Tunggu bunyi bip, lalu WiFi "AkarSiaga-XXXX" akan muncul. Bila alat sudah pernah dipasang, tahan tombolnya lebih dari 3 detik.'), done: true),
          _step(
            c,
            2,
            'Sambungkan HP ke WiFi alat',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Buka pengaturan WiFi HP, pilih "AkarSiaga-XXXX". Jika HP bilang "tidak ada internet", pilih Tetap terhubung.'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .6), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Text('Sandi: ', style: tt.bodySmall),
                  Expanded(child: SelectableText(setupPassword, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  IconButton(
                    tooltip: 'Salin sandi',
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: setupPassword));
                      ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Sandi disalin')));
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                if (_found)
                  Icon(Icons.check_circle, color: cs.primary)
                else
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _found ? 'Alat terdeteksi${s.devId.isNotEmpty ? ' (${s.devId})' : ''}' : 'Mencari alat... (otomatis)',
                    style: TextStyle(fontWeight: FontWeight.w600, color: _found ? cs.primary : cs.onSurface),
                  ),
                ),
              ]),
            ]),
            done: _found,
          ),
          _step(
            c,
            3,
            'WiFi rumah',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: _ssid, onChanged: (_) => setState(() {}), decoration: dec(c, label: 'Nama WiFi (2,4 GHz)')),
              const SizedBox(height: 10),
              TextField(
                controller: _pass,
                obscureText: _hide,
                decoration: dec(c, label: 'Sandi WiFi').copyWith(
                  suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Icon(s.serverReady ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 18, color: s.serverReady ? cs.primary : cs.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.serverReady ? 'Cloud aktif (${s.serverHost}): bisa dipantau dari mana saja.' : 'Tanpa Cloud: alat hanya bisa dipantau di WiFi yang sama.',
                    style: tt.bodySmall,
                  ),
                ),
              ]),
              if (!s.serverReady)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text('Tempel kode sambung'),
                    onPressed: () async {
                      final m = await s.pasteCode();
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
                      }
                    },
                  ),
                ),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_err!, style: TextStyle(color: cs.error)),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canSend ? _send : null,
                  icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                  label: Text(_found ? 'Hubungkan alat' : 'Menunggu alat...'),
                ),
              ),
            ]),
            dim: !_found && !_waiting,
          ),
          if (_waiting)
            Panel(
              color: cs.primaryContainer,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: 14),
                  Expanded(child: Text('Alat sedang masuk WiFi...', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer))),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Sekarang sambungkan HP kembali ke WiFi rumah${s.serverReady ? ' (atau cukup pakai data seluler)' : ''}. Aplikasi akan terhubung sendiri, ±20 detik.',
                  style: TextStyle(color: cs.onPrimaryContainer),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      s.cancelWait();
                      setState(() => _waiting = false);
                    },
                    child: const Text('Batal'),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
