# clos-mini — built by hand

`clos.clab.yml` boots six switches with generated configs. **This one booted three with
nothing, and every line was typed at the CLI.**

The generated fabric proves the automation works. It does not prove the operator
understands what the automation writes. This page is the record of closing that gap.

Checklist: [`hand-build.md`](hand-build.md) — deliberately contains no commands.

---

## Result

```
$ docker exec clab-closmini-host1 ping -c3 172.16.2.10
PING 172.16.2.10 (172.16.2.10): 56 data bytes
64 bytes from 172.16.2.10: seq=0 ttl=61 time=71.476 ms
64 bytes from 172.16.2.10: seq=1 ttl=61 time=0.466 ms
64 bytes from 172.16.2.10: seq=2 ttl=61 time=0.455 ms

--- 172.16.2.10 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
```

`ttl=61` is the part that matters. Alpine sends at 64; three routers decremented it.
Nothing was bridged — leaf1, spine1 and leaf2 each made a routing decision.

```
$ sr_cli -c 'show network-instance default protocols bgp neighbor'
| default | 10.0.0.1 | FABRIC | S | 65101 | established | ipv4-unicast | [2/2/1] |
| default | 10.0.0.3 | FABRIC | S | 65102 | established | ipv4-unicast | [3/3/2] |
```

---

## Topology

```
                 spine1  AS 65001  10.255.0.1/32
                /                              \
    10.0.0.0/31                                10.0.0.2/31
              \                                /
    10.0.0.1/31                                10.0.0.3/31
          leaf1                                leaf2
        AS 65101                              AS 65102
    10.255.1.1/32                          10.255.1.2/32
    172.16.1.1/24                          172.16.2.1/24
              |                                |
          host1 172.16.1.10          host2 172.16.2.10
```

One spine, so no ECMP — that is deliberate. ECMP is already proven in `clos01`; this lab
is about typing the config, not re-proving the design.

---

## Three faults, and how each was found

Every one of these was found by reading what the box actually printed and testing one
layer at a time from the bottom up. **None of them were BGP problems.**

### 1. The commit refused

```
Error in path: .interface{.name=="ethernet-1/2"}.subinterface{.index==0}
               .ipv4.address{.ip-prefix=="10.0.0.2/31"}
  [FailedPrecondition] subnet overlaps with .interface{.name=="ethernet-1/1"}...
```

The error names `ethernet-1/1`, so that is where to look:

```
info /interface ethernet-1/1 subinterface 0 ipv4
    address 10.0.0.0/31 { }
    address 10.0.0.2/31 { }
```

`address` is a **list**. A second `set` appends; it does not replace. The fix is a
`delete`, not another `set`.

Coming from IOS, `ip address` replaces, and that assumption is what caused it. The
commit refusing the entire transaction is the reason it never reached the forwarding
plane.

### 2. Committed clean, session stayed at `active`

```
show interface ethernet-1/1
  ethernet-1/1 is up, speed 10G
  ethernet-1/1.0 is down, reason no-ip-config
    IPv4 addr : 10.0.0.1/31
```

Port up, subinterface down, reason printed. SR Linux has three independent admin-state
switches — port, subinterface, and `ipv4` — where IOS has one `no shutdown`. All three
have to be enabled, on both ends of the link.

### 3. Interfaces up, ping worked, session *still* `active`

```
ping 10.0.0.1 network-instance default -c 3
3 packets transmitted, 3 received, 0% packet loss
```

Layer 3 was fine, which ruled out addressing entirely. That left the protocol timer:
`connect-retry` defaults to 120 seconds. Setting it to 5 brought the session up in under
30.

`gen_configs.py` had already been emitting `timers connect-retry 5` from the start. That
line stopped being noise the moment the problem was hit by hand.

---

## What SR Linux does differently from IOS

| | Cisco IOS | SR Linux |
|---|---|---|
| Where an address lives | on the interface | on a **subinterface** of it |
| Setting an address twice | replaces | **appends** to a list |
| Routing table membership | automatic, global table | explicit, `network-instance` |
| Bringing it up | `no shutdown` | three admin-states: port, subinterface, ipv4 |
| Applying config | line by line, immediately | **candidate**, then `commit` |
| Policy naming | `route-map NAME` | `/routing-policy policy NAME` |
| Attaching a policy | `route-map NAME out` | `export-policy [ NAME ]` — a list |
| Pinging | `ping vrf DEFAULT 10.0.0.1` | `ping 10.0.0.1 network-instance default` |

