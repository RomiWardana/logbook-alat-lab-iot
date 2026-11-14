import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:reown_appkit/reown_appkit.dart' show ReownAppKitModal, ReownAppKitModalNetworks;
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

class Pinjaman {
  final int id;
  final String namaAlat;
  final String peminjam;
  final DateTime waktuPinjam;
  final DateTime? waktuKembali;
  final String pencatat;

  Pinjaman({
    required this.id,
    required this.namaAlat,
    required this.peminjam,
    required this.waktuPinjam,
    required this.waktuKembali,
    required this.pencatat,
  });

  bool get sudahKembali => waktuKembali != null;
}

/// Membaca data lewat RPC (tanpa wallet) dan menulis data lewat wallet
/// yang tersambung via WalletConnect/Reown. Private key tidak ada di aplikasi.
class BlockchainService {
  late final Web3Client _client;
  late final DeployedContract _contract;
  ReownAppKitModal? _modal;

  void pasangModal(ReownAppKitModal modal) {
    _modal = modal;
  }

  bool get terhubung => alamatWallet != null;

  /// Alamat wallet yang sedang tersambung (huruf kecil), atau null.
  String? get alamatWallet {
    final m = _modal;
    if (m == null || !m.isConnected) return null;
    final sesi = m.session;
    final jaringan = m.selectedChain;
    if (sesi == null || jaringan == null) return null;
    final ns = ReownAppKitModalNetworks.getNamespaceForChainId(
        jaringan.chainId);
    return sesi.getAddress(ns)?.toLowerCase();
  }

  /// true jika wallet berada di jaringan yang diharapkan (Sepolia).
  bool get jaringanBenar {
    final jaringan = _modal?.selectedChain;
    if (jaringan == null) return false;
    return jaringan.chainId.endsWith(dotenv.env['CHAIN_ID']!);
  }

  Future<void> init() async {
    _client = Web3Client(dotenv.env['RPC_URL']!, http.Client());

    final abi = await rootBundle.loadString('assets/abi/LogbookAlat.json');
    _contract = DeployedContract(
      ContractAbi.fromJson(abi, 'LogbookAlat'),
      EthereumAddress.fromHex(dotenv.env['CONTRACT_ADDRESS']!),
    );
  }

  Future<List<Pinjaman>> ambilSemua() async {
    final res = await _client.call(
      contract: _contract,
      function: _contract.function('jumlahPinjaman'),
      params: [],
    );
    final jumlah = (res.first as BigInt).toInt();

    final hasil = <Pinjaman>[];
    for (var i = 0; i < jumlah; i++) {
      final r = await _client.call(
        contract: _contract,
        function: _contract.function('ambilPinjaman'),
        params: [BigInt.from(i)],
      );
      final kembali = (r[3] as BigInt).toInt();
      hasil.add(Pinjaman(
        id: i,
        namaAlat: r[0] as String,
        peminjam: r[1] as String,
        waktuPinjam: DateTime.fromMillisecondsSinceEpoch(
            (r[2] as BigInt).toInt() * 1000),
        waktuKembali: kembali == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(kembali * 1000),
        pencatat: (r[4] as EthereumAddress).with0x,
      ));
    }
    return hasil;
  }

  /// Mengirim transaksi lewat wallet. Pengguna menyetujuinya di MetaMask.
  Future<String> _kirim(String fungsi, List<dynamic> params) async {
    final m = _modal;
    final alamat = alamatWallet;
    if (m == null || alamat == null) {
      throw Exception('Wallet belum terhubung. Tekan Connect Wallet dulu.');
    }
    if (!jaringanBenar) {
      throw Exception('Pindahkan wallet ke jaringan Sepolia.');
    }

    final permintaan = m.requestWriteContract(
      topic: m.session!.topic,
      chainId: m.selectedChain!.chainId,
      deployedContract: _contract,
      functionName: fungsi,
      transaction: Transaction(from: EthereumAddress.fromHex(alamat)),
      parameters: params,
    );
    // Membuka aplikasi MetaMask supaya pengguna bisa menyetujui transaksi.
    m.launchConnectedWallet();

    final hasil = await permintaan;
    return hasil.toString();
  }

  Future<String> catatPinjam(String namaAlat, String peminjam) =>
      _kirim('catatPinjam', [namaAlat, peminjam]);

  Future<String> catatKembali(int id) =>
      _kirim('catatKembali', [BigInt.from(id)]);

  /// Menunggu transaksi masuk blok. true = berhasil, false = gagal (revert).
  Future<bool> tungguKonfirmasi(String hash) async {
    for (var i = 0; i < 40; i++) {
      final receipt = await _client.getTransactionReceipt(hash);
      if (receipt != null) return receipt.status ?? false;
      await Future.delayed(const Duration(seconds: 3));
    }
    throw Exception('Waktu tunggu konfirmasi habis');
  }

  /// Mendengarkan event AlatDipinjam dan AlatDikembalikan dari kontrak.
  Stream<FilterEvent> pantauEvent() {
    final ctrl = StreamController<FilterEvent>();
    final langganan = <StreamSubscription<FilterEvent>>[];

    for (final nama in ['AlatDipinjam', 'AlatDikembalikan']) {
      final stream = _client.events(
        FilterOptions.events(
          contract: _contract,
          event: _contract.event(nama),
        ),
      );
      langganan.add(stream.listen(ctrl.add, onError: ctrl.addError));
    }

    ctrl.onCancel = () async {
      for (final s in langganan) {
        await s.cancel();
      }
    };
    return ctrl.stream;
  }
}