# Roaming between the two routers

Xiaomi's mesh is proprietary and does not exist in OpenWrt. This setup does
the same job with standard features: the two routers are access points on the
same wired network, with the same SSID, and the clients are moved between them
with 802.11k/v/r and `usteer`. Tested with one AX3000 and one AX1800, both
wired to the same switch.

## What each piece does

| Piece | Role |
|---|---|
| 802.11k (`ieee80211k`) | the AP can ask a client which other APs it hears, and how well |
| 802.11v (`bss_transition`) | the AP can suggest that a client move to another AP (BSS transition management) |
| 802.11r (`ieee80211r`) | fast transition: a client that supports it moves without a full reauthentication |
| `usteer` | runs on every AP, shares client signal data with the other APs over the LAN and decides when to suggest a move |

All of this needs the full `wpad-mbedtls` (the `wpad-basic` variant lacks
802.11v). The images in this repository already have it, plus `usteer` and
`luci-app-usteer`.

## Access point mode

On each router: all ports in the LAN bridge (including the WAN port), an
address from the main router's DHCP, and no DHCP server, IPv6 RA or firewall of
its own. Each router also gets a fixed management address on a separate
subnet, and **the two management addresses must be different** (see the
problems below).

```sh
# all ports in the bridge, LAN as a DHCP client
uci add_list network.@device[0].ports='wan'
uci -q delete network.wan; uci -q delete network.wan6
uci set network.lan.proto='dhcp'
uci -q delete network.lan.ipaddr; uci -q delete network.lan.netmask; uci -q delete network.lan.ip6assign
# fixed management address, different on each AP (192.168.31.1, 192.168.31.2, ...)
uci set network.mgmt=interface
uci set network.mgmt.proto='static'
uci set network.mgmt.device='br-lan'
uci set network.mgmt.ipaddr='192.168.31.2'
uci set network.mgmt.netmask='255.255.255.0'
# the main router does DHCP and routing
uci set dhcp.lan.ignore='1'; uci set dhcp.lan.dhcpv6='disabled'; uci set dhcp.lan.ra='disabled'
uci commit
for s in dnsmasq odhcpd firewall; do /etc/init.d/$s disable; done
```

Check the bridge device name with `uci show network | grep br-lan` before the
`add_list`. With the firewall disabled, LuCI's *Status → Firewall* page is
empty: this is expected.

## Wi-Fi

The same SSID, password and encryption on both routers and both bands, and
**different channels** on each router. On the AX3000 `radio0` is 2.4 GHz and
`radio1` is 5 GHz; on the AX1800 it is the other way round, so pick the
channel by `band`.

```sh
for r in radio0 radio1; do
	uci set wireless.$r.country='BR'      # your country code
	uci set wireless.$r.disabled='0'
	case "$(uci get wireless.$r.band)" in
	2g) uci set wireless.$r.channel='6';  uci set wireless.$r.htmode='HE20' ;;
	5g) uci set wireless.$r.channel='36'; uci set wireless.$r.htmode='HE80' ;;
	esac
done
for i in default_radio0 default_radio1; do
	uci set wireless.$i.ssid='MyNetwork'
	uci set wireless.$i.encryption='psk2+ccmp'
	uci set wireless.$i.key='your-password'
	uci set wireless.$i.disabled='0'
	uci set wireless.$i.ieee80211k='1'
	uci set wireless.$i.bss_transition='1'
	# 802.11r: same mobility domain on every AP, keys derived from the password
	uci set wireless.$i.ieee80211r='1'
	uci set wireless.$i.mobility_domain='a4c3'
	uci set wireless.$i.ft_over_ds='0'
	uci set wireless.$i.ft_psk_generate_local='1'
done
uci commit wireless
wifi
```

The tested pair used channels 6 and 36 on one router and 1 and 149 on the
other. `mobility_domain` is any 4-digit hex value, as long as it is the same
on every AP. With `ft_psk_generate_local=1` the APs do not need to know each
other's addresses or keys. `ft_over_ds=0` makes the transition over the air,
which more clients support. Clients without 802.11r keep connecting with plain
WPA2-PSK.

## usteer

```sh
uci set usteer.@usteer[0].roam_scan_snr='-70'
uci set usteer.@usteer[0].roam_trigger_snr='-70'
uci set usteer.@usteer[0].signal_diff_threshold='8'
uci set usteer.@usteer[0].roam_kick_delay='86400000'
uci set usteer.@usteer[0].roam_scan_timeout='300000'
uci commit usteer
/etc/init.d/usteer restart
```

| Option | Value | Meaning |
|---|---|---|
| `roam_scan_snr` | -70 | below this signal, ask the client (802.11k) which APs it hears |
| `roam_trigger_snr` | -70 | below this signal, suggest a move (802.11v) |
| `signal_diff_threshold` | 8 | only to an AP at least 8 dB better |
| `roam_kick_delay` | 86400000 | 24 h: in practice the client is never disconnected (see below) |
| `roam_scan_timeout` | 300000 | after 3 scans without a result, wait 5 minutes |

The default band steering stays on: every 2 minutes it moves clients from
2.4 GHz to 5 GHz on the same AP when their signal is above -60 dBm.

Check that the two routers see each other:

```sh
ubus call usteer remote_hosts     # the other AP must be listed
ubus call usteer remote_info      # its radios (BSSIDs)
ubus call usteer get_clients      # clients and the signal each AP measured
```

## What was observed

- A phone at -73 dBm on one AP accepted the 802.11v suggestion and associated
  with the other AP within the same second (`BSS-TM-RESP status_code=0`
  followed by `AP-STA-CONNECTED` on the other router).
- A suggestion can be refused (`status_code=7`); `usteer` tries again after
  `roam_trigger_interval` (60 s), and the same phone accepted the next one.
- Some phones use 802.11r: the association shows `auth_alg=ft` instead of
  `auth_alg=open`, also between the two routers. Others always reconnect with
  `auth_alg=open`.
- The phones also move on their own (without any suggestion) when one AP is
  clearly better.

## Problems and traps

1. **Same management address on both APs: usteer ignores the other one.**
   `usteer` identifies the APs by the source address of their messages. With
   192.168.31.1 on both routers, each discarded the other's messages as its
   own, and `remote_hosts` stayed empty. Fix: a different management address
   on each AP.
2. **usteer disconnects clients that accept or ignore a suggestion.** After
   an 802.11v request, `usteer` arms a kick: if the client accepts or does not
   answer and is still connected after `roam_kick_delay` (10 s by default), it
   is deauthenticated. Only an explicit refusal cancels it. With a 24 h delay
   the APs only suggest and never drop anyone.
3. **Log noise from clients without 802.11k.** `usteer` keeps sending beacon
   requests to clients that never answer (some smart speakers, phones at the
   edge of range): hundreds of `BEACON-REQ-TX-STATUS` lines per hour.
   `roam_scan_snr=-70` and `roam_scan_timeout=300000` reduce them a lot.
4. **`nl80211: kernel reports: key addition failed`** appears right before
   every `auth_alg=ft` association. The client is authorized and traffic flows
   normally afterwards; it can be ignored.
5. **"deauthenticated due to local deauth request"** in the log usually marks a
   client dropped by the AP. It also shows up when hostapd cleans up a client
   that authenticated but never finished associating, which is harmless. A
   client that walks away shows `disconnected due to excessive missing ACKs`.
