"""Qualify finite Metrics profiles with the inert fixture's read counters."""

COUNTERS = ("started", "completed", "failed", "cancelled", "empty", "cacheReleases")
# Current Metrics picker scopes plus retained legacy history-proof scopes.
PERIOD_SECONDS = (3_600, 7_200, 28_800, 43_200, 86_400, 604_800, 2_592_000)


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


class MetricsReadPhase:
    def __init__(self, proof, mode):
        if mode not in ("refresh", "quiet"):
            raise ValueError("Use refresh or quiet Metrics read mode")
        self.mode = mode
        self.before = self.latest = phase(proof)
        if self.before["pending"]:
            raise ValueError("Start the profile after the pending read completes")
        if mode == "refresh" and (not self.before["retainedSnapshotRows"]
                                  or self.before["periodSeconds"] is None):
            raise ValueError("Refresh profiles need a completed nonempty Metrics scope")

    def observe(self, proof):
        current = phase(proof)
        if any(current[key] < self.latest[key] for key in COUNTERS):
            raise ValueError("Metrics counters reset during the profile")
        unchanged = ("failed", "cancelled", "empty", "cacheReleases",
                     "retainedSnapshotRows", "periodSeconds")
        if any(current[key] != self.before[key] for key in unchanged):
            raise ValueError("Metrics scope, cache or outcome changed during the profile")
        if self.mode == "quiet" and any(current[key] != self.before[key] for key in COUNTERS):
            raise ValueError("Quiet Metrics profile included read work")
        self.latest = current

    def finish(self):
        if self.latest["pending"]:
            raise ValueError("Metrics profile ended with an incomplete read")
        started = self.latest["started"] - self.before["started"]
        completed = self.latest["completed"] - self.before["completed"]
        if self.mode == "refresh" and (completed < 1 or started != completed):
            raise ValueError("Refresh Metrics profile did not include a complete refresh")
        return {"mode": self.mode, "startedDelta": started, "completedDelta": completed,
                "before": self.before, "after": self.latest}
