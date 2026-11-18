import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'Engine/ParcChromium/pdf_link_contract.py'
spec = importlib.util.spec_from_file_location('pdf_link_contract', SCRIPT)
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)

NAVIGATOR = """export class NavigatorDelegateImpl implements NavigatorDelegate {
  navigateInNewTab(url: string, active: boolean) {
    if (chrome.tabs) {
      chrome.tabs.create({url: url, active: active});
    } else {
      window.open(url);
    }
  }

  navigateInNewWindow(url: string) {
    if (chrome.windows) {
      chrome.windows.create({url: url});
    } else {
      window.open(url, '_blank');
    }
  }
}

export class PdfNavigatorImpl implements PdfNavigator {
  async navigate(urlString: string, disposition: WindowOpenDisposition) {
    switch (disposition) {
      case WindowOpenDisposition.NEW_WINDOW:
        this.navigatorDelegate_.navigateInNewWindow(url.href);
        break;
    }
  }
}
"""


class PdfLinkContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.write(contract.NAVIGATOR, NAVIGATOR)
        self.write(f'{contract.PDF_RESOURCES}/main.ts', 'export const viewer = true;\n')

    def tearDown(self):
        self.temp.cleanup()

    def write(self, relative: str, text: str):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def edit(self, old: str, new: str):
        text = (self.root / contract.NAVIGATOR).read_text(encoding='utf-8')
        self.assertIn(old, text)
        self.write(contract.NAVIGATOR, text.replace(old, new))

    def problems(self):
        return contract.check(self.root)[1]

    def test_current_viewer_passes(self):
        self.assertEqual(self.problems(), [])

    def test_new_window_case_moving_away_fails(self):
        self.edit('this.navigatorDelegate_.navigateInNewWindow(url.href);',
                  'this.navigatorDelegate_.navigateInNewTab(url.href, true);')
        self.assertIn(f'{contract.NAVIGATOR} no longer sends a Shift-clicked link to '
                      'navigateInNewWindow', self.problems())

    def test_new_window_through_another_api_fails(self):
        self.edit('chrome.windows.create({url: url});', 'chrome.tabs.create({url: url});')
        problems = self.problems()
        self.assertIn(f'{contract.NAVIGATOR} no longer opens a Shift-clicked link with '
                      'chrome.windows.create({url: url})', problems)
        self.assertIn(f'{contract.PDF_RESOURCES} calls chrome.windows.create 0 times; Parc '
                      'treats every PDF viewer window request as a Shift-clicked link', problems)

    def test_second_window_request_fails(self):
        self.write(f'{contract.PDF_RESOURCES}/elements/viewer_toolbar.ts',
                   'chrome.windows.create({url: helpUrl});\n')
        self.assertIn(f'{contract.PDF_RESOURCES} calls chrome.windows.create 2 times; Parc '
                      'treats every PDF viewer window request as a Shift-clicked link',
                      self.problems())

    def test_missing_viewer_fails(self):
        (self.root / contract.NAVIGATOR).unlink()
        self.assertIn(f'{contract.NAVIGATOR} is missing', self.problems())

    def test_build_action_writes_stamp_and_depfile_or_fails_by_name(self):
        stamp, depfile = self.root / 'out/contract.stamp', self.root / 'out/contract.d'
        stamp.parent.mkdir()
        command = [sys.executable, str(SCRIPT), '--chromium', str(self.root),
                   '--stamp', str(stamp), '--depfile', str(depfile)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stamp.read_text(), 'ok\n')
        target, inputs = depfile.read_text().split(': ', 1)
        self.assertEqual(target, str(stamp))
        self.assertIn(str(self.root / contract.NAVIGATOR), inputs)
        self.assertIn(str(self.root / contract.PDF_RESOURCES / 'main.ts'), inputs)
        self.assertIn(str(self.root / contract.PDF_RESOURCES) + ' ', inputs)
        stamp.unlink()
        self.edit('chrome.windows.create({url: url});', "window.open(url, '_blank');")
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Parc PDF link contract failed', result.stderr)
        self.assertFalse(stamp.exists())


if __name__ == '__main__':
    unittest.main()
