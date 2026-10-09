"""Qualify finite Metrics profiles with the inert fixture's read counters."""

import copy
import math

COUNTERS = ("started", "completed", "failed", "cancelled", "empty", "cacheReleases")
# Current Metrics picker scopes plus retained legacy history-proof scopes.
PERIOD_SECONDS = (3_600, 7_200, 28_800, 43_200, 86_400, 604_800, 2_592_000)
ROLLING_READ_FIELDS = ("readID", "intervalSeconds", "queryStartUnix", "queryEndUnix",
                       "rows", "reusedRows", "milliseconds")


def bracket_metrics_endpoint(read_usage, read_proof, clock):
    """Reject Metrics work crossing a CPU endpoint; credit only its earlier proof."""
    before = copy.deepcopy(read_proof())
    usage = read_usage()
    timestamp = clock()
    after = copy.deepcopy(read_proof())
    if before != after:
        raise ValueError("Metrics proof changed across the CPU endpoint")
    return usage, timestamp, before


def phase(proof):
    values = {key: proof[key] for key in (*COUNTERS, "retainedSnapshotRows")}
    if any(type(value) is not int or value < 0 for value in values.values()):
        raise ValueError("Metrics proof needs nonnegative integer counters")
    if values["retainedSnapshotRows"] > 100_000:
        raise ValueError("Metrics proof exceeds the fixture retention cap")
    closed = sum(values[key] for key in ("completed", "failed", "cancelled"))
    if closed > values["started"] or values["empty"] > values["completed"]:
        raise ValueError("Metrics proof has inconsistent read counters")
    reads = proof.get("recentReads", [])
    values["periodSeconds"] = reads[-1]["intervalSeconds"] if reads else None
    if values["periodSeconds"] is not None and (
            type(values["periodSeconds"]) not in (int, float)
            or values["periodSeconds"] not in PERIOD_SECONDS):
        raise ValueError("Metrics proof has an unsupported completed scope")
    values["pending"] = values["started"] - closed
    if proof.get("heldReadID") is not None:
        raise ValueError("Held synthetic reads cannot qualify a normal profile")
    return values


def rolling_phase(proof):
    """Validate bounded per-read evidence without relaxing the strict modes."""
    try:
        if type(proof) is not dict:
            raise ValueError("Rolling Metrics proof needs a record")
        reads = proof["recentReads"]
        if type(reads) is not list or not 1 <= len(reads) <= 12:
            raise ValueError("Rolling Metrics proof needs bounded completed read records")
        previous_id = 0
        validated = []
        for read in reads:
            if type(read) is not dict:
                raise ValueError("Rolling Metrics proof needs completed read records")
            for key in ("readID", "rows", "reusedRows"):
                if type(read[key]) is not int or read[key] < 0:
                    raise ValueError("Rolling Metrics read counters must be nonnegative integers")
            if read["readID"] <= previous_id or read["rows"] > 100_000 or read["reusedRows"] > read["rows"]:
                raise ValueError("Rolling Metrics proof has invalid read order or row counts")
            for key in ("intervalSeconds", "queryStartUnix", "queryEndUnix", "milliseconds"):
                if type(read[key]) not in (int, float) or not math.isfinite(read[key]):
                    raise ValueError("Rolling Metrics read measurements must be finite numbers")
            if read["intervalSeconds"] not in PERIOD_SECONDS or read["milliseconds"] < 0:
                raise ValueError("Rolling Metrics proof has an unsupported scope or timing")
            # UNIX conversion may introduce sub-microsecond rounding. This is
            # only a representation tolerance, not permission to change scope.
            if not math.isclose(read["queryEndUnix"] - read["queryStartUnix"],
                                read["intervalSeconds"], rel_tol=0, abs_tol=0.000001):
                raise ValueError("Rolling Metrics query bounds do not match its scope")
            previous_id = read["readID"]
            validated.append({key: read[key] for key in ROLLING_READ_FIELDS})
        values = phase(proof)
        if previous_id > values["started"] or values["retainedSnapshotRows"] != validated[-1]["rows"]:
            raise ValueError("Rolling Metrics snapshot does not match its completed read")
        return values, validated
    except (KeyError, TypeError, IndexError, OverflowError) as error:
        raise ValueError("Rolling Metrics proof has a malformed schema") from error


