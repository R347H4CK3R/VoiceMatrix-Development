import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class StandaloneQueueWiring(unittest.TestCase):
 def test_queue_never_sends_on_entry_or_saved_change(self):
  source=(ROOT/'VoiceMatrix/VideoQueueView.swift').read_text()
  self.assertNotIn('.task(id: saved)',source)
  self.assertEqual(source.count('await sendList('),1)
  self.assertIn('manualSend = Task { @MainActor in await sendList(videos) }',source)
  self.assertIn('@AppStorage("videoQueue.v1")',source)
  self.assertIn('Phone sending log',source)
 def test_local_route_and_explicit_laptop_actions(self):
  source=(ROOT/'VoiceMatrix/VideoQueueView.swift').read_text()
  self.assertIn('NavigationLink("Open on-iPhone Video Voice Studio")',source)
  self.assertIn('Adding or opening a list never sends it',source)
  self.assertIn('Request voice candidates on laptop',source)
 def test_laptop_tools_separate_from_primary_home_actions(self):
  source=(ROOT/'VoiceMatrix/App.swift').read_text()
  optional=source.index('DisclosureGroup("Optional laptop tools")')
  self.assertGreater(source.index('HomeCard(title: "Laptop RVC"'),optional)
  self.assertGreater(source.index('NavigationLink { VideoQueueView() }'),optional)
if __name__=='__main__': unittest.main()
