# D330 Linux Mintログイン時に画面がバックライトのみになる問題とその修正

## TL;DR

- Lenovo IdeaPad D330-10IGM + Linux Mint 22.3（Cinnamon）で、**ログイン画面（lightdm greeter）からデスクトップへ入る瞬間に、画面がバックライトのみ（表示なし）になることがある**問題を切り分けた。
- 原因は、[サスペンド/DPMS復帰時の黒画面バグ](https://github.com/v2-2v/linux_lenovod330)（本機種のDSIパネル固有の既知の不具合）と**同じ根本原因**で、トリガーが異なるだけだった。ログイン画面はカーネル/BIOSが渡した状態（`fastset`）をそのまま使うため安全だが、Cinnamonのウィンドウマネージャ（muffin）がセッション開始時に画面を自動回転（縦→横）させる際に、初めて本物のi915側DSI再初期化コードが走り、確率的に失敗することがある。
- 対策として、**ログイン画面の時点で先に同じ回転をかけておく**（lightdmの`display-setup-script`フックを使用）ことで、デスクトップ移行時の「状態変化」＝モードセット自体をなくす方向で緩和を試みた。ログイン画面が横向きになることは確認済みだが、発生確率自体が下がったかどうかの統計的な検証は今後の課題。
- **[linux_lenovod330](https://github.com/v2-2v/linux_lenovod330)リポジトリのDKMSパッチ（サスペンド/DPMS用）とは独立**しており、あちらを導入していないストックカーネルでも本問題は発生し、本修正は単独で有効。

---

## 環境

- 機種: Lenovo IdeaPad D330-10IGM
- OS: Linux Mint 22.3（Cinnamon、X11、lightdm + lightdm-gtk-greeter）
- カーネル: `7.0.0-30-generic`（ストック、無改造）
- GPU: Intel Gemini Lake, UHD Graphics 600
- 内蔵ディスプレイ: DSI-1接続、物理パネルモード`800x1280@60`（ネイティブ縦）

## 症状

- ログイン画面（lightdm greeter）は正常に表示される（**縦向き**）。
- ログインしてCinnamonデスクトップに入る瞬間、画面が**バックライトのみ**になり、表示が出ないことがある（毎回ではなく確率的）。
- 発生した場合、再ログイン・再起動すれば直ることが多い（[サスペンド復帰バグ](https://github.com/v2-2v/linux_lenovod330)と同様、再起動＝真の電源再投入経路は確実に成功する）。

## 原因の切り分け

まず、ログイン画面とデスクトップとで**画面の向きが違う**ことに着目した（ログイン画面＝縦、デスクトップ＝横）。

```bash
$ xrandr --verbose
DSI1 connected primary 1280x800+0+0 (0x47) right (normal left inverted right x axis y axis) 135mm x 216mm
...
	panel orientation: Right Side Up
		supported: Normal, Upside Down, Left Side Up, Right Side Up
...
  800x1280 (0x47) 78.500MHz -HSync -VSync *current +preferred
```

ここで重要なのは`panel orientation: Right Side Up`という**カーネル（i915）のDRMコネクタプロパティ**の存在である。これはVBTに埋め込まれた「このパネルは物理的に90度回転して実装されている」という情報で、ネイティブモードは`800x1280`（縦）のまま、ディスプレイサーバ側がこのプロパティを見て自動的に補正回転をかけることを想定した仕組みである。

切り分けのため、以下を確認した：

- `~/.config/monitors.xml`：存在しない（保存済みの画面配置設定が原因ではない）
- `/etc/X11/xorg.conf.d/`：回転関連の静的設定は無し
- `org.cinnamon.settings-daemon.peripherals.touchscreen orientation-lock`：`true`（加速度センサーによる動的な自動回転ではない）
- Xorgログ：`intel_drv.so`（レガシーintelドライバ）がロードされている

**結論**：`panel orientation`プロパティを実際に読んで自動補正回転をかけているのは、**Cinnamonのウィンドウマネージャmuffin（Mutter系）自身**であり、これはセッション開始時に一度だけ発生する。一方、lightdmのgreeter（`lightdm-gtk-greeter`、単純なX11クライアントでMutter系コンポジタではない）はこの補正機能を持たないため、ネイティブの縦のまま表示される。

つまり：

```
[greeter起動]                         [ログイン→Cinnamon起動]
状態: 800x1280、無回転                状態: 800x1280、無回転
（BIOSが渡したfastset状態のまま）  →  muffinがxrandr --rotate rightを発行
                                        ↓
                                   実モードセット発生
                                        ↓
                                   fastsetが無効化され、
                                   i915自身のDSI再初期化コードが
                                   初めて実行される
                                        ↓
                                   確率的に失敗（既知のバグ）
```

これは[サスペンド/DPMS復帰時の黒画面バグ](https://github.com/v2-2v/linux_lenovod330)と**全く同じ経路**（i915の`intel_dsi_disable()`→`intel_dsi_pre_enable()`という、パネル電源/リセットGPIOを再操作しDSIプロトコルを再確立する処理）であり、トリガーが「サスペンド復帰」ではなく「ログイン直後の初回モードセット（回転変更）」だった、というだけである。

## 修正方法

根本のi915側バグ自体は直せない（[別リポジトリ](https://github.com/v2-2v/linux_lenovod330)の結論と同じ）ため、**トリガーとなるモードセット自体を起こさない**方向で対策する。具体的には、lightdmのgreeterが起動した時点で、Cinnamonが後で行うのと同じ回転を先にかけておき、ログイン画面からデスクトップまで**状態を一貫させる**（＝ログイン時にモードセットが発生しないようにする）。

`display-setup-script`は、greeter用のXサーバーが起動した直後、greeterの描画が始まる**前**にroot権限で実行される。ここで先に`xrandr --rotate right`を実行しておくことで、greeter自体が最初から横向きで表示されるようになる。

### インストール（コピペで完結）

```bash
git clone https://github.com/v2-2v/linux_lenovod330-linuxmint-login-backlight-only-fix.git
cd linux_lenovod330-linuxmint-login-backlight-only-fix

sudo install -m 755 scripts/d330-lightdm-rotate.sh /etc/lightdm/d330-lightdm-rotate.sh
sudo install -m 644 scripts/90-d330-rotate.conf /etc/lightdm/lightdm.conf.d/90-d330-rotate.conf

sudo reboot
```

`scripts/d330-lightdm-rotate.sh`の中身:

```sh
#!/bin/sh
# D330: rotate the greeter's Xorg output to match what Cinnamon (muffin)
# will apply anyway via the kernel's "panel orientation: Right Side Up"
# connector property. Without this, the greeter shows native portrait and
# Cinnamon rotates on session start, which forces a real DSI modeset --
# the same unreliable re-init path as DPMS/suspend.
xrandr --output DSI1 --rotate right
```

`scripts/90-d330-rotate.conf`の中身:

```ini
[Seat:*]
display-setup-script=/etc/lightdm/d330-lightdm-rotate.sh
```

再起動すると、lightdmの再起動（ログアウト状態になる、既存セッションは失われる）を伴うので注意。

### 取り除く場合

```bash
sudo rm -f /etc/lightdm/d330-lightdm-rotate.sh /etc/lightdm/lightdm.conf.d/90-d330-rotate.conf
sudo reboot
```

## 検証状況

- ✅ **確認済み**：上記適用後、ログイン画面（greeter）が横向きで表示されるようになった。
- ❓ **未検証**：ログイン→デスクトップ移行時のモードセット自体（あるいはそれに類する処理）がまだ内部的に発生していないか、発生していてもgreeterと状態が同一なため実際に失敗しにくくなっているか、という点は、少数回の試行だけでは判断できない。[サスペンド復帰バグの調査](https://github.com/v2-2v/linux_lenovod330)で確立された知見（「確率的なハードウェアレベルのマージン不足」であり、成功率は条件次第で大きくばらつく）を踏まえると、統計的な確認には多数回のログイン試行が必要。

## `linux_lenovod330`リポジトリとの関係

同じ機種・同じ根本原因（DSIパネルの電源/初期化シーケンスが確率的に失敗する、というGeminiLake + i915 + VBT駆動DSIパネルの構造的な弱点）を共有しているが、対策のアプローチは別物：

| | 対象トリガー | 対策 |
|---|---|---|
| [linux_lenovod330](https://github.com/v2-2v/linux_lenovod330) | サスペンド復帰・DPMS off/on | カーネルパッチでバックライトGPIOを独立制御し、そもそもパネル電源サイクルを踏ませない |
| 本ドキュメント | ログイン→デスクトップ移行時の自動回転 | greeter側の回転をデスクトップ側と揃え、モードセット自体を発生させない |

いずれも「バグそのものを直す」のではなく「バグの発火条件（トリガー）を回避する」というアプローチである点は共通している。**本修正はカーネル無改造のストック環境でも単独で有効**であり、`linux_lenovod330`のDKMSパッチと併用しても問題ない。

## 今後の課題

- 数十回単位のログイン試行を行い、対策前後で黒画面の発生率が実際に下がったかを統計的に確認する。
- 対策後も発生する場合、`drm.debug=0x1e`を有効にしてログイン時のログを取得し、`Starting MIPI sequence`が実際に出ているか（＝モードセットが依然として発生しているか）を確認する。
- 可能であれば、lightdm-gtk-greeter以外の、`panel orientation`プロパティを自動的に尊重するgreeter（Mutter/GNOME Shellベースのgreeter等）への切り替えも根本対策として検討の余地がある。

（本ドキュメントは個人の調査記録であり、Lenovo/Intelの公式見解ではありません。）
