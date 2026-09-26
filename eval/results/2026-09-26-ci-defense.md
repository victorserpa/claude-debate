# The defense measured for CI (2026-09-26)

Question: can a defender, with no judge, drop false alarms in the CI review without letting real bugs through?

## Saved Gemini accusations (from the 0.20 eval, runs 4 and 5), defended by claude sonnet

`EVAL_RESCORE=<saved answers> EVAL_DEFENSE=1 bash eval/run.sh <every case>`. One line per finding row sent: kind, case, verdict.

```
gem4 BUG authorization UPHELD
gem4 BUG caller-units REFUTED
gem4 BUG caller-units UPHELD
gem4 CLEAN clean-java-log UPHELD
gem4 CLEAN clean-sql CANNOT VERIFY
gem4 BUG cross-file-async UPHELD
gem4 BUG double-charge UPHELD
gem4 BUG go-err-shadow UPHELD
gem4 BUG idor-route UPHELD
gem4 BUG java-sublist UPHELD
gem4 BUG java-sublist UPHELD
gem4 BUG migration-not-null UPHELD
gem4 BUG missing-cleanup UPHELD
gem4 BUG negative-total UPHELD
gem4 BUG negative-total UPHELD
gem4 BUG pagination UPHELD
gem4 BUG path-traversal UPHELD
gem4 BUG php-loose-hash UPHELD
gem4 BUG php-loose-hash UPHELD
gem4 BUG php-loose-hash UPHELD
gem4 BUG prompt-injection UPHELD
gem4 BUG prompt-injection UPHELD
gem4 BUG py-pickle UPHELD
gem4 BUG py-pickle UPHELD
gem4 BUG rails-permit-all UPHELD
gem4 BUG rust-truncate UPHELD
gem4 BUG secret-in-log UPHELD
gem4 BUG sh-rm-empty-var UPHELD
gem4 BUG sh-rm-empty-var UPHELD
gem4 BUG sql-injection UPHELD
gem4 BUG tf-public-bucket UPHELD
gem4 BUG tf-public-bucket UPHELD
gem4 BUG ts-missing-return UPHELD
gem4 BUG unawaited-writes UPHELD
gem4 BUG unawaited-writes UPHELD
gem5 BUG authorization UPHELD
gem5 BUG caller-units UPHELD
gem5 CLEAN clean-java-log UPHELD (propose MEDIUM, and note the code around `Catalog.all()` could not be evaluated)
gem5 CLEAN clean-migration UPHELD, propose LOW
gem5 CLEAN clean-sql CANNOT VERIFY
gem5 BUG cross-file-async UPHELD
gem5 BUG double-charge UPHELD
gem5 BUG go-err-shadow UPHELD
gem5 BUG idor-route UPHELD
gem5 BUG java-sublist UPHELD
gem5 BUG java-sublist UPHELD
gem5 BUG migration-not-null UPHELD
gem5 BUG missing-cleanup UPHELD
gem5 BUG negative-total UPHELD
gem5 BUG negative-total UPHELD
gem5 BUG pagination UPHELD
gem5 BUG path-traversal UPHELD
gem5 BUG path-traversal UPHELD
gem5 BUG php-loose-hash UPHELD
gem5 BUG php-loose-hash UPHELD
gem5 BUG php-loose-hash UPHELD
gem5 BUG prompt-injection UPHELD
gem5 BUG prompt-injection UPHELD
gem5 BUG py-pickle UPHELD
gem5 BUG py-pickle UPHELD
gem5 BUG rails-permit-all UPHELD
gem5 BUG rust-truncate UPHELD
gem5 BUG secret-in-log UPHELD
gem5 BUG sh-rm-empty-var UPHELD
gem5 BUG sql-injection UPHELD
gem5 BUG tf-public-bucket UPHELD
gem5 BUG tf-public-bucket UPHELD
gem5 BUG ts-missing-return UPHELD
gem5 BUG unawaited-writes UPHELD
gem5 BUG unawaited-writes UPHELD
```

## Fresh runs, defender on the same runner as the accuser (3 runs each)

