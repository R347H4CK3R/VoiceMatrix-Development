import pathlib,shutil,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class UIRevealTests(unittest.TestCase):
 def test_bounded_drag_policy_converges_without_full_screen_oscillation(self):
  source=ROOT/'VoiceMatrixUITests/UIRevealPolicy.swift'
  self.assertTrue(source.is_file(),'Bounded reveal policy missing')
  if not shutil.which('swiftc'):self.skipTest('Swift toolchain unavailable; no native geometry claim')
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'main.swift').write_text('''import Foundation
let viewport=CGRect(x:0,y:100,width:430,height:589)
assert(UIRevealPolicy.offset(target:CGRect(x:0,y:200,width:300,height:48),viewport:viewport)==0)
assert(UIRevealPolicy.offset(target:CGRect(x:0,y:830.666,width:300,height:48),viewport:viewport)==120)
assert(UIRevealPolicy.offset(target:CGRect(x:0,y:20,width:300,height:48),viewport:viewport)==(-120))
for initial in [CGFloat(-200),CGFloat(20),CGFloat(830.666),CGFloat(1100)] {
 var target=CGRect(x:0,y:initial,width:300,height:48)
 for _ in 0..<10 {
  let offset=UIRevealPolicy.offset(target:target,viewport:viewport)
  assert(abs(offset)<=120)
  target.origin.y -= offset
 }
 assert(target.minY>viewport.minY && target.maxY<viewport.maxY)
}
print("Bounded UI geometry converges; this does not simulate UIKit gestures")
''')
   subprocess.run(['swiftc',str(source),str(p/'main.swift'),'-o',str(p/'check')],check=True)
   subprocess.run([str(p/'check')],check=True)
 def test_reveal_keeps_visibility_and_functional_assertions(self):
  s=(ROOT/'VoiceMatrixUITests/CharacterWorkflowUITests.swift').read_text()
  self.assertIn('UIRevealPolicy.offset',s)
  self.assertIn('for _ in 0..<10',s)
  for text in ['XCTAssertTrue(element.exists && element.isHittable)','XCTAssertGreaterThan(element.frame.minY, app.navigationBars.firstMatch.frame.maxY + 16)','XCTAssertLessThan(element.frame.maxY, app.tabBars.firstMatch.frame.minY - 160)','Imported references must survive an app restart','Reference must play from its private copy with the import source gone']:
   self.assertIn(text,s)
