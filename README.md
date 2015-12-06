lvs01 Cookbook
==============
LVS(Linux Virtual Server) (1) を使って負荷分散サーバーを構築するクックブックです。

LVSサーバーが単一障害点(SPOF)にならない様に、KeepAlived(2)を利用してHA構成を作ります。この時必要なVIPは、SOFTLAYERのポータブルサブネットを利用します。このポータブルサブネットは、VLANに対して追加でサブネットを割り当てるもので、Private と Public の両方のアドレスをオーダーできるので、インターネットからのアクセスと、Private VLAN内のサーバー同志のアクセスに利用できます。


システム構成
------------

### HA構成
このクックブックは、次の図の赤破線枠のLVSアクティブ-スタンバイの構成を作ります。マスター状態のLVSサーバーは、VIPを保持して振り分けを実施します。マスター状態のLVSサーバーが居なくなると、スタンバイ状態のLVSサーバーが昇格してVIPを保持して振り分けをおこないます。

![LVSアクティブ-スタンバイ構成](docs/LVS_ActStby.png)


### 要求振分け方式
このクックブックで実現する要求の振分けは、DR(ダイレクト・ルーティング)です。この方式は、要求をVIPで受け、実サーバーへ要求パケットを転送します。応答は、LVSを経由せずに直接返します。(4)(5)(6)

![DR振分け方法](docs/dr_load_balance.png)


### OSファイアウォールの設定
このクックブックでは、次の様なiptablesの設定を行い、ファイアウォール不要を設定にします。
サーバー個別にiptables設定するのは技術スキル的また作業工数として難しい場合は、専用のファイアウォールを導入すれば簡単に解決できます。しかし、タイトルのヒットを支える高負荷システムでは、ファイアウォールが性能ボトルネックやサービス停止の原因となるリスクを負うことになり、専用ファイアウォールに依存する訳にはいきません。特にLVSの様な、膨大な数のアクセスを裁かなければならない機能では、一層顕著な問題となります。

![LVS-iptables](docs/iptables.png)


### カーネルパラメータの変更

このCookbookはTCPのセッション追跡テーブルのサイズを拡張します。 TCPのセッション追跡テーブルが溢れると、dmesgに次の様なメッセージを出してパケットを廃棄してしまいます。(1),(2),(3) この様な状況に陥らない様にテーブルサイズを拡大します。(7)(8)(9)

```
nf_conntrack: table full, dropping packet.
```

トラッキング数をカウント数監視(10)(12)するには、以下のコマンドで行数を数えます。

```
# cat /proc/sys/net/netfilter/nf_conntrack_count
2
```

コネクションテーブルのサイズを増やしておきます。セッションあたりスワップ対象外のメモリを約350バイトを必要(11)(12)とします。以下の設定では、2000000*350/1024/1024 = 668MB となりますから、メモリ量を考慮しながら設定値を決めます。

```lang:sysctl.conf
nf_conntrack_max=2000000
```



要件
------------

### 確認済オペレーティング・システム
- Ubuntu Linux 14.04 LTS Trusty Tahr - Minimal Install (64 bit) 
- Debian GNU/Linux 8.x jessie/Stable - Minimal Install (64 bit)
- CentOS 6.x - Minimal Install (64 bit)

### プロビジョニングスクリプト
SoftLayerのサーバー起動時に設定するプロビジョニング・スクリプトで次のURLを設定する事を前提にしてます。
- Ubuntu https://raw.githubusercontent.com/takara9/ProvisioningScript/master/ubuntu_basic_config
- CentOS6 https://raw.githubusercontent.com/takara9/ProvisioningScript/master/ubuntu_basic_config
- Debian https://raw.githubusercontent.com/takara9/ProvisioningScript/master/debian_basic_config 


### ポータブル・サブネット
https://control.softlayer.com/ -> Network -> IP Management -> Subnet -> Order IP addresses から事前にオーダーしておきます。取得したサブネットから、VIPに割り当てるIPアドレスを選んでおきます。

### リアルサーバーのIPアドレスとポート
- Webサーバー等の負荷分散対象のサーバーIPアドレス、ポート番号のCHEFのアトビュートとして設定するため、事前に確保しておく必要があります。

### リアルサーバーのループバックI/F設定
リアルサーバーのクックブックは、GitHub https://github.com/takara9/lvs-web01 にありますので、併用することで作業を効率化できます。

受けたパケットをリアルサーバーへフォワードするため、リアルサーバーでVIPのパケットを受信できる様に設定しなければなりません。Linux ディストリビューションに対応して追加する必要があります。 


**Debian/Ubuntuの場合 (/etc/network/interfaces)**

```
auto lo:1
iface lo:1 inet static
      address 161.202.132.84    <-- VIPに置き換える
      netmask 255.255.255.255
```

**CentOS6の場合 (/etc/sysconfig/network-scripts/ifcfg-lo:1)**

```
DEVICE=lo:1
IPADDR=161.202.132.84          <-- VIPのアドレスに置き換える
NETMASK=255.255.255.255
ONBOOT=yes
NAME=loopback
```


###  リアルサーバーのARP設定の変更
ARPリクエスト受信時に、ループバックに割り当てたIPで応答しない様にします。この設定を外すと、LVSをバイパスしてリアルサーバー転送される事になるので注意です。

```
net.ipv4.conf.lo.arp_ignore = 1
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
```

### その他必要なパッケージ
ポストインストール・スクリプト等からインストールされていない場合は、以下の追加パッケージとファイアウォールの設定を行っておきます。

