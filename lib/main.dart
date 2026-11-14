import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'blockchain_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final service = BlockchainService();
  await service.init();
  runApp(MyApp(service: service));
}

class MyApp extends StatelessWidget {
  final BlockchainService service;
  const MyApp({super.key, required this.service});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Logbook Alat Lab IoT',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: DaftarPage(service: service),
      );
}

enum FilterDaftar { semua, dipinjam, selesai, milikku }

String _namaFilter(FilterDaftar f) {
  switch (f) {
    case FilterDaftar.semua:
      return 'Semua';
    case FilterDaftar.dipinjam:
      return 'Belum dikembalikan';
    case FilterDaftar.selesai:
      return 'Sudah dikembalikan';
    case FilterDaftar.milikku:
      return 'Milik wallet saya';
  }
}

class DaftarPage extends StatefulWidget {
  final BlockchainService service;
  const DaftarPage({super.key, required this.service});

  @override
  State<DaftarPage> createState() => _DaftarPageState();
}

class _DaftarPageState extends State<DaftarPage> {
  late Future<List<Pinjaman>> _data;
  FilterDaftar _filter = FilterDaftar.semua;
  StreamSubscription<dynamic>? _langganan;
  bool _live = false;
  bool _sedangMuat = false;

  @override
  void initState() {
    super.initState();
    _data = widget.service.ambilSemua();
    _mulaiPantau();
  }

  @override
  void dispose() {
    _langganan?.cancel();
    super.dispose();
  }

  /// Berlangganan event dari kontrak agar daftar terbarui otomatis.
  void _mulaiPantau() {
    try {
      _langganan = widget.service.pantauEvent().listen(
        (_) => _muatDariEvent(),
        onError: (_) {
          if (mounted) {
            setState(() {
              _live = false;
            });
          }
        },
      );
      _live = true;
    } catch (_) {
      _live = false;
    }
  }

  Future<void> _muatDariEvent() async {
    if (!mounted || _sedangMuat) return;
    _sedangMuat = true;
    try {
      await _refresh();
    } catch (_) {
      // abaikan, pengguna masih bisa refresh manual
    } finally {
      _sedangMuat = false;
    }
  }

  Future<void> _refresh() async {
    final baru = widget.service.ambilSemua();
    if (mounted) {
      setState(() {
        _data = baru;
      });
    }
    await baru;
  }

  void _pesan(String teks) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(teks),
        duration: const Duration(seconds: 10),
        showCloseIcon: true,
      ));
  }

  /// Menjalankan transaksi + menampilkan status: memproses, berhasil, gagal.
  Future<void> _jalankan(Future<String> Function() kirim) async {
    try {
      _pesan('Memproses transaksi...');
      final hash = await kirim();
      _pesan('Terkirim, menunggu konfirmasi...\n$hash');
      final ok = await widget.service.tungguKonfirmasi(hash);
      _pesan(ok
          ? 'Berhasil! Hash: $hash'
          : 'Gagal (transaksi ditolak). Hash: $hash');
      await _refresh();
    } catch (e) {
      _pesan('Gagal: $e');
    }
  }

  Future<void> _bukaTambah() async {
    final hasil = await Navigator.push<(String, String)>(
      context,
      MaterialPageRoute(builder: (_) => const TambahPage()),
    );
    if (hasil == null) return;
    await _jalankan(() => widget.service.catatPinjam(hasil.$1, hasil.$2));
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  List<Pinjaman> _terapkanFilter(List<Pinjaman> semua) {
    final saya = widget.service.alamatWallet?.toLowerCase();
    final hasil = semua.where((p) {
      switch (_filter) {
        case FilterDaftar.semua:
          return true;
        case FilterDaftar.dipinjam:
          return !p.sudahKembali;
        case FilterDaftar.selesai:
          return p.sudahKembali;
        case FilterDaftar.milikku:
          return p.pencatat.toLowerCase() == saya;
      }
    }).toList();
    return hasil.reversed.toList();
  }

  Widget _labelStatus(bool selesai) {
    final MaterialColor warna = selesai ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: warna),
      ),
      child: Text(
        selesai ? 'SELESAI' : 'DIPINJAM',
        style: TextStyle(
          color: warna.shade800,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _barFilter() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final f in FilterDaftar.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: ChoiceChip(
                  label: Text(_namaFilter(f)),
                  selected: _filter == f,
                  onSelected: (_) {
                    setState(() {
                      _filter = f;
                    });
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logbook Alat Lab IoT'),
        actions: [
          Tooltip(
            message: _live
                ? 'Pembaruan otomatis aktif'
                : 'Pembaruan otomatis tidak aktif',
            child: Icon(
              _live ? Icons.sensors : Icons.sensors_off,
              color: _live ? Colors.green : Colors.grey,
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _bukaTambah,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Pinjaman>>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Gagal memuat: ${snap.error}'),
                ),
              ]);
            }

            final semua = snap.data!;
            final belum = semua.where((p) => !p.sudahKembali).length;
            final list = _terapkanFilter(semua);

            if (semua.isEmpty) {
              return ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Belum ada data peminjaman.'),
                ),
              ]);
            }

            return Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    'Total ${semua.length} data  •  $belum dipinjam  •  '
                    '${semua.length - belum} selesai',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _barFilter(),
                Expanded(
                  child: list.isEmpty
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Tidak ada data untuk filter ini.'),
                          ),
                        ])
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final p = list[i];
                            final selesai = p.sudahKembali;
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              child: ListTile(
                                leading: Icon(
                                  selesai
                                      ? Icons.check_circle
                                      : Icons.pending_actions,
                                  color:
                                      selesai ? Colors.green : Colors.orange,
                                  size: 32,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p.namaAlat,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          decoration: selesai
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                    _labelStatus(selesai),
                                  ],
                                ),
                                subtitle: Text(
                                  'Peminjam: ${p.peminjam}\n'
                                  'Pinjam: ${_fmt(p.waktuPinjam)}'
                                  '${selesai ? '\nKembali: ${_fmt(p.waktuKembali!)}' : ''}',
                                ),
                                isThreeLine: true,
                                trailing: selesai
                                    ? null
                                    : TextButton(
                                        onPressed: () => _jalankan(() =>
                                            widget.service
                                                .catatKembali(p.id)),
                                        child: const Text('Kembalikan'),
                                      ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class TambahPage extends StatefulWidget {
  const TambahPage({super.key});

  @override
  State<TambahPage> createState() => _TambahPageState();
}

class _TambahPageState extends State<TambahPage> {
  final _formKey = GlobalKey<FormState>();
  final _alat = TextEditingController();
  final _peminjam = TextEditingController();

  @override
  void dispose() {
    _alat.dispose();
    _peminjam.dispose();
    super.dispose();
  }

  String? _wajib(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catat Peminjaman')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(children: [
            TextFormField(
              controller: _alat,
              decoration: const InputDecoration(labelText: 'Nama alat'),
              validator: _wajib,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _peminjam,
              decoration: const InputDecoration(
                  labelText: 'Peminjam (nama panggilan/kode)'),
              validator: _wajib,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    Navigator.pop(
                        context, (_alat.text.trim(), _peminjam.text.trim()));
                  }
                },
                child: const Text('Kirim Transaksi'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}