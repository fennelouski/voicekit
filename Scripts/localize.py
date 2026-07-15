#!/usr/bin/env python3
"""Generate Resources/<locale>.lproj/{Localizable,InfoPlist}.strings for every
macOS UI locale from the per-language JSON in Scripts/i18n/.

en.json is the source of truth for the key set. Any key missing from a
language falls back to the English base (and is reported), so a partially
translated language still ships a complete, working .strings file.

Run:  python3 Scripts/localize.py        # writes Resources/*.lproj
      python3 Scripts/localize.py --check # non-zero exit if any key is missing
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
I18N = os.path.join(ROOT, "Scripts", "i18n")
OUT = os.path.join(ROOT, "Resources")

# locale folder -> language JSON it draws from. Regional variants inherit their
# parent language; only where a variant genuinely differs does it get its own file.
LOCALES = {
    "en": "en", "en-AU": "en", "en-GB": "en", "en-IN": "en",
    "ar": "ar", "ca": "ca", "cs": "cs", "da": "da", "de": "de", "el": "el",
    "es": "es", "es-419": "es", "fi": "fi", "fr": "fr", "fr-CA": "fr",
    "he": "he", "hi": "hi", "hr": "hr", "hu": "hu", "id": "id", "it": "it",
    "ja": "ja", "ko": "ko", "ms": "ms", "nb": "nb", "nl": "nl", "pl": "pl",
    "pt-BR": "pt-BR", "pt-PT": "pt-BR", "ro": "ro", "ru": "ru", "sk": "sk",
    "sv": "sv", "th": "th", "tr": "tr", "uk": "uk", "vi": "vi",
    "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "zh-HK": "zh-Hant",
}

def esc(s):
    return (s.replace("\\", "\\\\").replace('"', '\\"')
             .replace("\n", "\\n").replace("\t", "\\t"))

def load(lang):
    path = os.path.join(I18N, f"{lang}.json")
    if not os.path.exists(path):
        return None
    return json.load(open(path, encoding="utf-8"))

def write_strings(path, mapping, order):
    lines = []
    for k in order:
        lines.append(f'"{esc(k)}" = "{esc(mapping[k])}";')
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

def main():
    check = "--check" in sys.argv
    base = load("en")
    if base is None:
        sys.exit("Scripts/i18n/en.json missing")
    loc_order = list(base["Localizable"].keys())
    info_order = list(base["InfoPlist"].keys())

    missing_total = 0
    for locale, lang in LOCALES.items():
        data = load(lang) or {}
        loc = dict(base["Localizable"])          # start from English
        info = dict(base["InfoPlist"])
        for k, v in (data.get("Localizable") or {}).items():
            if k in loc:
                loc[k] = v
        for k, v in (data.get("InfoPlist") or {}).items():
            if k in info:
                info[k] = v

        # count untranslated keys (only meaningful for non-English languages)
        if lang != "en":
            src = data.get("Localizable") or {}
            missing = [k for k in loc_order if k not in src]
            missing_total += len(missing)
            if missing:
                print(f"  {locale}: {len(missing)} untranslated", file=sys.stderr)

        if not check:
            d = os.path.join(OUT, f"{locale}.lproj")
            os.makedirs(d, exist_ok=True)
            write_strings(os.path.join(d, "Localizable.strings"), loc, loc_order)
            write_strings(os.path.join(d, "InfoPlist.strings"), info, info_order)

    if not check:
        print(f"Wrote {len(LOCALES)} locales to Resources/")
    if check and missing_total:
        sys.exit(f"{missing_total} untranslated key(s) across languages")

if __name__ == "__main__":
    main()
