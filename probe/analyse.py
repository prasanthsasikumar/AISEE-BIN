#!/usr/bin/env python3
"""Turn one probe walk into the numbers the comparison report needs.

THROWAWAY, alongside AISEEBIN/Probe/. Delete both once the report is written.

    python3 probe/analyse.py probe-20260913T1030.csv --map greenhouse.map.json

Reads the CSV written by ProbeView, and reports, for ARKit and for Immersal:
time to first fix, availability, position error against the stamped places,
revisit drift, recovery after an occlusion, and the indoor/outdoor split.

Two deliberate choices worth knowing about before reading any output:

* **Neither frame is privileged.** ARKit reports in the session frame (which,
  after relocalization, should coincide with the graph's frame) and Immersal
  reports in its own map frame. Comparing them directly would bake ARKit's
  own drift into Immersal's error. So each system is scored the same way: fit
  one rigid 2D transform from its estimates at the stamps onto the surveyed
  place coordinates, then report the residuals. A rigid fit cannot hide real
  error — it removes only the arbitrary choice of origin and north.
* **ARKit is scored twice.** Once raw in the graph frame (absolute accuracy,
  which is what the app actually consumes) and once after the same best fit
  (shape accuracy, i.e. drift alone). The gap between them is informative.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd

# Fallback ground truth: the bundled sample graph, if no real map is supplied.
SAMPLE_PLACES = {
    "entrance": (0.0, 0.0), "junction": (0.0, -8.0), "tropical": (-6.0, -8.0),
    "orchid": (-6.0, -14.0), "palm": (6.0, -8.0), "restrooms": (6.0, -2.0),
}

# A fix disagreeing with ARKit odometry by more than this is treated as
# suspect: over a 2 s interval no walker covers the difference.
SUSPECT_DISAGREEMENT_M = 1.0
# How far from a stamp a fix may be and still count as "at" that place.
STAMP_TOLERANCE_S = 1.5


def load_places(path: Path | None) -> dict[str, tuple[float, float]]:
    if path is None:
        print("! no --map given; scoring against the bundled sample coordinates")
        return SAMPLE_PLACES
    graph = json.loads(path.read_text())
    return {p["id"]: (float(p["x"]), float(p["z"])) for p in graph["pois"]}


def rigid_fit_2d(src: np.ndarray, dst: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Rotation and translation (no scale, no reflection) taking src onto dst."""
    src_c, dst_c = src.mean(axis=0), dst.mean(axis=0)
    h = (src - src_c).T @ (dst - dst_c)
    u, _, vt = np.linalg.svd(h)
    correction = np.diag([1.0, float(np.sign(np.linalg.det(vt.T @ u.T)))])
    rotation = vt.T @ correction @ u.T
    return rotation, dst_c - rotation @ src_c


def residuals(src: np.ndarray, dst: np.ndarray) -> np.ndarray:
    rotation, translation = rigid_fit_2d(src, dst)
    return np.linalg.norm((src @ rotation.T + translation) - dst, axis=1)


def describe(name: str, values: np.ndarray) -> str:
    if len(values) == 0:
        return f"  {name:<34} no data"
    return (f"  {name:<34} median {np.median(values):5.2f}  mean {values.mean():5.2f}  "
            f"p90 {np.percentile(values, 90):5.2f}  max {values.max():5.2f}  (n={len(values)})")


