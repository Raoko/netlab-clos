# Verification — actual output from the running fabric

Captured from the live lab. Nothing here is illustrative; every block is terminal
output. Reproduce with `./verify.sh`.

Environment: containerlab on Ubuntu 24.04, Nokia SR Linux 24.10.1, 8 nodes.

---

## 1. Every node is up

```
$ docker ps --format '{{.Names}}\t{{.Status}}'
clab-clos01-host1	Up 6 hours
clab-clos01-host2	Up 6 hours
clab-clos01-leaf1	Up 6 hours
clab-clos01-leaf2	Up 6 hours
clab-clos01-leaf3	Up 6 hours
clab-clos01-leaf4	Up 6 hours
clab-clos01-spine1	Up 6 hours
clab-clos01-spine2	Up 6 hours
```

## 2. BGP — every session established

Each spine peers with all four leaves. Unique ASN per device, as RFC 7938 prescribes
for a DC underlay.

```
$ sr_cli 'show network-instance default protocols bgp neighbor'   # spine1

|  Net-Inst  |   Peer   |  Group  | Peer-AS |    State    |    Uptime     | [Rx/Active/Tx] |
| default    | 10.0.0.1 | FABRIC  | 65101   | established | 0d:0h:1m:40s  | [3/3/5]        |
| default    | 10.0.0.3 | FABRIC  | 65102   | established | 0d:5h:34m:2s  | [2/2/7]        |
| default    | 10.0.0.5 | FABRIC  | 65103   | established | 0d:5h:33m:51s | [2/2/7]        |
| default    | 10.0.0.7 | FABRIC  | 65104   | established | 0d:5h:34m:2s  | [3/3/6]        |

4 configured neighbors, 4 configured sessions are established, 0 disabled peers
```

The `10.0.0.1` session showing 1m40s is spine1 re-peering with leaf1 after the
[failure drill](failure-drill.md). The other three have run continuously for 5h34m.

## 3. ECMP in the FIB — two next-hops, one prefix

`leaf1` reaching `leaf4`'s host subnet. Both spines are installed, not just
advertised:

```
$ sr_cli 'show network-instance default route-table ipv4-unicast prefix 172.16.4.0/24'

| 172.16.4.0/24 | bgp | bgp_mgr | True | default | 170 | 10.0.0.0/31 (in | ethernet-1/1.0 |
|               |     |         |      |         |     | 10.0.1.0/31 (in |                |
```

## 4. ECMP in the data plane — both spines forward real traffic

The FIB claiming two next-hops is not proof that both are used. Six traceroutes,
watching hop 2:

```
$ for i in 1 2 3 4 5 6; do traceroute -n -q1 -m4 172.16.4.10 | sed -n '3p'; done

 2  10.0.1.0  0.991 ms      <- spine2
 2  10.0.1.0  0.934 ms      <- spine2
 2  10.0.0.0  1.252 ms      <- spine1
 2  10.0.0.0  1.248 ms      <- spine1
 2  10.0.0.0  0.297 ms      <- spine1
 2  10.0.0.0  1.263 ms      <- spine1
```

**Both spines answer hop 2.** Traffic is genuinely load-shared, not pinned to one
path with a spare sitting idle.

## 5. End-to-end

`host1` (172.16.1.10, behind leaf1) to `host2` (172.16.4.10, behind leaf4) —
leaf → spine → leaf:

```
$ ping -c4 172.16.4.10

--- 172.16.4.10 ping statistics ---
4 packets transmitted, 4 packets received, 0% packet loss
round-trip min/avg/max = 0.460/0.709/1.019 ms
```

---

## What was hard

The first deploy failed. SR Linux 24.10 rejected the BGP group policy statements:

```
Parsing error: While parsing 'export-policy': Expected '[' instead of 'EXPORT-FABRIC'
```

The platform requires **list syntax** — `export-policy [ EXPORT-FABRIC ]` — where
earlier examples show a bare name.

The fix went into `gen_configs.py`, **not** into the six rendered files under
`configs/`. Patching the artifact would have worked once and been silently undone by
the next regeneration. The data model has to stay authoritative or the pattern is
worthless. CI enforces this: the `generate` job regenerates and fails the build if
anything under `configs/` differs.

## Also proven

- [Failure drill](failure-drill.md) — one spine uplink dropped, next-hops fall 2 → 1,
  **traffic continues at 0% loss**, session recovers on restore.
