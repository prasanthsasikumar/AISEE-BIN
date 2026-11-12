# Joining several Author scans into one map (NUS COM, 11 Nov 2026)

Each Author scan has its own ARKit/Immersal frame. These scripts put them in one frame
and publish a combined graph with an Immersal multi-map alignment (`immersalAlignment.maps`,
one placement per scan, `ty` = height offset), and no world map.

Run from a working folder containing `nus/` (rows.json, anchors.json, `<slug>.npy` clouds):

1. Line the scans up by hand in the aligner page, then Copy result -> `user1.json`.
2. `python3 refine.py user1.json`: snaps places with the same name (within 8 m) together, then writes poses.json.
3. `python3 merge.py nus merge2.json merged.json`: merges the graphs, joins scans whose route points are within 2.5 m on the same floor, and adds the `extra_edges` bridges.
4. `python3 publish.py nus-com "<note>"`: uploads the combined points and inserts the next version.

`seeded.py`/`align.py` are the automatic attempt (pin at a shared spot, sweep yaw). With
little overlap between scans it could not settle the rotations, so the hand layout won.
