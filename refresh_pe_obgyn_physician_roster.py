#!/usr/bin/env python3
"""
Recovered from mufflyt/isochrones (deleted by commit c426bcaed, restored via
private_equity branch import/isochrones-pe-assets, commit 99acdb7). Paths
below adapted from the original hardcoded /Users/tmuffly/isochrones to run
in this repo; no other logic changed.

Refresh the study-facing PE-backed OB/GYN physician roster.

This targeted rebuild uses live platform directories where they are reachable
from the current environment and applies an MD/DO-only inclusion rule.

Refreshed directly from live directories:
- Together Women's Health
- Axia Women's Health
- Advantia Health
- Women's Care

Preserved from the existing site-derived roster because the domains are timing
out from the current shell environment:
- Genesis OBGYN
- UWH of Texas

Outputs:
- outputs/private_equity_obgyn/pe_obgyn_physician_roster.csv
- outputs/private_equity_obgyn/pe_obgyn_physician_roster_with_npi.csv
"""

from __future__ import annotations

import csv
import html
import importlib.util
import json
import os
import re
import sys
from typing import Dict, List, Tuple


BUILD_SCRIPT_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "build_pe_obgyn_sample_frame.py"
)
OUTPUT_DIR = "outputs/private_equity_obgyn"
PHYSICIAN_OUTPUT = os.path.join(OUTPUT_DIR, "pe_obgyn_physician_roster.csv")
PHYSICIAN_WITH_NPI_OUTPUT = os.path.join(
    OUTPUT_DIR,
    "pe_obgyn_physician_roster_with_npi.csv",
)
TWH_LIVE_PATH = os.path.join(
    OUTPUT_DIR,
    "twh_live_gynecology_obstetrics_providers_2026-04-02.csv",
)