@dataclass
class Walk:
    frames: pd.DataFrame
    fixes: pd.DataFrame
    stamps: pd.DataFrame
    markers: pd.DataFrame
    localizes: pd.DataFrame

    @classmethod
    def load(cls, path: Path) -> "Walk":
        rows = pd.read_csv(path)
        rows["elapsed_s"] = rows["elapsed_s"].astype(float)
        localizes = rows[rows.event == "localize"].copy()
        return cls(
            frames=rows[rows.event == "frame"].copy(),
            fixes=localizes[localizes.imm_success == 1].copy(),
            stamps=rows[rows.event == "stamp"].copy(),
            markers=rows[rows.event == "marker"].copy(),
            localizes=localizes,
        )

    def ar_at(self, when: float) -> np.ndarray | None:
        """ARKit planar position at a moment, interpolated between samples."""
        f = self.frames.dropna(subset=["ar_x", "ar_z"])
        if f.empty or not (f.elapsed_s.min() - 0.5 <= when <= f.elapsed_s.max() + 0.5):
            return None
        return np.array([np.interp(when, f.elapsed_s, f.ar_x),
                         np.interp(when, f.elapsed_s, f.ar_z)])

    def fix_at(self, when: float, trusted_only: bool = True) -> np.ndarray | None:
        """Nearest successful Immersal fix to a moment, if one is close enough.

        `trusted_only` drops fixes the odometry cross-check flagged. A single
        wrong fix is worth metres, and least squares spreads that error across
        every other point — so an unfiltered rigid fit would report Immersal as
        uniformly mediocre rather than usually good with rare blunders. Both
        readings are reported; neither alone is the truth.
        """
        candidates = self.fixes
        if trusted_only and "odom_disagreement_m" in candidates:
            disagreement = pd.to_numeric(candidates.odom_disagreement_m, errors="coerce")
            candidates = candidates[~(disagreement > SUSPECT_DISAGREEMENT_M)]
        if candidates.empty:
            return None
        gaps = (candidates.elapsed_s - when).abs()
        if gaps.min() > STAMP_TOLERANCE_S:
            return None
        row = candidates.loc[gaps.idxmin()]
        # Immersal map space is y-up like ARKit's, so the ground plane is x/z.
        return np.array([float(row.imm_px), float(row.imm_pz)])

    def outdoor_spans(self) -> list[tuple[float, float]]:
        spans, opened = [], None
        for _, row in self.markers.iterrows():
            note = str(row.note)
            if "Stepped outside" in note:
                opened = row.elapsed_s
            elif "Back inside" in note and opened is not None:
                spans.append((opened, row.elapsed_s))
                opened = None
        if opened is not None:
            spans.append((opened, float("inf")))
        return spans


def report_availability(walk: Walk) -> None:
    print("\nAVAILABILITY")
    normal = walk.frames[walk.frames.ar_tracking == "normal"]
    if normal.empty:
        print("  ARKit never reached normal tracking — it never relocalized at all.")
    else:
        print(f"  ARKit time to normal tracking        {normal.elapsed_s.min():5.1f} s")
        share = len(normal) / max(len(walk.frames), 1)
        print(f"  ARKit share of walk tracking normal  {share:5.1%}")

    if walk.fixes.empty:
        print("  Immersal never returned a fix — check token, map ids, and lighting.")
    else:
        print(f"  Immersal time to first fix           {walk.fixes.elapsed_s.min():5.1f} s")

    attempts = walk.localizes[walk.localizes.note != "replayed"]
    if not attempts.empty:
        rate = (attempts.imm_success == 1).mean()
        print(f"  Immersal fix rate (live requests)    {rate:5.1%}  ({len(attempts)} requests)")
        # Immersal answers a failed match with error "none": the request was fine,
        # the place simply was not recognised. Relabelled so it cannot be misread
        # as a plumbing problem.
        reasons = attempts[attempts.imm_success != 1].imm_error.fillna("no match")
        for reason, count in reasons.replace({"none": "no match"}).value_counts().items():
            print(f"      {count:4d} × {reason}")
    replayed = walk.localizes[walk.localizes.note == "replayed"]
    if not replayed.empty:
        rate = (replayed.imm_success == 1).mean()
        print(f"  Immersal fix rate (replayed frames)  {rate:5.1%}  ({len(replayed)} frames, "
              "latency excluded from timings)")


def report_latency(walk: Walk) -> None:
    live = walk.localizes[(walk.localizes.note != "replayed")].dropna(subset=["imm_latency_ms"])
    if live.empty:
        return
    print("\nLATENCY (live requests only)")
    print(describe("round trip (ms)", live.imm_latency_ms.to_numpy(dtype=float)))
    if "imm_bytes" in live:
        kb = live.imm_bytes.dropna().to_numpy(dtype=float) / 1024
        if len(kb):
            print(describe("request size (KB)", kb))


