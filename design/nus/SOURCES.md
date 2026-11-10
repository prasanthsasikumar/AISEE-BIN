# NUS Open House Guide: image sources

## NUS crest (AppIcon, NUSLogo)
- Source: Wikimedia Commons, "File:National University of Singapore logo print.jpg"
  https://commons.wikimedia.org/wiki/File:National_University_of_Singapore_logo_print.jpg
  (original: https://upload.wikimedia.org/wikipedia/commons/a/a7/National_University_of_Singapore_logo_print.jpg)
- Photo by Ralff Nestor Nacor (User:Ralffralff), 2023-08-19, CC BY-SA 4.0.
- Saved as `source/nus-logo-print.jpg` (4080x3072). It is a photograph of the crest on a glass wall, not a vector.
  The crest was perspective-corrected and masked from it (crop approx. x 220-540, y 140-570 at 1000 px width).
- No SVG of the NUS crest exists on Commons (searched "NUS coat of arms", "National University of Singapore logo").
- The NUS name and crest are NUS trademarks. Replace with the official artwork from NUS brand guidelines before release.
- Colours in the crest are the photo's (blue ~#007BCD, peach), not the NUS brand blue #003D7C used for the icon background.

## SoCat placeholder (SoCat, SoCatWave)
- OpenMoji, https://openmoji.org, `color/svg/1F408.svg` (cat, walking, side view) and `1F63A.svg` (smiling cat face).
  Raw: https://raw.githubusercontent.com/hfg-gmuend/openmoji/master/color/svg/
- Licence: CC BY-SA 4.0. Attribution: "OpenMoji - the open-source emoji and icon project. License: CC BY-SA 4.0".
  Share-alike applies to the artwork itself (the PNGs), not the app code. Placeholder only; NUS will supply real SoCat art.
- SVGs saved in `source/`. Rendered with resvg (resvg_py) and trimmed to the opaque bounding box.