```lang:Ubuntu/Debianの場合
# apt-get install curl ufw git
# ufw allow from 10.0.0.0/8
# ufw enable
```



アトリビュート
----------

リアルサーバーが３台以上ある場合、["real_server_ip_addrN"],["real_server_portN"]を attributes/default.rb に追加し、recipes と templates の当該する変数を追加して、振分け対象を認識できる様にします。

["persistence_timeout"]に"0"を設定すると、リアルサーバーへ順番に割り当てていきます。そして、例えば、300をセットすると、最初に降り分けられたリアルサーバーへ継続的に降られる様になり、最後にアクセスしてから300秒（5分）を超過すると、新たに振分け先を決定します。

["public_prim_subnet"]は、パブリック側のプライマリ・サブネットのサブネットとネットマスクを設定します。これはアクティとスタンバイのLVSノードが、相互のパブリック側ポートを監視できる様にするためです。


#### lvs01::default
<table>
  <tr>
    <th>Key</th>
    <th>Type</th>
    <th>Description</th>
    <th>Default</th>
  </tr>

  <tr> 
    <td>["virtual_ipaddress1"]</td>
    <td>IP address</td>
    <td>代表となるIP (VIP)</td>
    <td>NULL (必須)</td>
  </tr>

  <tr> 
    <td>["virtual_portno1"]</td>
    <td>Port Number</td>
    <td>代表となるポート番号</td>
    <td>NULL (必須)</td>
  </tr>

  <tr> 
    <td>["persistence_timeout"]</td>
    <td>Number</td>
    <td>振り分けを固執する秒数</td>
    <td>0</td>
  </tr>

  <tr> 
    <td>["public_prim_subnet"]</td>
    <td>Number</td>
    <td>LVS nodes が所属するサブネットとマスク</td>
    <td>161.202.142.192/28</td>
  </tr>

  <tr> 
    <td>["real_server_ip_addr1"]</td>
    <td>IP address</td>
    <td>実サーバーのIPアドレス</td>
    <td>NULL (必須)</td>
  </tr>

  <tr> 
    <td>["real_server_port1"]</td>
    <td>Port Number</td>
    <td>実サーバーのポート番号</td>
    <td>NULL (必須)</td>
  </tr>

  <tr> 
    <td>["real_server_ip_addr2"]</td>
    <td>IP address</td>
    <td>実サーバーのIPアドレス</td>
    <td>NULL (必須)</td>
  </tr>

  <tr> 
    <td>["real_server_port2"]</td>
    <td>Port Number</td>
    <td>実サーバーのポート番号</td>
    <td>NULL (必須)</td>
  </tr>
</table>




使い方
------------

以下の順番でコマンドを実行して、サーバーにクックブックを置きます。

```
# curl -L https://www.opscode.com/chef/install.sh | bash
# knife cookbook create dummy -o /var/chef/cookbooks
# cd /var/chef/cookbooks
# git clone https://github.com/takara9/lvs01
```
アトリビュートを環境に合わせて編集して、以下のコマンドでサーバーに適用します。

```
# chef-solo -o lvs01
```

### 動作確認
次のipvsadm(13)コマンドで、VIPと実サーバーがリストされていれば、ひとまず動作している事になります。

```
root@lvs1:/var/chef/cookbooks# ipvsadm -Ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  161.202.132.84:80 rr
  -> 161.202.142.204:80           Route   1      134        0         
  -> 161.202.142.206:80           Route   1      135        0     
```




参考資料
------------

1. The Linux Virtual Server Project http://www.linuxvirtualserver.org
2. Keepalived for Linux http://www.keepalived.org/
3. ソフトレイヤー活用ガイド 4.2 サーバーを替えても同じIPアドレスを継続するには？ https://www.change-makers.jp/post/10345
4. LVS-HOWTO http://www.austintek.com/LVS/LVS-HOWTO/HOWTO
5. RedHat Enterprise Linux 6 第3章 Load Balancer Add-On の設定 https://access.redhat.com/documentation/ja-JP/Red_Hat_Enterprise_Linux/6/html/Load_Balancer_Administration/ch-lvs-setup-VSA.html
6. RedHat Enterprise Linux 7 ロードバランサーの管理 https://access.redhat.com/documentation/ja-JP/Red_Hat_Enterprise_Linux/7/html/Load_Balancer_Administration/index.html
7. Resolving “nf_conntrack: table full, dropping packet.” flood message in dmesg Linux kernel log (http://pc-freak.net/blog/resolving-nf_conntrack-table-full-dropping-packet-flood-message-in-dmesg-linux-kernel-log/)
8. あなたの大量配信サーバ、ip_conntrack溢れていませんか？(http://www.e-agency.co.jp/column/20121225.html)
9. DMMツチノコブログ netfilterモジュール (http://tsuchinoko.dmmlabs.com/?p=1016)
10. iptables (http://www.iptables.info/en/connection-state.html)
11. 3.7 ip_conntrack: maximum limit of XXX entries exceeded (http://www.netfilter.org/documentation/FAQ/netfilter-faq-3.html#ss3.7)
12. Kernel Documentation (https://www.kernel.org/doc/Documentation/networking/nf_conntrack-sysctl.txt)
13. ipvsadm(8) -Linux man page http://linux.die.net/man/8/ipvsadm
14. keepalived.conf(5) - Linux man page http://linux.die.net/man/5/keepalived.conf




License and Authors
-------------------

Authors: Maho Takara

License: see LICENCE file