def report_accuracy(walk: Walk, places: dict[str, tuple[float, float]]) -> None:
    print("\nPOSITION ERROR AT STAMPED PLACES (metres)")
    if walk.stamps.empty:
        print("  No stamps in this log — without ground truth there is no accuracy to report.")
        return

    truth, ar_points, imm_points, imm_truth = [], [], [], []
    missing_ar, missing_imm = 0, 0
    for _, stamp in walk.stamps.iterrows():
        place = places.get(str(stamp.place_id))
        if place is None:
            print(f"  ! stamp for unknown place '{stamp.place_id}' ignored")
            continue
        ar = walk.ar_at(stamp.elapsed_s)
        fix = walk.fix_at(stamp.elapsed_s)
        if ar is None:
            missing_ar += 1
        else:
            truth.append(place)
            ar_points.append(ar)
        if fix is None:
            missing_imm += 1
        else:
            imm_truth.append(place)
            imm_points.append(fix)

    # A rigid 2D fit spends 3 degrees of freedom (one rotation, two
    # translations), so three stamps leave only three residual degrees of
    # freedom and the fit can absorb most of the real error. Numbers from a
    # short walk look flatteringly good; say so rather than quoting them.
    fewest = min(len(ar_points), len(imm_points))
    if 3 <= fewest < 5:
        print(f"  ! only {fewest} usable stamps. A rigid fit has 3 degrees of freedom, so these\n"
              "    residuals understate the true error — treat them as a smoke test, not a result.")

    if len(ar_points) >= 3:
        ar_arr, truth_arr = np.array(ar_points), np.array(truth)
        raw = np.linalg.norm(ar_arr - truth_arr, axis=1)
        print(describe("ARKit, raw in graph frame", raw))
        print(describe("ARKit, after best rigid fit", residuals(ar_arr, truth_arr)))
    else:
        print(f"  ARKit: only {len(ar_points)} usable stamps (need 3 to fit)")

    if len(imm_points) >= 3:
        print(describe("Immersal, trusted fixes only",
                       residuals(np.array(imm_points), np.array(imm_truth))))
    else:
        print(f"  Immersal: only {len(imm_points)} stamps had a trusted fix within "
              f"{STAMP_TOLERANCE_S}s (need 3 to fit)")

    # The same thing again, keeping the blunders, because that is what the app
    # would actually have believed.
    raw_points, raw_truth = [], []
    for _, stamp in walk.stamps.iterrows():
        place = places.get(str(stamp.place_id))
        fix = walk.fix_at(stamp.elapsed_s, trusted_only=False)
        if place is not None and fix is not None:
            raw_truth.append(place)
            raw_points.append(fix)
    if len(raw_points) >= 3:
        print(describe("Immersal, including flagged fixes",
                       residuals(np.array(raw_points), np.array(raw_truth))))
        excluded = len(raw_points) - len(imm_points)
        if excluded > 0:
            print(f"  {excluded} of {len(raw_points)} stamps sat on a flagged fix. The gap between "
                  "the two\n  lines above is the cost of a blunder, and it is the number to quote "
                  "for safety.")
    if missing_imm:
        print(f"  Immersal had no fix at {missing_imm} of {len(walk.stamps)} stamps — "
              "an availability failure, not an accuracy one, but it lands on the visitor the same way.")
    if missing_ar:
        print(f"  ARKit had no pose at {missing_ar} stamps")


def report_drift(walk: Walk, places: dict[str, tuple[float, float]]) -> None:
    """Revisit error: the same physical place, stamped twice, is the cleanest
    drift measurement there is — no alignment or ground-truth survey needed."""
    repeats = walk.stamps.place_id.value_counts()
    repeats = repeats[repeats > 1]
    if repeats.empty:
        print("\nREVISIT DRIFT\n  No place was stamped twice; walk step 5 was skipped.")
        return
    print("\nREVISIT DRIFT (same place, stamped twice)")
    for place_id in repeats.index:
        visits = walk.stamps[walk.stamps.place_id == place_id].elapsed_s.tolist()
        first, last = visits[0], visits[-1]
        ar_first, ar_last = walk.ar_at(first), walk.ar_at(last)
        imm_first, imm_last = walk.fix_at(first), walk.fix_at(last)
        gap = last - first
        ar_drift = f"{np.linalg.norm(ar_last - ar_first):5.2f} m" if ar_first is not None and ar_last is not None else "   n/a"
        imm_drift = f"{np.linalg.norm(imm_last - imm_first):5.2f} m" if imm_first is not None and imm_last is not None else "   n/a"
        print(f"  {place_id:<12} after {gap:5.0f}s   ARKit {ar_drift}   Immersal {imm_drift}")


def report_recovery(walk: Walk) -> None:
    uncovered = walk.markers[walk.markers.note.astype(str).str.contains("Lens uncovered")]
    if uncovered.empty:
        return
    print("\nRECOVERY AFTER OCCLUSION (seconds until the next good pose)")
    for _, marker in uncovered.iterrows():
        t = marker.elapsed_s
        later_ar = walk.frames[(walk.frames.elapsed_s > t) & (walk.frames.ar_tracking == "normal")]
        later_imm = walk.fixes[walk.fixes.elapsed_s > t]
        ar = f"{later_ar.elapsed_s.min() - t:5.1f}" if not later_ar.empty else "never"
        imm = f"{later_imm.elapsed_s.min() - t:5.1f}" if not later_imm.empty else "never"
        print(f"  at {t:6.1f}s   ARKit {ar}   Immersal {imm}")


