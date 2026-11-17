#!/usr/bin/env python3
import pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text()
passed=re.findall(r"Test Case .*OnDeviceMediaResolverTests.* passed",text)
if len(passed) < 6 or re.search(r"Test Case .* (?:skipped|failed)",text) or '** TEST SUCCEEDED **' not in text:
    raise SystemExit('Required actual-app adapter tests did not all execute successfully')
print(f'{len(passed)} actual-app adapter tests executed successfully; no skipped tests')
