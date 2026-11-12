// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LogbookAlat {
    struct Pinjaman {
        string namaAlat;
        string peminjam;      // nama panggilan/kode, bukan NIM
        uint256 waktuPinjam;
        uint256 waktuKembali; // 0 = belum dikembalikan
        address pencatat;
    }

    Pinjaman[] private daftar;

    event AlatDipinjam(uint256 id, string namaAlat, address pencatat);
    event AlatDikembalikan(uint256 id);

    function catatPinjam(string calldata namaAlat, string calldata peminjam) external {
        require(bytes(namaAlat).length > 0, "Nama alat tidak boleh kosong");
        require(bytes(peminjam).length > 0, "Peminjam tidak boleh kosong");
        daftar.push(Pinjaman(namaAlat, peminjam, block.timestamp, 0, msg.sender));
        emit AlatDipinjam(daftar.length - 1, namaAlat, msg.sender);
    }

    function catatKembali(uint256 id) external {
        require(id < daftar.length, "Data tidak ada");
        require(daftar[id].pencatat == msg.sender, "Bukan pencatat");
        require(daftar[id].waktuKembali == 0, "Sudah dikembalikan");
        daftar[id].waktuKembali = block.timestamp;
        emit AlatDikembalikan(id);
    }

    function jumlahPinjaman() external view returns (uint256) {
        return daftar.length;
    }

    function ambilPinjaman(uint256 id) external view
        returns (string memory, string memory, uint256, uint256, address)
    {
        require(id < daftar.length, "Data tidak ada");
        Pinjaman memory p = daftar[id];
        return (p.namaAlat, p.peminjam, p.waktuPinjam, p.waktuKembali, p.pencatat);
    }
}