def report_transition(walk: Walk) -> None:
    spans = walk.outdoor_spans()
    if not spans:
        return
    print("\nINDOOR / OUTDOOR TRANSITION")
    attempts = walk.localizes[walk.localizes.note != "replayed"]
    outside = pd.Series(False, index=attempts.index)
    for start, end in spans:
        outside |= attempts.elapsed_s.between(start, end)

    for label, subset in (("inside", attempts[~outside]), ("outside", attempts[outside])):
        if subset.empty:
            continue
        rate = (subset.imm_success == 1).mean()
        print(f"  Immersal fix rate {label:<8} {rate:5.1%}  ({len(subset)} requests)")

    frames = walk.frames
    frames_outside = pd.Series(False, index=frames.index)
    for start, end in spans:
        frames_outside |= frames.elapsed_s.between(start, end)
    for label, subset in (("inside", frames[~frames_outside]), ("outside", frames[frames_outside])):
        if not subset.empty:
            share = (subset.ar_tracking == "normal").mean()
            print(f"  ARKit normal tracking {label:<8} {share:5.1%}")

    answered = walk.fixes.dropna(subset=["imm_map"])
    if not answered.empty:
        print("  fixes answered by map id: "
              + ", ".join(f"{int(k)}×{v}" for k, v in answered.imm_map.value_counts().items()))


def report_suspect_fixes(walk: Walk) -> None:
    """The aliasing check. `/localizeb64` returns no confidence, so the stand-in
    is disagreement with ARKit's short-interval odometry, which is reliable."""
    disagreements = walk.fixes.dropna(subset=["odom_disagreement_m"])
    print("\nFIX PLAUSIBILITY (odometry cross-check, convention-free)")
    if disagreements.empty:
        print("  Fewer than two consecutive fixes; nothing to cross-check.")
        return
    values = disagreements.odom_disagreement_m.to_numpy(dtype=float)
    print(describe("disagreement with ARKit (m)", values))
    suspect = disagreements[values > SUSPECT_DISAGREEMENT_M]
    print(f"  fixes disagreeing by >{SUSPECT_DISAGREEMENT_M} m: {len(suspect)} of {len(disagreements)} "
          f"({len(suspect) / len(disagreements):.1%})")
    for _, row in suspect.head(10).iterrows():
        print(f"      t={row.elapsed_s:7.1f}s  {row.odom_disagreement_m:5.2f} m  map {row.imm_map}")
    if len(suspect):
        print("  Each of these is a position the app would have spoken as fact. For a blind\n"
              "  visitor that is the failure that matters most — read these before the medians.")


def report_convention(walk: Walk) -> None:
    """Which rotation convention Immersal's REST response actually uses.

    Undocumented, so it is settled empirically, and not by comparing turn rates:
    the CV axis flip is a rotation by pi about X, which for a roughly upright
    phone shifts every heading by a constant and leaves turn *rates* identical.
    It is therefore invisible to any difference-based test.

    What does separate the candidates is a fact about walking: you face
    approximately where you are going. So each candidate is scored by the cosine
    between the camera's forward vector and the direction of travel between
    consecutive fixes, all in Immersal's own map frame. The correct reading sits
    near +1; the un-flipped reading of a CV pose sits near -1 (the flip reverses
    forward exactly); a transposed reading is an inverse rotation and correlates
    with nothing.

    Only headings depend on this. Every position number in this report is
    untouched, because position comes from px/py/pz alone.
    """
    terms = [f"imm_r{i}{j}" for i in range(3) for j in range(3)]
    fixes = walk.fixes.dropna(subset=terms + ["imm_px", "imm_pz"])
    print("\nROTATION CONVENTION (empirical)")
    if len(fixes) < 5:
        print("  Too few fixes to determine; positions are unaffected either way.")
        return

    rows = fixes[terms].to_numpy(dtype=float).reshape(-1, 3, 3)
    ground = fixes[["imm_px", "imm_pz"]].to_numpy(dtype=float)
    travel = np.diff(ground, axis=0)
    lengths = np.linalg.norm(travel, axis=1)
    # Only intervals with real walking carry heading information.
    moving = lengths > 0.5
    if moving.sum() < 3:
        print("  The walk had too little motion between fixes to tell.")
        return

    scores = {}
    for row_major in (True, False):
        for flip in (True, False):
            cosines = []
            for index in np.flatnonzero(moving):
                matrix = rows[index] if row_major else rows[index].T
                if flip:
                    matrix = matrix @ np.diag([1.0, -1.0, -1.0])
                forward = -matrix[:, 2]
                forward_ground = np.array([forward[0], forward[2]])
                norm = np.linalg.norm(forward_ground)
                if norm < 1e-6:
                    continue
                direction = travel[index] / lengths[index]
                cosines.append(float(forward_ground @ direction / norm))
            if cosines:
                name = f"{'row' if row_major else 'column'}-major, {'CV flip' if flip else 'no flip'}"
                scores[name] = float(np.median(cosines))

    ranked = sorted(scores.items(), key=lambda kv: -kv[1])
    for name, score in ranked:
        print(f"  {name:<28} faces direction of travel  {score:+.2f}")
    best, best_score = ranked[0]
    if best_score < 0.5:
        print("  → inconclusive: no candidate faces the walk. Check that the phone pointed "
              "forward,\n    and treat every heading in this report as unverified.")
        return
    # Row-major and column-major differ only by a transpose, and transposing a
    # yaw-only rotation just negates the yaw — which this test cannot see. Pitch
    # and roll are what separate them, so a phone held perfectly level leaves a
    # genuine tie. Say so rather than picking one.
    if len(ranked) > 1 and abs(ranked[1][1] - best_score) < 0.05:
        print(f"  → {best} or {ranked[1][0]} — tied.")
        print("    These differ by a transpose, which is invisible while the camera stays level. "
              "Only\n    the CV flip is settled. Headings are usable; the tie matters solely if "
              "pitch or roll\n    is ever read out of these poses, which this app does not do.")
    else:
        print(f"  → {best}")


