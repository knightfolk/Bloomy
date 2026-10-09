# Reuse legacy log metadata without retaining raw text

The local source still reads at most 128 KiB from `provider.log` on every poll.
An unchanged tail now reuses its selected line positions and parsed dates,
including explicitly invalid dates. Event fields are rebuilt from the fresh
bytes through the existing parser. Raw messages, categories and file bytes are
never retained by the cache, and the public source still returns raw events.
EventBuffer remains the owner of privacy filtering, deduplication and retention.

One private actor belongs to each immutable source; copied sources share it.
Reading, hashing, replay and cache replacement run in one actor turn. The cache
holds one SHA-256 fingerprint, the exact requested limit, formatter context and
at most 100 ordinal/date pairs. Larger limits preserve the previous public
result while bypassing retention. Nonpositive limits still read the file before
returning empty. A read error discards metadata before propagating.

Cache hits remain ordinary successful acquisitions. The service renews
`legacyReadAt`, clears recovered diagnostics and merges the complete batch with
unified events. No poll, timer, network request or provider action is added.

## Parser context and equivalence

The public parser keeps its existing fixed POSIX format and optional capture
does not allocate a metadata array. Cache replay uses the identical newline,
field, severity and lifecycle rules. Positions retain chronological read order,
including duplicate records, tied dates and nil dates.

The key captures the actual fresh formatter's resolved time zone, calendar and
behavior; cold parsing uses that same formatter. It does not force UTC or change
parsing strictness. Apple describes the formatter's default time-zone behavior
in its [DateFormatter documentation](https://developer.apple.com/documentation/foundation/dateformatter/timezone),
and fixed-format POSIX parsing in [QA1480](https://developer.apple.com/library/archive/qa/qa1480/_index.html).
The internal test factory varies time zone while retaining that fixed format and
locale; it is not a general-purpose configurable parser API.

## Measured component cost

Baseline source is `6de2a2c7b66b437df4d2caffc0f4121692d04f0a`. Evidence is in
`.build/legacy-tail-read-review-20261009/`. The first frozen baseline executable
measures the original source and parser. Thirty repeated reads in each of five
alternating comparisons produce matching reference/source medians near
6.16/6.13 ms for ordinary warnings, 5.65/5.65 ms for sensitive warnings and
4.20/4.20 ms for a quiet tail.

An intermediate comparison uses the refactored uncached parser and is retained
for provenance. The final counterbalanced comparison instead freezes the exact
original parser from the baseline commit, adding only an import and renaming
its two enums to avoid module-name collisions. It compares that original with
the source cache in the same optimized process. The linked candidate library
is retained as `frozen-candidate-libDarkbloomTelemetry.a`.

Timing includes bounded file acquisition plus EventBuffer merging/privacy work.
Fixture writes and expected-result preparation stay outside that timing. All
complete event fields and order match, including the changing-tail case's
retained older events.

| Synthetic workload | Uncached median/read | Cached source median/read |
| --- | ---: | ---: |
| Unchanged ordinary warnings | 6.447 ms | 2.589 ms |
| Unchanged sensitive warnings | 5.945 ms | 2.077 ms |
| Unchanged quiet tail | 4.449 ms | 0.109 ms |
| Changed tail on every read | 6.218 ms | 6.441 ms |

Cold source reads cost slightly more. Their measured median/reference pairs are
6.529/6.420 ms ordinary, 6.034/5.940 ms sensitive, 4.608/4.470 ms quiet and
6.458/6.265 ms in the changing workload. These bounded timings show the tradeoff;
they are not a whole-app CPU, allocation or energy measurement.

## Verification and limits

Six regressions cover raw sensitive fields, Unicode/invalid UTF-8, mixed
newlines, duplicate/tied/invalid dates, 30 repeated reads, append/truncate,
same-size atomic replacement, empty files, failure/recovery, exact limits,
bounded metadata, concurrent reads, source copies, isolated formatter-context
changes and service freshness/privacy/unified-event recovery. The first focused
Release run passes 37 tests in three suites. Independent read-only review found
no blocking production issue; its request for populated dated-event context
proof was incorporated before the final regression run.

The final serial Release run passes 1,860 reported app tests in 234 suites, plus
21 protocol and 28 host tests, with seven existing opt-in skips. It includes the
strengthened populated dated-event context regression. All finite test and
benchmark runs finish; the first frozen-reference launch was attempted before
its compiler finished and returned "executable not found". That failed launch
is retained separately; the successful run follows the joined compiler and
uses a fresh output directory. It is the `frozen-final` result above.
The final full Release product build also exits zero after 48.88 seconds.

No visual layout changes here. The prior native synthetic popup review remains
at `b05de19`; it is not a rendering of the newer source. Installed Bloomy, actual
provider configuration, unrelated dirty work and all broader native/motion,
accessibility, production attribution and delivery gates remain preserved.
Nothing is pushed or published by this checkpoint.