The candidate model is the one worth arguing for. On IOS a wrong line is live and wrong
the instant you press enter. Here the box kept forwarding exactly as before while the
whole transaction was validated, then refused all of it and named the conflicting path.

---

## Per-device configuration, in order

Nine steps per device. The leaves are the same nine with different numbers.

```
# 1-3 · addresses, and the switches that turn them on
set /interface ethernet-1/1 subinterface 0 admin-state enable
set /interface ethernet-1/1 subinterface 0 ipv4 admin-state enable
set /interface ethernet-1/1 subinterface 0 ipv4 address 10.0.0.0/31
set /interface ethernet-1/2 subinterface 0 admin-state enable
set /interface ethernet-1/2 subinterface 0 ipv4 admin-state enable
set /interface ethernet-1/2 subinterface 0 ipv4 address 10.0.0.2/31
set /interface system0 subinterface 0 admin-state enable
set /interface system0 subinterface 0 ipv4 admin-state enable
set /interface system0 subinterface 0 ipv4 address 10.255.0.1/32

# 4 · nothing routes until it is in a network-instance
set /network-instance default interface ethernet-1/1.0
set /network-instance default interface ethernet-1/2.0
set /network-instance default interface system0.0

# 5 · BGP, its ASN, its router-id, its address family
set /network-instance default protocols bgp admin-state enable
set /network-instance default protocols bgp autonomous-system 65001
set /network-instance default protocols bgp router-id 10.255.0.1
set /network-instance default protocols bgp afi-safi ipv4-unicast admin-state enable

# 6 · the peer group, so policy and timers are set once
set /network-instance default protocols bgp group FABRIC admin-state enable
set /network-instance default protocols bgp group FABRIC afi-safi ipv4-unicast admin-state enable
set /network-instance default protocols bgp group FABRIC timers connect-retry 5

# 7 · neighbours — always the far end of the cable
set /network-instance default protocols bgp neighbor 10.0.0.1 admin-state enable
set /network-instance default protocols bgp neighbor 10.0.0.1 peer-group FABRIC
set /network-instance default protocols bgp neighbor 10.0.0.1 peer-as 65101
set /network-instance default protocols bgp neighbor 10.0.0.3 admin-state enable
set /network-instance default protocols bgp neighbor 10.0.0.3 peer-group FABRIC
set /network-instance default protocols bgp neighbor 10.0.0.3 peer-as 65102

# 8 · without an export policy the session comes up and advertises nothing
set /routing-policy prefix-set FABRIC prefix 10.255.0.0/16 mask-length-range 32..32
set /routing-policy prefix-set FABRIC prefix 172.16.0.0/12 mask-length-range 24..24
set /routing-policy policy EXPORT-FABRIC statement 10 match prefix-set FABRIC
set /routing-policy policy EXPORT-FABRIC statement 10 action policy-result accept
set /routing-policy policy EXPORT-FABRIC default-action policy-result reject
set /routing-policy policy IMPORT-ALL default-action policy-result accept
set /network-instance default protocols bgp group FABRIC export-policy [ EXPORT-FABRIC ]
set /network-instance default protocols bgp group FABRIC import-policy [ IMPORT-ALL ]

# 9 · the first moment any of it is real
commit stay
```

Leaf values: leaf1 is AS 65101 / `10.255.1.1/32` / `e1-1` `10.0.0.1/31` / `e1-10`
`172.16.1.1/24`, neighbour `10.0.0.0` peer-as 65001. leaf2 is AS 65102 /
`10.255.1.2/32` / `e1-1` `10.0.0.3/31` / `e1-10` `172.16.2.1/24`, neighbour `10.0.0.2`
peer-as 65001.

---

## Then read the generator

Open [`../gen_configs.py`](../gen_configs.py) and [`../fabric.yml`](../fabric.yml).

It writes exactly the above — six times, without typos, from a data model. Comparing it
against `configs/spine1.cfg` after typing the same thing by hand is the moment the
automation stops being magic.

> *"I built it by hand first, then automated it, because I wanted to know what the
> generator was doing before I trusted it."*
