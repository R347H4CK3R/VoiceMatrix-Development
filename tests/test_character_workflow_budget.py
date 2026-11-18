import pathlib, re, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class CharacterWorkflowBudgetTests(unittest.TestCase):
 def test_multi_launch_workflow_has_bounded_case_budget_without_relaxing_global_gate(self):
  source=(ROOT/'VoiceMatrixUITests/CharacterWorkflowUITests.swift').read_text()
  self.assertRegex(source,r'func testImportSelectListenAndKeepVoicesAfterRelaunch\(\)\s*\{\s*executionTimeAllowance = 180')
  self.assertIn('Imported references must survive an app restart',source)
  self.assertIn('Reference must play from its private copy with the import source gone',source)
  self.assertIn('XCTAssertGreaterThan((editor.value as? String ?? "").count, 500)',source)
  workflow=(ROOT/'.github/workflows/character-ui-smoke.yml').read_text()
  runs=[line for line in workflow.splitlines() if 'xcodebuild test-without-building ' in line]
  self.assertEqual(len(runs),4, 'unit/UI, import/relaunch, naming and saved RVC history must each run')
  for run in runs:
   self.assertIn('-test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300',run)
  self.assertIn('-only-testing:VoiceMatrixUITests/CharacterWorkflowUITests/testImportSelectListenAndKeepVoicesAfterRelaunch',runs[1])
  self.assertIn('-only-testing:VoiceMatrixUITests/CharacterWorkflowUITests/testUserAssignedNamePersistsAndCanBeReset',runs[2])
  self.assertIn('-only-testing:VoiceMatrixUITests/RVCHistoryUITests/testSeededHistorySelectsVerifiedCopyAcrossRelaunch',runs[3])