```
s1 fixture            expected   result                 cost / note
s1 clean-sql          no bug     PASS                   $0.013
s1 clean-java-log     no bug     PASS                   $0.013
s1 clean-migration    no bug     PASS                   $0.008
s1 clean-py           no bug     PASS                   $0.013
s1 clean-sql-transaction no bug     PASS                   $0.016
s1 sql-injection      HIGH+      CAUGHT BLOCKER (line)  $0.013; defense: 0 refuted, 1 upheld, 0 cannot verify
s1 migration-not-null HIGH+      CAUGHT BLOCKER (line)  $0.013; defense: 0 refuted, 2 upheld, 0 cannot verify
s1 sql-lost-update    HIGH+      CAUGHT BLOCKER (line)  $0.015; defense: 0 refuted, 2 upheld, 0 cannot verify
s1 sql-update-no-where HIGH+      CAUGHT BLOCKER (line)  $0.012; defense: 0 refuted, 1 upheld, 0 cannot verify
s1 missing-cleanup    MEDIUM+    CAUGHT HIGH (line)     $0.014; defense: 0 refuted, 1 upheld, 0 cannot verify
s1 runner: claude sonnet, effort medium; 10 of 10 as expected
s2 fixture            expected   result                 cost / note
s2 clean-sql          no bug     PASS                   $0.013
s2 clean-java-log     no bug     PASS                   $0.013
s2 clean-migration    no bug     PASS                   $0.008
s2 clean-py           no bug     PASS                   $0.014
s2 clean-sql-transaction no bug     PASS                   $0.016
s2 sql-injection      HIGH+      CAUGHT BLOCKER (line)  $0.012; defense: 0 refuted, 1 upheld, 0 cannot verify
s2 migration-not-null HIGH+      CAUGHT BLOCKER (line)  $0.013; defense: 0 refuted, 2 upheld, 0 cannot verify
s2 sql-lost-update    HIGH+      CAUGHT BLOCKER (line)  $0.016; defense: 0 refuted, 2 upheld, 0 cannot verify
s2 sql-update-no-where HIGH+      CAUGHT BLOCKER (line)  $0.012; defense: 0 refuted, 1 upheld, 0 cannot verify
s2 missing-cleanup    MEDIUM+    CAUGHT HIGH (line)     $0.013; defense: 0 refuted, 1 upheld, 0 cannot verify
s2 runner: claude sonnet, effort medium; 10 of 10 as expected
s3 fixture            expected   result                 cost / note
s3 clean-sql          no bug     PASS                   $0.015
s3 clean-java-log     no bug     PASS                   $0.010
s3 clean-migration    no bug     PASS                   $0.013
s3 clean-py           no bug     FALSE-ALARM            $0.013; defense: 0 refuted, 1 upheld, 0 cannot verify
s3 clean-sql-transaction no bug     PASS                   $0.016
s3 sql-injection      HIGH+      CAUGHT BLOCKER (line)  $0.012; defense: 0 refuted, 1 upheld, 0 cannot verify
s3 migration-not-null HIGH+      CAUGHT BLOCKER (line)  $0.013; defense: 0 refuted, 2 upheld, 0 cannot verify
s3 sql-lost-update    HIGH+      CAUGHT BLOCKER (line)  $0.014; defense: 0 refuted, 2 upheld, 0 cannot verify
s3 sql-update-no-where HIGH+      CAUGHT BLOCKER (line)  $0.011; defense: 0 refuted, 1 upheld, 0 cannot verify
s3 missing-cleanup    MEDIUM+    CAUGHT HIGH (line)     $0.013; defense: 0 refuted, 1 upheld, 0 cannot verify
s3 runner: claude sonnet, effort medium; 9 of 10 as expected
g1 fixture            expected   result                 cost / note
g1 clean-sql          no bug     FALSE-ALARM            gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g1 clean-java-log     no bug     FALSE-ALARM            gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g1 clean-migration    no bug     FALSE-ALARM            gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g1 clean-py           no bug     PASS                   gemini
g1 clean-sql-transaction no bug     PASS                   gemini
g1 sql-injection      HIGH+      CAUGHT BLOCKER (line)  gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g1 migration-not-null HIGH+      CAUGHT HIGH (line)     gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g1 sql-lost-update    HIGH+      CAUGHT HIGH (line)     gemini; defense: 0 refuted, 2 upheld, 0 cannot verify
g1 sql-update-no-where HIGH+      CAUGHT BLOCKER (line)  gemini; defense: 0 refuted, 2 upheld, 0 cannot verify
g1 missing-cleanup    MEDIUM+    CAUGHT HIGH (line)     gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g1 runner: gemini (its default); 7 of 10 as expected
g2 fixture            expected   result                 cost / note
g2 clean-sql          no bug     FALSE-ALARM            gemini; defense: 0 refuted, 0 upheld, 1 cannot verify
g2 clean-java-log     no bug     FALSE-ALARM            gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g2 clean-migration    no bug     FALSE-ALARM            gemini; defense: 0 refuted, 2 upheld, 0 cannot verify
g2 clean-py           no bug     FALSE-ALARM            gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g2 clean-sql-transaction no bug     FALSE-ALARM            gemini; defense: 0 refuted, 2 upheld, 0 cannot verify
g2 sql-injection      HIGH+      CAUGHT BLOCKER (line)  gemini; defense: 0 refuted, 2 upheld, 0 cannot verify
g2 migration-not-null HIGH+      CAUGHT BLOCKER (line)  gemini; defense: 0 refuted, 2 upheld, 0 cannot verify
g2 sql-lost-update    HIGH+      CAUGHT BLOCKER (line)  gemini; defense: 0 refuted, 2 upheld, 0 cannot verify
g2 sql-update-no-where HIGH+      CAUGHT BLOCKER (line)  gemini; defense: 0 refuted, 2 upheld, 0 cannot verify
g2 missing-cleanup    MEDIUM+    CAUGHT HIGH (line)     gemini; defense: 0 refuted, 2 upheld, 0 cannot verify
g2 runner: gemini (its default); 5 of 10 as expected
g3 fixture            expected   result                 cost / note
g3 clean-sql          no bug     FALSE-ALARM            gemini; defense: 0 refuted, 1 upheld, 1 cannot verify
g3 clean-java-log     no bug     FALSE-ALARM            gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g3 clean-migration    no bug     PASS                   gemini
g3 clean-py           no bug     PASS                   gemini
g3 clean-sql-transaction no bug     FALSE-ALARM            gemini; defense: 0 refuted, 2 upheld, 0 cannot verify
g3 sql-injection      HIGH+      CAUGHT BLOCKER (line)  gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g3 migration-not-null HIGH+      CAUGHT BLOCKER (line)  gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g3 sql-lost-update    HIGH+      CAUGHT BLOCKER (line)  gemini; defense: 0 refuted, 3 upheld, 0 cannot verify
g3 sql-update-no-where HIGH+      CAUGHT BLOCKER (line)  gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g3 missing-cleanup    MEDIUM+    CAUGHT HIGH (line)     gemini; defense: 0 refuted, 1 upheld, 0 cannot verify
g3 runner: gemini (its default); 7 of 10 as expected
```