def plot(walk: Walk, output: Path) -> None:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("\n(no plots: pip install matplotlib)")
        return

    figure, axes = plt.subplots(1, 3, figsize=(16, 5))
    f = walk.frames.dropna(subset=["ar_x", "ar_z"])
    axes[0].plot(f.ar_x, f.ar_z, lw=1, label="ARKit")
    if not walk.stamps.empty:
        xs = [walk.ar_at(t) for t in walk.stamps.elapsed_s]
        xs = np.array([p for p in xs if p is not None])
        if len(xs):
            axes[0].scatter(xs[:, 0], xs[:, 1], c="crimson", zorder=3, label="stamps")
    axes[0].set_title("ARKit trajectory (session frame)")
    axes[0].set_aspect("equal"); axes[0].legend(); axes[0].set_xlabel("x (m)"); axes[0].set_ylabel("z (m)")

    if not walk.fixes.empty:
        axes[1].scatter(walk.fixes.imm_px, walk.fixes.imm_pz, s=8, c=walk.fixes.elapsed_s, cmap="viridis")
        axes[1].set_title("Immersal fixes (map frame, coloured by time)")
        axes[1].set_aspect("equal"); axes[1].set_xlabel("x (m)"); axes[1].set_ylabel("z (m)")

    attempts = walk.localizes[walk.localizes.note != "replayed"]
    axes[2].step(attempts.elapsed_s, (attempts.imm_success == 1).astype(int), where="post", label="Immersal fix")
    axes[2].step(f.elapsed_s, (f.ar_tracking == "normal").astype(int) * 0.9, where="post", label="ARKit normal")
    for start, end in walk.outdoor_spans():
        axes[2].axvspan(start, min(end, f.elapsed_s.max()), color="orange", alpha=0.15)
        axes[2].text(start, 1.05, "outside", fontsize=8, color="darkorange")
    axes[2].set_ylim(-0.1, 1.2); axes[2].set_title("Availability over the walk (shaded = outdoors)")
    axes[2].set_xlabel("elapsed (s)"); axes[2].legend(loc="lower right")

    figure.tight_layout()
    figure.savefig(output, dpi=140)
    print(f"\nplots → {output}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv", type=Path)
    parser.add_argument("--map", type=Path, default=None,
                        help="greenhouse.map.json, for the surveyed place coordinates")
    parser.add_argument("--plots", type=Path, default=None, help="write figures to this PNG")
    args = parser.parse_args()

    if not args.csv.exists():
        print(f"no such file: {args.csv}", file=sys.stderr)
        return 1

    walk = Walk.load(args.csv)
    places = load_places(args.map)

    print(f"\n{'=' * 72}\n{args.csv.name}  —  {len(walk.frames)} ARKit samples, "
          f"{len(walk.localizes)} localize attempts, {len(walk.stamps)} stamps\n{'=' * 72}")
    report_availability(walk)
    report_latency(walk)
    report_accuracy(walk, places)
    report_drift(walk, places)
    report_recovery(walk)
    report_transition(walk)
    report_suspect_fixes(walk)
    report_convention(walk)
    if args.plots:
        plot(walk, args.plots)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
