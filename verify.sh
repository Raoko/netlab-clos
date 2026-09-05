#!/usr/bin/env bash
# Post-deploy check. Every line here is an interview answer.
set -u

echo "=== BGP sessions (expect 4 established per spine, 2 per leaf) ==="
for d in spine1 spine2 leaf1 leaf2 leaf3 leaf4; do
  echo "--- $d"
  sudo docker exec clab-clos01-$d sr_cli -- \
    'show network-instance default protocols bgp neighbor' 2>/dev/null \
    | grep -E 'established|active|connect' || echo "  (no output - check node is up)"
done

echo
echo "=== ECMP: leaf1 should have TWO next-hops to leaf4's subnet ==="
sudo docker exec clab-clos01-leaf1 sr_cli -- \
  'show network-instance default route-table ipv4-unicast prefix 172.16.4.0/24 detail'

echo
echo "=== End-to-end: host1 -> host2 across the fabric ==="
sudo docker exec clab-clos01-host1 ping -c 3 172.16.4.10

echo
echo "=== Path proof: traceroute should show leaf1 -> spine -> leaf4 ==="
sudo docker exec clab-clos01-host1 traceroute -n 172.16.4.10 2>/dev/null \
  || echo "(install traceroute in the alpine host if missing)"
