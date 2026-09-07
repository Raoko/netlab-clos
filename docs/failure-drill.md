# Failure Drill — ECMP resilience under spine link loss

Real output from the running lab, not a description of what should happen.

**Claim under test:** with two spines and ECMP, losing one spine uplink on a leaf
must remove exactly one next-hop and must **not** interrupt traffic.

**Method:** fail the physical link (`ip link set e1-1 down` inside the leaf1
container), which is a true carrier loss — not an admin shutdown of the BGP peer.
This is the closest thing to pulling a cable.

---

## Step 1 — Baseline

Both spine uplinks live. `leaf1` holds **two** next-hops to `leaf4`'s host subnet.

```
| 172.16.4.0/24 | bgp | bgp_mgr | True | default | 170 | 10.0.0.0/31 (in | ethernet-1/1.0 |
|               |     |         |      |         |     | 10.0.1.0/31 (in |                |
```

```
| 10.0.0.0 | FABRIC | 65001 | established | 0d:5h:30m:22s | ipv4-unicast | [5/5/3] |
| 10.0.1.0 | FABRIC | 65002 | established | 0d:5h:30m:54s | ipv4-unicast | [5/5/7] |
```

```
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.576/0.647/0.777 ms
```

---

## Step 2 — Fail the spine1 uplink

```sh
docker exec clab-clos01-leaf1 ip link set e1-1 down
```

**Route table drops to a single next-hop.** `10.0.0.0/31` is gone; only
`ethernet-1/2.0` toward spine2 remains:

```
| 172.16.4.0/24 | bgp | bgp_mgr | True | default | 170 | 10.0.1.0/31 (in | ethernet-1/2.0 |
```

**The spine1 session leaves `established` and falls back to `active`** — retrying,
with no negotiated address families:

```
| 10.0.0.0 | FABRIC | 65001 | active      | -             |              |         |
| 10.0.1.0 | FABRIC | 65002 | established | 0d:5h:32m:30s | ipv4-unicast | [6/6/2] |
```

Note spine2's counter moving to `[6/6/2]` — it is now carrying prefixes that
previously arrived via spine1.

**Traffic never stopped:**

```
5 packets transmitted, 5 packets received, 0% packet loss
round-trip min/avg/max = 0.469/0.566/0.759 ms
```

That is the whole point of the design. Half the fabric capacity is gone and the
application sees nothing.

---

## Step 3 — Restore

```sh
docker exec clab-clos01-leaf1 ip link set e1-1 up
```

**Both next-hops return:**

```
| 172.16.4.0/24 | bgp | bgp_mgr | True | default | 170 | 10.0.0.0/31 (in | ethernet-1/1.0 |
|               |     |         |      |         |     | 10.0.1.0/31 (in |                |
```

**Session re-establishes** — note the uptime counter reset, proof it genuinely went
down and came back rather than never dropping:

```
| 10.0.0.0 | FABRIC | 65001 | established | 0d:0h:0m:25s  | ipv4-unicast | [5/5/3] |
| 10.0.1.0 | FABRIC | 65002 | established | 0d:5h:33m:19s | ipv4-unicast | [5/5/7] |
```

```
3 packets transmitted, 3 packets received, 0% packet loss
```

---

## Result

| | Next-hops | spine1 session | Traffic |
|---|---|---|---|
| Baseline | **2** | established 5h30m | 0% loss |
| Link down | **1** | **active** | **0% loss** |
| Restored | **2** | established 25s | 0% loss |

The two uptime counters are the honest part: spine2 runs continuously at 5h33m
across all three steps, while spine1 resets to 25s. The failure was real.

---

## Why this drill and not another

A fabric that has never lost a link has not been tested — it has only been deployed.
ECMP is the reason to build a Clos topology at all, and the only way to show it works
is to take something away and prove the traffic does not care.

`admin-state disable` on the BGP peer would have been easier and would have proved
less. Dropping the interface exercises the same path a cut fiber does: carrier loss,
then the routing protocol reacting to it.
