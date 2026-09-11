# NetBox as the source of truth

`fabric.yml` was always a stand-in. The generator's own header said so:
*"Swap fabric.yml for a NetBox API call and the rest of this script does not change."*

That swap is now done, and the claim was tested instead of assumed.

---

## The proof

Every switch config was rendered twice, once from each source, and compared:

```
leaf1   d63d5c609e7d   identical
leaf2   b31e0a12765d   identical
leaf3   af49f11eedd2   identical
leaf4   47a1b44a538a   identical
spine1  c4c093e0e465   identical
spine2  f72779f3c1f4   identical
```

SHA-256 prefixes. **All six configs match byte for byte.**

---

## What NetBox holds

- Site `clos-01`
- Six **Nokia 7220 IXR-D3** switches, using the community device-type library so every
  port exists with its real SR Linux name
- **Spine** and **Leaf** roles
- A `bgp_asn` custom field on each device, plus the ASNs under a private RIR
- The eight spine-to-leaf cables
- 26 addresses: 16 `/31` link ends, 6 loopbacks set as each device's primary IP, and
  4 host gateways
- The `/16` supernets as containers, and the four host `/24`s

## How the generator reads it

| The generator needs | NetBox provides |
|---|---|
| spines and leaves | device role `spine` / `leaf` at site `clos-01` |
| ASN | custom field `bgp_asn` |
| loopback | the device's primary IPv4 |
| host subnet | the address on `ethernet-1/10`, taken as a network |
| link addressing | derived by the same rule as `fabric.yml` |

**Order matters.** The `/31`s are derived from each switch's position in the list, and
NetBox returns devices alphabetically. The reader sorts by the number in each name, so
`spine1` stays index 0 and the addressing cannot silently shift.

---

## Running it

```sh
python gen_configs.py                                  # from fabric.yml - what CI runs
python gen_configs.py --source netbox --out /tmp/cfg   # from NetBox
```

| Setting | Default |
|---|---|
| `NETBOX_URL` | the lab NetBox |
| `NETBOX_TOKEN` | falls back to `~/.config/netbox/token` |
| `NETBOX_CA` | unset: TLS is not verified, and the script says so |

The token is a **read-only** NetBox v2 token. It is never committed.

---

## Why CI still uses `fabric.yml`

GitHub's runner cannot reach a home lab, so CI keeps rendering from `fabric.yml` and keeps
failing the build if `configs/` drifts from it. The NetBox path is opt-in, and `requests`
is imported only when that path runs, so CI still installs nothing but `pyyaml`.

The drift check was re-run after the change. It still passes.

---

## Found while building it

- **NetBox matches manufacturer names exactly.** The library spells it `Netgear`, and an
  existing `NETGEAR` made its device types fail to import.
- **VLANs and prefixes have no `planned` status.** Devices do. `reserved` is the
  equivalent for addressing.
- **Two access points had quietly changed address** after a gateway cutover, because their
  DHCP reservations were never created. They were found by sweeping the subnet and matching
  MAC addresses, and NetBox records where they actually are rather than where the plan put
  them.