class MetricsReadPhase:
    def __init__(self, proof, mode):
        if mode not in ("refresh", "quiet", "rolling-refresh"):
            raise ValueError("Use refresh, quiet or rolling-refresh Metrics read mode")
        self.mode = mode
        if mode == "rolling-refresh":
            self.before, reads = rolling_phase(proof)
            self.rolling_read = reads[-1]
            self.rolling_baseline = dict(self.rolling_read)
            self.rolling_completions = []
            if self.rolling_read["readID"] != self.before["started"]:
                raise ValueError("Start a rolling profile after its latest read completes successfully")
        else:
            self.before = phase(proof)
        self.latest = self.before
        if self.before["pending"]:
            raise ValueError("Start the profile after the pending read completes")
        if mode != "quiet" and (not self.before["retainedSnapshotRows"]
                                or self.before["periodSeconds"] is None):
            raise ValueError("Refresh profiles need a completed nonempty Metrics scope")

    def observe(self, proof):
        if self.mode == "rolling-refresh":
            current, reads = rolling_phase(proof)
        else:
            current = phase(proof)
        if any(current[key] < self.latest[key] for key in COUNTERS):
            raise ValueError("Metrics counters reset during the profile")
        unchanged = ("failed", "cancelled", "empty", "cacheReleases", "periodSeconds")
        if self.mode != "rolling-refresh":
            unchanged += ("retainedSnapshotRows",)
        if any(current[key] != self.before[key] for key in unchanged):
            raise ValueError("Metrics scope, cache or outcome changed during the profile")
        if self.mode == "quiet" and any(current[key] != self.before[key] for key in COUNTERS):
            raise ValueError("Quiet Metrics profile included read work")
        if self.mode == "rolling-refresh":
            self._observe_rolling_reads(current, reads)
        self.latest = current

    def _observe_rolling_reads(self, current, reads):
        previous = self.rolling_read
        if any(read != previous for read in reads if read["readID"] == previous["readID"]):
            raise ValueError("Completed rolling Metrics read evidence changed")
        new = [read for read in reads if read["readID"] > previous["readID"]]
        completed = current["completed"] - self.latest["completed"]
        if len(new) != completed:
            raise ValueError("Rolling Metrics proof skipped completed read evidence")
        for read in new:
            if read["readID"] != previous["readID"] + 1:
                raise ValueError("Rolling Metrics proof skipped a read ID")
            if (read["intervalSeconds"] != self.before["periodSeconds"]
                    or read["queryStartUnix"] < previous["queryStartUnix"]
                    or read["queryEndUnix"] < previous["queryEndUnix"]):
                raise ValueError("Rolling Metrics query moved backward or changed scope")
            if not 0 < read["rows"] <= previous["rows"] or read["reusedRows"] != read["rows"]:
                raise ValueError("Rolling Metrics rows grew, became empty or were not fully reused")
            previous = read
        if reads[-1] != previous:
            raise ValueError("Rolling Metrics rows changed without a completed read")
        self.rolling_read = previous
        self.rolling_completions.extend(new)

    def finish(self):
        if self.latest["pending"]:
            raise ValueError("Metrics profile ended with an incomplete read")
        started = self.latest["started"] - self.before["started"]
        completed = self.latest["completed"] - self.before["completed"]
        if self.mode != "quiet" and (completed < 1 or started != completed):
            raise ValueError("Refresh Metrics profile did not include a complete refresh")
        result = {"mode": self.mode, "startedDelta": started, "completedDelta": completed,
                  "before": self.before, "after": self.latest}
        if self.mode == "rolling-refresh":
            # Known fields are validated scalars. Copy every record and phase
            # so neither caller-owned proofs nor earlier reports own our state.
            result.update(before=dict(self.before), after=dict(self.latest),
                          baselineRead=dict(self.rolling_baseline),
                          completedReads=[dict(read) for read in self.rolling_completions])
        return result
