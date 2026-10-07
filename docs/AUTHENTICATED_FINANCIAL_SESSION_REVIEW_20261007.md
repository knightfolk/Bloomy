# Authenticated financial sessions — October 7, 2026

The earnings client now owns a shared authentication actor. Exported contexts
contain an opaque account scope plus a unique session generation; raw account ID
and credential fingerprint stay private. Copies of the client share the actor.
Context-bound financial reports require a ready context before and after the
SQLite suspension, including its error path. This is the authentication/read
foundation; MonitorStore publication and retained chart clearing are not wired yet.

## Contract

Local credential replacement, in-place changes, missing/unreadable files and
invalid tokens invalidate requests and clear the session identity. Replacing even
identical bytes creates a new authentication boundary. Fresh successful account
parsing establishes identity before ingestion, so a rejected B ledger page cannot
leave A as the authenticated account. B remains unready until ingestion succeeds.
Clients without a database can authenticate but never claim ledger readiness.

Request tickets also reject superseded responses within the same credential
session. A delayed success, authentication rejection or transport failure cannot
publish an older account or revoke the newer one, including A → B → A. Validation
and authentication revocation share one actor turn to close the require/reject
race. Public leaderboard 401/403 is an HTTP failure, not evidence that the local
login expired. Same-token transport failures preserve the session identity;
presentation must still mark retained results stale.

Filesystem sources watch the credential file and its parent directories, recover
when paths are replaced/recreated, and own descriptor cancellation/closure.
Directory events compare file metadata before rereading unchanged credentials.
There is no timer or additional network polling. API boundaries always reread
credentials, so correctness does not depend solely on notification delivery.
Reads are limited to 64 KiB, validate regular files and stable file metadata,
and reject invalid UTF-8, empty tokens and embedded whitespace/control characters.
Watcher opens are nonblocking and accept only regular files/directories, including
a descriptor check after opening to handle path replacement races.

The old global lifetime-balance fallback was removed. Lifetime balance differences
can include corrections and are not earned-income rates. If authenticated recent
history is incomplete and the public leaderboard has no matching account, the
rolling total remains unavailable. Scoped report observations remain available to
the future chart presentation with their explicit coverage and capture timestamps.

## Regression evidence

Synthetic tests cover account generations, same-account request ordering,
identical-byte replacement, invalid/oversized/nonregular credentials, filesystem
replacement/deletion, directory recreation and in-place writes. A report is held
inside the actual SQLite progress callback while credentials change, then its old
result is rejected. Held authenticated/public responses and transport errors test
supersession; another held response completes after A → B → A. Failed B ingestion,
public authentication-like failures, same-token transport failures, subscriber
completion on actor destruction and no-database readiness have separate assertions.

An interim run exposed a real named-pipe hang in the watcher open. A retained
process sample points to that exact call. The task-owned test helper was stopped
and its parent joined; regular-file filtering and nonblocking descriptor opens
repair the boundary. The sample and failed run are retained. Another interim run
compiled the pre-fix rejection method before its strengthened test, and therefore
failed the expected obsolete-rejection assertion; final verification uses stable
source inputs. A bounded read-only reviewer found the reject ordering race and
confirmed the source repairs. No production credentials, databases, provider
commands, inference or installed app were used for these tests.

The final focused run passes 40 tests: 16 new session regressions, seven account
tests and 17 scoped-report tests. The stable-source full Release suite passes
1,698 reported tests (1,649 telemetry/UI, 21 companion protocol and 28 companion
host), with seven existing opt-in skips. The production Release build passes in
43.15 seconds. All 32 native staging checks and `git diff --check` pass. The only
full-test compiler warning is the existing unrelated redundant NSAppearance
require assertion; no changed-source warning remains. Final bounded source
review found no concrete defects. Source/terminal-log hashes are retained in
`.build/auth-session-verification-20261007.json`.

Retained logs are `.build/auth-session-{final-focused,release-tests,release-build,staging}-20261007.log`.
Earlier compile/stall/interim logs and the process sample remain separate. These
are source/test/build evidence, not a signed distribution manifest.

## Remaining scope

The existing AccountEarningsFetching legacy query methods and MonitorStore still
use global aggregates. They do not gain account isolation merely because fetch
now returns a context through its new API. Protocol integration must bind one
context to a complete chart read, generation-check every publication, clear all
retained financial/profit/energy caches on switch/revocation, and disclose legacy
history separately. Native A/B/revocation/held-callback fixtures are still required.
No UI rendering, performance superiority, installed update or release is claimed.
Earlier native motion gates remain open independently.

Plan: [scoped financial reads](superpowers/plans/2026-10-07-scoped-financial-reads.md).
