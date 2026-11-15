# Bounded reference screening pool (selection policy 4)

The previous on-device selector retained only three turns before music/noise
screening. Three contaminated turns could therefore prevent a later clean turn
from ever reaching screening. Policy 4 considers up to six candidates while the
studio keeps its existing limit of three F5 preview-generation attempts. This
can increase screening/transcription time and retained attempt storage, but does
not increase simultaneous model concurrency or the generation-attempt budget.

Existing overlap subtraction, 150 ms edge trimming, quality thresholds, word
verification and voice preservation are unchanged. Distinct turns remain ranked
by duration then start before shorter tail crops. This is reference recovery,
not music isolation, overlap separation or a guarantee of clean speech.

Retained policies nil/1/2/3 validate their original exact windows before being
upgraded. A v4 record validates against six-candidate selection. Existing source
and original analysis files remain retained by the studio's current upgrade path.

Compiled Swift tests cover a fourth reachable turn, six-candidate cap, overlap
exclusion, rejected unbounded input, and legacy migration with both short pauses
and long single turns. Classifier decisions in the reachability case are
synthetic. Real iPhone classification, synthesis quality and performance are not
established by those policy tests. Native XCTest additionally covers the cap;
Apple compilation/execution must be reported separately when actually run.
