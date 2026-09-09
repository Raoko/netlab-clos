# 🎯 GOAL
Two hosts on different switches can ping each other, and every hop between them is a routing decision I typed by hand.

# 📊 WHERE I AM
Just did: host1 pinged host2 across the fabric, 0% loss
Next up:  nothing. It works. Write it up.

# ✅ MILESTONES
- [x] three empty switches booted
- [x] spine1 ports have addresses
- [x] spine1 loopback has an address
- [x] spine1 ports joined the routing table
- [x] spine1 BGP switched on
- [x] spine1 peer group made
- [x] spine1 knows its two neighbours
- [x] spine1 allowed to share routes
- [x] spine1 config saved for real
- [x] leaf1 built the same way
- [x] leaf2 built the same way
- [x] host1 pings host2

# 📂 THE FILES
- `clos-mini.clab.yml` — boots the three switches and two hosts, with no config
- `docs/hand-build.md` — the checklist, deliberately with no commands in it
- `configs/spine1.cfg` — what the generator writes, to compare against at the end

# 📝 LOG
- 2026-09-08 — DONE. leaf2 built, both BGP sessions established, host1 pinged host2 with 0% loss and ttl=61, which is 64 minus the three routers it crossed
- 2026-09-08 — spine1 pointed at 10.0.0.1 (AS 65101) and 10.0.0.3 (AS 65102)
- 2026-09-08 — FABRIC peer group created on spine1
- 2026-09-08 — spine1 addressed on both ports and its loopback, all three put in the default routing table, BGP switched on
