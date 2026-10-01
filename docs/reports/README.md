# Reports

Write-ups shared with the team, one folder per report, newest last.

| Date | Report |
|---|---|
| 2026-10-01 | [Flower Dome field test guide](2026-10-01-field-test-guide/) — instructions for the on-site tester |
| 2026-10-01 | [Flower Dome progress](2026-10-01-flower-dome-progress/) — one-page overview (two ways to scan, status, timeline), then detail: online vs on-device, web editor how-to, 1 Oct site test, glasses, links |

A report with a `report.html` is the source of its PDF. To rebuild the PDF after editing it:

```sh
cd docs/reports/<folder>
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --no-pdf-header-footer \
  --print-to-pdf="$PWD/<name>.pdf" "file://$PWD/report.html"
```
