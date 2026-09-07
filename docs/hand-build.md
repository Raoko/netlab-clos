# clos-mini — build it by hand

`clos.clab.yml` boots six switches with generated configs. **This one boots three with
nothing.**

The generated fabric proves the automation works. It does not prove the operator
understands what the automation writes. **This topology exists to close that gap.**

Rule: **every command is typed at the CLI.** No startup-configs, no generator, no
copying from `configs/`.

---

## Topology

```
                 spine1
                 AS 65001
                /        \
    10.0.0.0/31          10.0.0.2/31
              /            \
          leaf1            leaf2
        AS 65101          AS 65102
     172.16.1.0/24     172.16.2.0/24
            |                |
         host1            host2
      172.16.1.10       172.16.2.10
```

One spine, so **no ECMP** — that is fine. ECMP is already proven in `clos01`. This lab
is about typing the config, not re-proving the design.

---

## Addressing

/31s on point-to-point links (RFC 3021). Spine takes the even address.

| Link | Spine side | Leaf side |
|---|---|---|
| spine1 `e1-1` ↔ leaf1 `e1-1` | `10.0.0.0/31` | `10.0.0.1/31` |
| spine1 `e1-2` ↔ leaf2 `e1-1` | `10.0.0.2/31` | `10.0.0.3/31` |

| Device | ASN | Loopback | Host subnet |
|---|---|---|---|
| spine1 | 65001 | `10.255.0.1/32` | — |
| leaf1 | 65101 | `10.255.1.1/32` | `172.16.1.0/24`, gateway `.1` on `e1-10` |
| leaf2 | 65102 | `10.255.1.2/32` | `172.16.2.0/24`, gateway `.1` on `e1-10` |

---

## Run it

```sh
sudo containerlab deploy -t clos-mini.clab.yml
sudo docker exec -it clab-closmini-spine1 sr_cli
```

Runs alongside `clos01` — different lab name, different container names.

Tear down and start over as often as you like:

```sh
sudo containerlab destroy -t clos-mini.clab.yml --cleanup
```

---

## The checklist

Per device, in this order. **No commands here on purpose** — work them out from
`sr_cli` help, the SR Linux documentation, and the rendered files in `configs/` when
genuinely stuck.

Reading the answer is allowed. Pasting it is not.

- [ ] Address each point-to-point interface with its `/31`
- [ ] Address the loopback
- [ ] Address the host-facing interface on each leaf (`e1-10`, `.1` of its subnet)
- [ ] Add **every** interface to the `default` network-instance
- [ ] Set the local **ASN** and **router-id**
- [ ] Create a peer group — call it `FABRIC`
- [ ] Define each neighbour with its **peer-AS**
- [ ] Attach an **export policy** so host subnets are actually advertised
- [ ] `commit` — and read the error when it rejects something

---

## Two traps, stated without the answer

**1. Interfaces do nothing until they are in a network-instance.** An address on an
interface is not enough. This is the most common first-time mistake on SR Linux, and
the symptom is a session that never leaves `active`.

**2. Policy syntax is a list.** SR Linux 24.10 rejects a bare policy name on
`export-policy`. The parser error names the character it wanted. Read it — it tells you
exactly what is wrong, which is more useful than being told here.

That second one is a real bug from this repo's history, fixed in commit `9c4880a`.

---

## Done when

```
show network-instance default protocols bgp neighbor
```

Both sessions **established** on spine1, one on each leaf.

```
docker exec clab-closmini-host1 ping -c3 172.16.2.10
```

`0% packet loss`, host to host, across the fabric.

---

## Then read the generator

Open `gen_configs.py` and `fabric.yml`.

It writes exactly what you just typed — six times, without typos, from a data model.
That is the moment the automation stops being magic, and the reason to do this by hand
first.

**The sentence this earns:**

> *"I built it by hand first, then automated it, because I wanted to know what the
> generator was doing before I trusted it."*
