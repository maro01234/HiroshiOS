# HiroshiOS

画面に `Hello World from HiroshiOS!` と「田彡」型のWindowsマークを表示する、最小構成の自作OSです。
レガシーBIOS版と64ビットUEFI版の両方をビルドできます。

## 必要なもの

- `clang`
- `python3`
- `make`
- `qemu-system-i386`
- `qemu-system-x86_64`（UEFIファームウェア同梱版）

このMacでは、上記のコマンドがすでに利用できます。

## ビルドと起動

```sh
make
make run-bios
```

QEMUのウィンドウが開き、黒い画面に次の文字が表示されれば成功です。

```text
Hello World from HiroshiOS!

   +-----+-----+     >>>
   |     |     |      >>>
   |     |     |       >>>
   +-----+-----+
   |     |     |       >>>
   |     |     |      >>>
   +-----+-----+     >>>
```

BIOSの標準フォントには日本語の「田」「彡」がないため、ASCII文字だけで4枚の窓と風の線を表現しています。

QEMUを終了するには、ウィンドウを閉じるか、QEMUモニターで終了します。

自動テストも実行できます。

```sh
make test
```

## UEFI版

UEFI版をビルドしてQEMUで起動するには、次を実行します。

```sh
make uefi
make run-uefi
```

表示後にいずれかのキーを押すと、UEFIファームウェアへ戻ります。生成物は次の2つです。

- `build/HiroshiOS.efi`: Ubuntu USB上のGRUBから起動するファイル
- `build/BOOTX64.EFI`: HiroshiOS専用USBの `/EFI/BOOT/` に置くファイル

Ubuntu USBからは、`HiroshiOS.efi` をUSBの読み書き可能な領域へコピーし、Legacy版ではなくUEFI版GRUBのコンソールで次を実行します。

```grub
insmod chain
search --file --set=root /HiroshiOS.efi
chainloader /HiroshiOS.efi
boot
```

Ubuntu USBに既に存在する `/EFI/BOOT/BOOTX64.EFI` は、Ubuntuの起動に必要なので上書きしないでください。現在のUEFI版は未署名のため、Secure Bootは無効にする必要があります。

## ファイルの役割

- `boot.S`: BIOSから直接実行される16ビットのプログラム
- `uefi/boot.S`: UEFIから呼び出される64ビットのプログラム
- `uefi/message.txt`: UEFI画面へ表示する文章とASCIIアート
- `Makefile`: ビルド、QEMU起動、自動テストの手順
- `tools/elf_text_to_bin.py`: Clangのオブジェクトから512バイトの起動イメージを取り出す補助ツール
- `build/HiroshiOS.img`: `make`で生成される起動ディスクイメージ
- `build/HiroshiOS.efi`: `make`で生成されるx86-64 UEFIアプリ

## 起動の流れ

### BIOS版

1. QEMUのBIOSがディスク先頭の512バイトを物理アドレス `0x7c00` に読み込みます。
2. BIOSは末尾のシグネチャ `0x55 0xaa` を確認して、先頭の命令へジャンプします。
3. `boot.S` がレジスタとスタックを初期化します。
4. BIOSの画面出力機能（割り込み `0x10`）で1文字ずつ表示します。
5. CPUを `hlt` 命令で停止させます。

### UEFI版

1. UEFIファームウェアまたはGRUBがPE32+形式の `HiroshiOS.efi` を読み込みます。
2. UEFI System Tableから標準コンソールを取得します。
3. `OutputString` でメッセージとASCIIアートを表示します。
4. キー入力を待ち、押されたら呼び出し元へ戻ります。

## 次の一歩

この段階では、厳密には「OS本体を読み込むブートセクタ」です。次は次の順序で拡張できます。

1. キーボード入力を受け取る
2. 画面クリアや改行処理を自前で実装する
3. 32ビットのプロテクトモードへ移行する
4. C言語で書いたカーネルをディスクから読み込む
5. メモリ管理、割り込み、簡単なシェルを追加する