def load_builder_module():
    spec = importlib.util.spec_from_file_location(
        "pe_build_sample_frame",
        BUILD_SCRIPT_PATH,
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def dedupe_urls(urls: List[str]) -> List[str]:
    seen = set()
    deduped = []
    for url in urls:
        if not url:
            continue
        canonical = url.strip()
        if canonical in seen:
            continue
        seen.add(canonical)
        deduped.append(canonical)
    return deduped


def md_do_only(name: str) -> bool:
    return bool(re.search(r"\b(MD|DO)\b", name or "", re.I))


def normalize_state_label(value: str) -> str:
    state = (value or "").strip().upper()
    if state == "D.C.":
        return "DC"
    return state


def fetch_page(build_mod, url: str) -> str:
    return build_mod.fetch(url, sleep_s=0.0)


def extract_balanced_json_object(build_mod, text: str, marker: str) -> dict:
    unescaped = html.unescape(text)
    marker_idx = unescaped.find(marker)
    if marker_idx == -1:
        return {}
    start_idx = unescaped.find("{", marker_idx)
    if start_idx == -1:
        return {}
    chunk = build_mod.balanced_json_segment(unescaped, start_idx, "{", "}")
    if not chunk:
        return {}
    try:
        return json.loads(chunk)
    except json.JSONDecodeError:
        return {}


def parse_h1(build_mod, html_text: str) -> str:
    match = re.search(r"<h1[^>]*>(.*?)</h1>", html_text, re.I | re.S)
    if not match:
        return ""
    return build_mod.clean_address(match.group(1))


def parse_locality_parts(build_mod, locality_value) -> tuple[str, str, str]:
    locality_html = " ".join(locality_value or []) if isinstance(locality_value, list) else str(locality_value or "")
    raw_parts = [
        build_mod.clean_address(part)
        for part in re.split(r"<br\s*/?>", locality_html, flags=re.I)
        if build_mod.clean_address(part)
    ]
    city = raw_parts[0] if raw_parts else ""
    state = ""
    postal_code = ""
    if len(raw_parts) >= 2:
        state_line = raw_parts[1]
        zip_match = re.search(r"(\d{5}(?:-\d{4})?)$", state_line)
        if zip_match:
            postal_code = zip_match.group(1)
            state_line = state_line[: zip_match.start()].strip()
        state = build_mod.state_code_from_text(state_line) or build_mod.state_code_from_text(
            f"{state_line} {postal_code}".strip()
        )
    return city, state, postal_code


def build_physician_row(
    build_mod,
    platform,
    practice: dict,
    provider_name: str,
    provider_practice_name: str,
    provider_url: str,
    full_index,
    first_last_index,
    existing_provider_lookup,
    existing_name_state_lookup,
) -> dict | None:
    if not md_do_only(provider_name):
        return None

    practice_state = normalize_state_label(practice.get("state", ""))
    provider_key = provider_url.strip()
    normalized_name = build_mod.normalize_name(provider_name)
    name_state_key = (practice_state, normalized_name)

    if provider_key in existing_provider_lookup:
        npi, matched_name, match_status = existing_provider_lookup[provider_key]
    elif name_state_key in existing_name_state_lookup:
        npi, matched_name, match_status = existing_name_state_lookup[name_state_key]
    else:
        exact_matches = full_index.get((practice_state, normalized_name), [])
        if len(exact_matches) == 1:
            row = exact_matches[0]
            npi, matched_name, match_status = row["npi"], row["physician_name"], "exact"
        else:
            fl_key = build_mod.first_last_key(provider_name)
            fl_matches = first_last_index.get((practice_state, fl_key), [])
            if len(fl_matches) == 1:
                row = fl_matches[0]
                npi, matched_name, match_status = (
                    row["npi"],
                    row["physician_name"],
                    "first_last_exact",
                )
            elif len(exact_matches) > 1:
                npi, matched_name, match_status = "", provider_name, "ambiguous_exact"
            elif len(fl_matches) > 1:
                npi, matched_name, match_status = "", provider_name, "ambiguous_first_last"
            else:
                npi, matched_name, match_status = "", provider_name, "unmatched"

    return {
        "state": practice_state,
        "city": practice.get("city", ""),
        "platform": platform.platform,
        "pe_group": platform.pe_group,
        "practice_name": practice.get("practice_name", ""),
        "provider_page_practice_name": provider_practice_name,
        "provider_name_scraped": provider_name,
        "matched_physician_name": matched_name,
        "npi": npi,
        "npi_match_status": match_status,
        "practice_url": practice.get("practice_url", ""),
        "provider_url": provider_url,
        "ownership_source_url": platform.ownership_source_url,
    }


def build_existing_lookup(current_rows, build_mod) -> Tuple[dict, dict]:
    existing_provider_lookup = {}
    existing_name_state_lookup = {}
    for row in current_rows:
        npi = (row.get("npi") or "").strip()
        if not npi:
            continue
        provider_url = (row.get("provider_url") or "").strip()
        if provider_url:
            existing_provider_lookup[provider_url] = (
                npi,
                row.get("matched_physician_name", "") or row.get("provider_name_scraped", ""),
                row.get("npi_match_status", ""),
            )
        name_key = (
            normalize_state_label(row.get("state", "")),
            build_mod.normalize_name(row.get("provider_name_scraped", "")),
        )
        existing_name_state_lookup[name_key] = (
            npi,
            row.get("matched_physician_name", "") or row.get("provider_name_scraped", ""),
            row.get("npi_match_status", ""),
        )
    return existing_provider_lookup, existing_name_state_lookup


def build_together_rows(
    build_mod,
    full_index,
    first_last_index,
    existing_provider_lookup,
    existing_name_state_lookup,
) -> List[dict]:
    platform = next(p for p in build_mod.PLATFORMS if p.parser_type == "together")

    provider_practice_map: Dict[str, dict] = {}
    for state, state_page_url in platform.state_pages.items():
        state_html = fetch_page(build_mod, state_page_url)
        state_slug = state_page_url.rstrip("/").split("/")[-1]
        for practice_url in build_mod.together_practice_links(state_html, state_slug):
            if build_mod.candidate_rank(build_mod.practice_name_from_url(practice_url)) is None:
                continue
            practice = build_mod.parse_together_practice(practice_url)
            practice["state"] = practice.get("state") or state
            practice["state"] = normalize_state_label(practice.get("state", ""))
            for provider_url in practice.get("provider_urls", []):
                provider_practice_map.setdefault(provider_url, practice)

    live_rows = []
    with open(TWH_LIVE_PATH, newline="") as handle:
        for row in csv.DictReader(handle):
            if md_do_only(row.get("provider_name_live", "")):
                live_rows.append(dict(row))

    rows: List[dict] = []
    for live_row in live_rows:
        provider_url = (live_row.get("provider_url") or "").strip()
        practice = dict(provider_practice_map.get(provider_url, {}))
        if not practice:
            practice_label = (live_row.get("practice_city_live") or "").strip()
            practice_name = practice_label.rsplit(",", 1)[0].strip() if "," in practice_label else practice_label
            address = build_mod.clean_address(live_row.get("address_live", ""))
            practice = {
                "practice_name": practice_name,
                "city": build_mod.city_from_address(address),
                "state": build_mod.state_code_from_text(address),
                "address": address,
                "phone": "",
                "practice_url": "",
            }

        provider_name = build_mod.clean_address(live_row.get("provider_name_live", ""))
        row = build_physician_row(
            build_mod=build_mod,
            platform=platform,
            practice=practice,
            provider_name=provider_name,
            provider_practice_name=practice.get("practice_name", ""),
            provider_url=provider_url,
            full_index=full_index,
            first_last_index=first_last_index,
            existing_provider_lookup=existing_provider_lookup,
            existing_name_state_lookup=existing_name_state_lookup,
        )
        if row:
            rows.append(row)
    return rows


def axia_provider_urls(build_mod) -> List[str]:
    sitemap = fetch_page(build_mod, "https://axiawh.com/providers-sitemap.xml")
    urls = re.findall(r"<loc>(https://axiawh\.com/providers/[^<]+)</loc>", sitemap, re.I)
    return dedupe_urls(urls)


def parse_axia_provider_page(build_mod, provider_url: str) -> tuple[str, str, str]:
    page = fetch_page(build_mod, provider_url)
    provider_name = parse_h1(build_mod, page)
    if not provider_name:
        provider_name = build_mod.parse_title(page).split("|", 1)[0].strip()
    practice_name = ""
    practice_name_match = re.search(
        r'provider of trusted health care for the women of\s+([^".]+)',
        html.unescape(page),
        re.I,
    )
    if practice_name_match:
        practice_name = build_mod.clean_address(practice_name_match.group(1))
    location_urls = dedupe_urls(
        re.findall(r'href="(https://axiawh\.com/locations/[^"]+/)"', page, re.I)
    )
    first_location_url = location_urls[0] if location_urls else ""
    return provider_name, practice_name, first_location_url


def build_axia_rows(
    build_mod,
    full_index,
    first_last_index,
    existing_provider_lookup,
    existing_name_state_lookup,
) -> List[dict]:
    platform = next(p for p in build_mod.PLATFORMS if p.parser_type == "axia")
    practice_cache: Dict[str, dict] = {}
    rows: List[dict] = []

    provider_urls = axia_provider_urls(build_mod)
    for idx, provider_url in enumerate(provider_urls, start=1):
        if idx == 1 or idx % 50 == 0:
            print(f"Axia provider {idx}/{len(provider_urls)}")
        provider_name, provider_practice_name, practice_url = parse_axia_provider_page(
            build_mod,
            provider_url,
        )
        if not md_do_only(provider_name):
            continue

        practice = {
            "practice_name": provider_practice_name,
            "city": "",
            "state": "",
            "address": "",
            "phone": "",
            "practice_url": practice_url,
        }
        if practice_url:
            if practice_url not in practice_cache:
                practice_cache[practice_url] = build_mod.parse_axia_practice(practice_url)
            practice = dict(practice_cache[practice_url])
        if provider_practice_name and not practice.get("practice_name"):
            practice["practice_name"] = provider_practice_name

        row = build_physician_row(
            build_mod=build_mod,
            platform=platform,
            practice=practice,
            provider_name=provider_name,
            provider_practice_name=provider_practice_name or practice.get("practice_name", ""),
            provider_url=provider_url,
            full_index=full_index,
            first_last_index=first_last_index,
            existing_provider_lookup=existing_provider_lookup,
            existing_name_state_lookup=existing_name_state_lookup,
        )
        if row:
            rows.append(row)
    return rows


def advantia_provider_urls(build_mod) -> List[str]:
    page = fetch_page(build_mod, "https://advantiahealth.com/team/")
    urls = re.findall(
        r'href="(https?://(?:www\.)?advantiahealth\.com/team/[^"#?]+/)"',
        page,
        re.I,
    )
    cleaned = []
    for url in dedupe_urls(urls):
        if url.rstrip("/") in {
            "https://advantiahealth.com/team",
            "https://www.advantiahealth.com/team",
        }:
            continue
        if "/team/page/" in url or url.endswith("/feed/"):
            continue
        if "#cmplz" in url:
            continue
        cleaned.append(url.replace("https://advantiahealth.com", "https://www.advantiahealth.com"))
    return dedupe_urls(cleaned)


def parse_advantia_provider_page(build_mod, provider_url: str) -> tuple[str, str]:
    page = fetch_page(build_mod, provider_url)
    provider_name = parse_h1(build_mod, page)
    if not provider_name:
        provider_name = build_mod.parse_title(page).split("|", 1)[0].strip()
    location_urls = dedupe_urls(
        re.findall(
            r'href="(https://www\.advantiahealth\.com/locations/[^"]+/)"',
            page,
            re.I,
        )
    )
    first_location_url = location_urls[0] if location_urls else ""
    return provider_name, first_location_url


def build_advantia_rows(
    build_mod,
    full_index,
    first_last_index,
    existing_provider_lookup,
    existing_name_state_lookup,
) -> List[dict]:
    platform = next(p for p in build_mod.PLATFORMS if p.parser_type == "advantia")
    practice_cache: Dict[str, dict] = {}
    rows: List[dict] = []

    provider_urls = advantia_provider_urls(build_mod)
    for idx, provider_url in enumerate(provider_urls, start=1):
        if idx == 1 or idx % 25 == 0:
            print(f"Advantia provider {idx}/{len(provider_urls)}")
        provider_name, practice_url = parse_advantia_provider_page(build_mod, provider_url)
        if not md_do_only(provider_name):
            continue

        practice = {
            "practice_name": "",
            "city": "",
            "state": "",
            "address": "",
            "phone": "",
            "practice_url": practice_url,
        }
        if practice_url:
            if practice_url not in practice_cache:
                practice_cache[practice_url] = build_mod.parse_advantia_practice(practice_url)
            practice = dict(practice_cache[practice_url])

        row = build_physician_row(
            build_mod=build_mod,
            platform=platform,
            practice=practice,
            provider_name=provider_name,
            provider_practice_name=practice.get("practice_name", ""),
            provider_url=provider_url,
            full_index=full_index,
            first_last_index=first_last_index,
            existing_provider_lookup=existing_provider_lookup,
            existing_name_state_lookup=existing_name_state_lookup,
        )
        if row:
            rows.append(row)
    return rows


def womenscare_provider_urls(build_mod) -> List[str]:
    directory_page = fetch_page(build_mod, "https://www.womenscareobgyn.com/providers")
    slugs = re.findall(r"providers\\/([a-z0-9\-]+)", directory_page, re.I)
    urls = [
        f"https://www.womenscareobgyn.com/providers/{slug}"
        for slug in dedupe_urls([slug.rstrip("\\") for slug in slugs])
        if slug != "all-providers"
    ]
    return urls


def parse_womenscare_provider_page(build_mod, provider_url: str) -> tuple[str, dict]:
    page = fetch_page(build_mod, provider_url)
    provider_name = build_mod.parse_title(page).split("|", 1)[0].strip()
    related_locations = extract_balanced_json_object(
        build_mod,
        page,
        '"relatedLocationsSection":{',
    )
    locations = related_locations.get("locations") or []
    location = locations[0] if locations else {}

    city, state, postal_code = parse_locality_parts(build_mod, location.get("locality") or [])
    address_lines = build_mod.clean_address(location.get("addressLines", ""))
    city_state_zip = ", ".join(
        part
        for part in [
            city,
            " ".join(part for part in [state, postal_code] if part).strip(),
        ]
        if part
    )
    address = build_mod.clean_address(", ".join(part for part in [address_lines, city_state_zip] if part))

    practice = {
        "practice_name": build_mod.strip_tags(location.get("name", "")),
        "city": city or build_mod.city_from_address(address),
        "state": state or build_mod.state_code_from_text(address),
        "address": address,
        "phone": build_mod.strip_tags(location.get("phone_number", "")),
        "practice_url": location.get("uri", ""),
    }
    return provider_name, practice


def build_womenscare_rows(
    build_mod,
    full_index,
    first_last_index,
    existing_provider_lookup,
    existing_name_state_lookup,
) -> List[dict]:
    platform = next(p for p in build_mod.PLATFORMS if p.parser_type == "womenscare")
    rows: List[dict] = []
    provider_urls = womenscare_provider_urls(build_mod)
    for idx, provider_url in enumerate(provider_urls, start=1):
        if idx == 1 or idx % 50 == 0:
            print(f"Women's Care provider {idx}/{len(provider_urls)}")
        provider_name, practice = parse_womenscare_provider_page(build_mod, provider_url)
        row = build_physician_row(
            build_mod=build_mod,
            platform=platform,
            practice=practice,
            provider_name=provider_name,
            provider_practice_name=practice.get("practice_name", ""),
            provider_url=provider_url,
            full_index=full_index,
            first_last_index=first_last_index,
            existing_provider_lookup=existing_provider_lookup,
            existing_name_state_lookup=existing_name_state_lookup,
        )
        if row:
            rows.append(row)
    return rows


def preserve_requested_domain_rows(current_rows: List[dict]) -> List[dict]:
    preserved = []
    for row in current_rows:
        provider_url = row.get("provider_url") or ""
        practice_url = row.get("practice_url") or ""
        if "genesisobgyn.net" in provider_url or "genesisobgyn.net" in practice_url:
            if md_do_only(row.get("provider_name_scraped", "")):
                preserved.append(row)
            continue
        if "uwhtexas.com" in provider_url or "uwhtexas.com" in practice_url:
            if md_do_only(row.get("provider_name_scraped", "")):
                preserved.append(row)
            continue
    return preserved


def main() -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    build_mod = load_builder_module()
    original_fetch = build_mod.fetch
    build_mod.fetch = lambda url, sleep_s=0.0: original_fetch(url, sleep_s=0.0)
    _, full_index, first_last_index = build_mod.read_canonical()

    with open(PHYSICIAN_OUTPUT, newline="") as handle:
        current_rows = list(csv.DictReader(handle))

    existing_provider_lookup, existing_name_state_lookup = build_existing_lookup(
        current_rows,
        build_mod,
    )

    retained_rows = [
        row
        for row in current_rows
        if row.get("platform")
        not in {
            "Together Women's Health",
            "Axia Women's Health",
            "Advantia Health",
            "Women's Care",
        }
        and "genesisobgyn.net" not in (row.get("provider_url") or "")
        and "genesisobgyn.net" not in (row.get("practice_url") or "")
        and "uwhtexas.com" not in (row.get("provider_url") or "")
        and "uwhtexas.com" not in (row.get("practice_url") or "")
    ]

    refreshed_rows = (
        build_together_rows(
            build_mod,
            full_index,
            first_last_index,
            existing_provider_lookup,
            existing_name_state_lookup,
        )
        + build_axia_rows(
            build_mod,
            full_index,
            first_last_index,
            existing_provider_lookup,
            existing_name_state_lookup,
        )
        + build_advantia_rows(
            build_mod,
            full_index,
            first_last_index,
            existing_provider_lookup,
            existing_name_state_lookup,
        )
        + build_womenscare_rows(
            build_mod,
            full_index,
            first_last_index,
            existing_provider_lookup,
            existing_name_state_lookup,
        )
        + preserve_requested_domain_rows(current_rows)
    )

    combined_rows = retained_rows + refreshed_rows
    combined_rows.sort(
        key=lambda row: (
            row["state"],
            row["platform"],
            row["practice_name"],
            row["matched_physician_name"] or row["provider_name_scraped"],
            row["provider_url"],
        )
    )

    fieldnames = [
        "state",
        "city",
        "platform",
        "pe_group",
        "practice_name",
        "provider_page_practice_name",
        "provider_name_scraped",
        "matched_physician_name",
        "npi",
        "npi_match_status",
        "practice_url",
        "provider_url",
        "ownership_source_url",
    ]

    for output_path in [PHYSICIAN_OUTPUT, PHYSICIAN_WITH_NPI_OUTPUT]:
        with open(output_path, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(combined_rows)

    platform_counts: Dict[str, int] = {}
    for row in combined_rows:
        platform_counts[row["platform"]] = platform_counts.get(row["platform"], 0) + 1

    print(f"Wrote {len(combined_rows)} physician rows to {PHYSICIAN_OUTPUT}")
    print(f"Wrote {len(combined_rows)} physician rows to {PHYSICIAN_WITH_NPI_OUTPUT}")
    print("Platform counts:")
    for platform_name in sorted(platform_counts):
        print(f"  {platform_name}: {platform_counts[platform_name]}")


if __name__ == "__main__":
    main()
