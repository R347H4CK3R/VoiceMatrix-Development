from pathlib import Path
import hashlib
import unittest

class HistoryDialogPresenterTests(unittest.TestCase):
    def test_only_presenter_placement_changes(self):
        root=Path(__file__).resolve().parents[1]
        current=(root/'VoiceMatrix/CharacterLibraryView.swift').read_text()
        moved='        .confirmationDialog("Delete this retained audio and its check receipt? Export it first if you need a copy. This does not delete the voice reference.", isPresented: Binding(get: { speechHistoryDeletion != nil }, set: { if !$0 { speechHistoryDeletion = nil } })) {\n            Button("Delete retained result", role: .destructive) { if let id = speechHistoryDeletion { audio.stop(); library.deleteSpeechHistory(id) }; speechHistoryDeletion = nil }\n            Button("Cancel", role: .cancel) { speechHistoryDeletion = nil }\n        }\n'
        self.assertEqual(current.count(moved),1)
        self.assertIn(moved+'        .navigationTitle(mode == .speech',current)
        # Original 32ffcfa4 file with only the dialog modifier removed.
        self.assertEqual(hashlib.sha256(current.replace(moved,'').encode()).hexdigest(),'633c0bb82b6cd64a88f20132882d0d473fbe40c17cdb5db1b719c7a157d68454')
        self.assertEqual(current.count('.confirmationDialog("Delete this retained'),1)
        self.assertIn('Button("Cancel", role: .cancel) { speechHistoryDeletion = nil }',current)

if __name__=='__main__':unittest.main()
