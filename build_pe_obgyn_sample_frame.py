#!/usr/bin/env python3
"""
Recovered from mufflyt/isochrones (deleted by commit c426bcaed, restored via
private_equity branch import/isochrones-pe-assets, commit 99acdb7). Paths
below adapted from the original hardcoded /Users/tmuffly/isochrones to run
in this repo; no other logic changed.

Build a verified PE-backed OB/GYN mystery-caller starter sample frame.

Current scope:
- Together Women's Health
- Axia Women's Health
- Advantia Health
- Women's Care
- Unified Women's Healthcare affiliate sites

Outputs:
- outputs/private_equity_obgyn/pe_obgyn_practice_sample_frame.csv
- outputs/private_equity_obgyn/pe_obgyn_physician_roster.csv
"""

from __future__ import annotations

import csv
import html
import json
import os
import re
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Tuple
from urllib.parse import urljoin

import requests


CANONICAL_PATH = os.environ.get(
    "PE_ABOG_CROSSWALK", os.path.expanduser("~/Desktop/canonical_abog_npi_LATEST.csv")
)
OUTPUT_DIR = "outputs/private_equity_obgyn"
PRACTICE_OUTPUT = os.path.join(OUTPUT_DIR, "pe_obgyn_practice_sample_frame.csv")
PHYSICIAN_OUTPUT = os.path.join(OUTPUT_DIR, "pe_obgyn_physician_roster.csv")

SESSION = requests.Session()
SESSION.headers.update(
    {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/123.0.0.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.google.com/",
    }
)

FETCH_CACHE: Dict[str, str] = {}

STATE_NAME_TO_ABBR = {
    "ALABAMA": "AL",
    "ALASKA": "AK",
    "ARIZONA": "AZ",
    "ARKANSAS": "AR",
    "CALIFORNIA": "CA",
    "COLORADO": "CO",
    "CONNECTICUT": "CT",
    "DELAWARE": "DE",
    "DISTRICT OF COLUMBIA": "DC",
    "FLORIDA": "FL",
    "GEORGIA": "GA",
    "HAWAII": "HI",
    "IDAHO": "ID",
    "ILLINOIS": "IL",
    "INDIANA": "IN",
    "IOWA": "IA",
    "KANSAS": "KS",
    "KENTUCKY": "KY",
    "LOUISIANA": "LA",
    "MAINE": "ME",
    "MARYLAND": "MD",
    "MASSACHUSETTS": "MA",
    "MICHIGAN": "MI",
    "MINNESOTA": "MN",
    "MISSISSIPPI": "MS",
    "MISSOURI": "MO",
    "MONTANA": "MT",
    "NEBRASKA": "NE",
    "NEVADA": "NV",
    "NEW HAMPSHIRE": "NH",
    "NEW JERSEY": "NJ",
    "NEW MEXICO": "NM",
    "NEW YORK": "NY",
    "NORTH CAROLINA": "NC",
    "NORTH DAKOTA": "ND",
    "OHIO": "OH",
    "OKLAHOMA": "OK",
    "OREGON": "OR",
    "PENNSYLVANIA": "PA",
    "RHODE ISLAND": "RI",
    "SOUTH CAROLINA": "SC",
    "SOUTH DAKOTA": "SD",
    "TENNESSEE": "TN",
    "TEXAS": "TX",
    "UTAH": "UT",
    "VERMONT": "VT",
    "VIRGINIA": "VA",
    "WASHINGTON": "WA",
    "WEST VIRGINIA": "WV",
    "WISCONSIN": "WI",
    "WYOMING": "WY",
}


@dataclass(frozen=True)
class PlatformConfig:
    platform: str
    parser_type: str
    pe_group: str
    ownership_source_url: str
    ownership_source_note: str
    state_pages: Dict[str, str]


PLATFORMS: Sequence[PlatformConfig] = (
    PlatformConfig(
        platform="Together Women's Health",
        parser_type="together",
        pe_group="Shore Capital",
        ownership_source_url=(
            "https://togetherwomenshealth.com/partnership/resources/news/"
            "together-women-s-health-expands-mississippi-footprint-with-five-"
            "strategic-practice-affiliations-through-women-s-health-of-mississippi-partnership"
        ),
        ownership_source_note=(
            "Official Together Women's Health news page states Shore Capital is an investor."
        ),
        state_pages={
            "AL": "https://togetherwomenshealth.com/locations/alabama",
            "CO": "https://togetherwomenshealth.com/locations/colorado",
            "GA": "https://togetherwomenshealth.com/locations/georgia",
            "IL": "https://togetherwomenshealth.com/locations/illinois",
            "KY": "https://togetherwomenshealth.com/locations/kentucky",
            "MI": "https://togetherwomenshealth.com/locations/michigan",
            "MO": "https://togetherwomenshealth.com/locations/missouri",
            "MS": "https://togetherwomenshealth.com/locations/mississippi",
            "TN": "https://togetherwomenshealth.com/locations/tennessee",
        },
    ),
    PlatformConfig(
        platform="Axia Women's Health",
        parser_type="axia",
        pe_group="Partners Group",
        ownership_source_url=(
            "https://e3.marco.ch/publish/partnersgroup/36_9678/"
            "20210505_EQUI__Axia_Women_s_Health_FINAL.pdf"
        ),
        ownership_source_note=(
            "Official Partners Group press release announcing acquisition of Axia Women's Health."
        ),
        state_pages={
            "IN": "https://axiawh.com/care-by-state/in/",
            "KY": "https://axiawh.com/care-by-state/ky/",
            "NJ": "https://axiawh.com/care-by-state/nj/",
            "PA": "https://axiawh.com/care-by-state/pa/",
        },
    ),
    PlatformConfig(
        platform="Advantia Health",
        parser_type="advantia",
        pe_group="Deerfield Management",
        ownership_source_url=(
            "https://www.advantiahealth.com/news/"
            "advantia-health-announces-45m-investment-to-accelerate-expansion/"
        ),
        ownership_source_note=(
            "Official Advantia press release states Deerfield remained Advantia's largest investor."
        ),
        state_pages={
            "DC": "https://www.advantiahealth.com/locations/",
            "IL": "https://www.advantiahealth.com/locations/",
            "MD": "https://www.advantiahealth.com/locations/",
            "MO": "https://www.advantiahealth.com/locations/",
            "VA": "https://www.advantiahealth.com/locations/",
        },
    ),
    PlatformConfig(
        platform="Women's Care",
        parser_type="womenscare",
        pe_group="BC Partners",
        ownership_source_url="https://www.bcpartners.com/portfolio/womens-care-enterprises/",
        ownership_source_note="Current BC Partners portfolio page for Women's Care Enterprises.",
        state_pages={
            "AZ": "https://www.womenscareobgyn.com/locations/",
            "FL": "https://www.womenscareobgyn.com/locations/",
        },
    ),
    PlatformConfig(
        platform="Unified Women's Healthcare",
        parser_type="uwh_marker",
        pe_group="Altas Partners / Ares PE / Oak HC/FT",
        ownership_source_url=(
            "https://unifiedwomenshealthcare.com/"
            "unified-womens-healthcare-acquires-womens-health-usa/"
        ),
        ownership_source_note=(
            "Official Unified release states backing from Altas, Ares PE, and Oak HC/FT."
        ),
        state_pages={
            "AZ": "https://genesisobgyn.net/locations/",
            "CT": "https://womenshealthct.com/locations/",
            "TX": "https://uwhtexas.com/locations/",
        },
    ),
    PlatformConfig(
        platform="Unified Women's Healthcare",
        parser_type="uwh_whasn",
        pe_group="Altas Partners / Ares PE / Oak HC/FT",
        ownership_source_url=(
            "https://unifiedwomenshealthcare.com/"
            "unified-womens-healthcare-acquires-womens-health-usa/"
        ),
        ownership_source_note=(
            "Official Unified release states backing from Altas, Ares PE, and Oak HC/FT."
        ),
        state_pages={
            "NV": "https://whasn.com/locations/",
        },
    ),
)


EXCLUDE_PATTERNS = re.compile(
    r"(urogyn|urogyne|fertility|pelvic|imaging|perinatal|maternal-fetal|mfm)",
    re.I,
)
INCLUDE_PATTERNS = re.compile(
    r"(ob[\s-]?gyn|obstet|gyne|women|womans|woman s)",
    re.I,
)


def fetch(url: str, sleep_s: float = 0.15) -> str:
    if url in FETCH_CACHE:
        return FETCH_CACHE[url]
    response = SESSION.get(url, timeout=30)
    response.raise_for_status()
    time.sleep(sleep_s)
    FETCH_CACHE[url] = response.text
    return response.text


def strip_tags(text: str) -> str:
    text = re.sub(r"<br\s*/?>", "\n", text or "", flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    return html.unescape(re.sub(r"\s+", " ", text)).strip()


def clean_address(text: str) -> str:
    text = strip_tags(text)
    text = re.sub(r"\s*,\s*", ", ", text)
    return re.sub(r"\s+", " ", text).strip(" ,")


def normalize_name(text: str) -> str:
    text = html.unescape(text or "")
    text = text.upper()
    text = re.sub(r"\b(MD|M\.D\.|DO|D\.O\.|FACOG|FACS|CNM|CRNP|NP|WHNP|MSN|PA-C|PA)\b", "", text)
    text = re.sub(r"[^A-Z ]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def first_last_key(text: str) -> str:
    parts = normalize_name(text).split()
    if len(parts) >= 2:
        return f"{parts[0]} {parts[-1]}"
    return " ".join(parts)


def split_first_last(text: str) -> Tuple[str, str]:
    parts = normalize_name(text).split()
    if len(parts) >= 2:
        return parts[0].title(), parts[-1].title()
    if len(parts) == 1:
        return parts[0].title(), ""
    return "", ""


def state_code_from_text(text: str) -> str:
    cleaned = clean_address(text).upper()
    normalized = cleaned.replace(".", "").strip()
    if normalized in STATE_NAME_TO_ABBR.values():
        return normalized
    if normalized in STATE_NAME_TO_ABBR:
        return STATE_NAME_TO_ABBR[normalized]
    match = re.search(r",\s*([A-Z]{2})\s+\d{5}(?:-\d{4})?$", cleaned)
    if match:
        return match.group(1)
    match = re.search(r",\s*([A-Z][A-Z ]+)\s+\d{5}(?:-\d{4})?$", cleaned)
    if match:
        return STATE_NAME_TO_ABBR.get(match.group(1).strip(), "")
    return ""


def city_from_address(address: str) -> str:
    cleaned = clean_address(address)
    match = re.search(r"([A-Za-z .'-]+),\s*(?:[A-Z]{2}|[A-Za-z ]+)\s+\d{5}(?:-\d{4})?$", cleaned)
    return match.group(1).strip() if match else ""


def text_value(value: object) -> str:
    if isinstance(value, dict):
        return str(value.get("name", "")).strip()
    return str(value or "").strip()


def read_canonical() -> Tuple[List[dict], Dict[Tuple[str, str], List[dict]], Dict[Tuple[str, str], List[dict]]]:
    rows: List[dict] = []
    full_index: Dict[Tuple[str, str], List[dict]] = {}
    first_last_index: Dict[Tuple[str, str], List[dict]] = {}

    with open(CANONICAL_PATH, newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            row = dict(row)
            row["state"] = (row.get("state") or "").strip().upper()
            row["normalized_name"] = normalize_name(row.get("physician_name", ""))
            row["first_last_key"] = first_last_key(row.get("physician_name", ""))
            rows.append(row)
            full_index.setdefault((row["state"], row["normalized_name"]), []).append(row)
            first_last_index.setdefault((row["state"], row["first_last_key"]), []).append(row)

    return rows, full_index, first_last_index


NPI_SEARCH_CACHE: Dict[Tuple[str, str, str], Tuple[str, str, str]] = {}


def search_npi_registry(provider_name: str, state: str) -> Tuple[str, str, str]:
    cache_key = (provider_name, state, "npi_registry")
    if cache_key in NPI_SEARCH_CACHE:
        return NPI_SEARCH_CACHE[cache_key]

    first_name, last_name = split_first_last(provider_name)
    if not first_name or not last_name:
        result = ("", provider_name, "unmatched")
        NPI_SEARCH_CACHE[cache_key] = result
        return result

    params = {
        "version": "2.1",
        "first_name": first_name,
        "last_name": last_name,
        "state": state.upper(),
        "limit": "20",
    }
    url = "https://npiregistry.cms.hhs.gov/api/?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            payload = response.read().decode("utf-8")
        data = json.loads(payload)
    except Exception:
        result = ("", provider_name, "unmatched")
        NPI_SEARCH_CACHE[cache_key] = result
        return result

    physician_hits: List[Tuple[str, str]] = []
    for result_row in data.get("results", []):
        taxonomies = result_row.get("taxonomies", [])
        if not any((tax.get("code") or "").upper().startswith("207V") for tax in taxonomies):
            continue
        basic = result_row.get("basic", {})
        full_name = " ".join(
            part
            for part in [basic.get("first_name", "").title(), basic.get("last_name", "").title()]
            if part
        ).strip()
        physician_hits.append((result_row.get("number", ""), full_name or provider_name))

    unique_hits = sorted(set(physician_hits))
    if len(unique_hits) == 1:
        npi, matched_name = unique_hits[0]
        result = (npi, matched_name, "api_unique_207V")
    elif len(unique_hits) > 1:
        result = ("", provider_name, "ambiguous_api")
    else:
        result = ("", provider_name, "unmatched")

    NPI_SEARCH_CACHE[cache_key] = result
    return result


def match_provider(
    provider_name: str,
    state: str,
    full_index: Dict[Tuple[str, str], List[dict]],
    first_last_index: Dict[Tuple[str, str], List[dict]],
) -> Tuple[str, str, str]:
    normalized = normalize_name(provider_name)
    state = state.upper()
    exact_matches = full_index.get((state, normalized), [])
    if len(exact_matches) == 1:
        row = exact_matches[0]
        return row["npi"], row["physician_name"], "exact"
    if len(exact_matches) > 1:
        return "", provider_name, "ambiguous_exact"

    fl_key = first_last_key(provider_name)
    fl_matches = first_last_index.get((state, fl_key), [])
    if len(fl_matches) == 1:
        row = fl_matches[0]
        return row["npi"], row["physician_name"], "first_last_exact"
    if len(fl_matches) > 1:
        return "", provider_name, "ambiguous_first_last"

    return search_npi_registry(provider_name, state)


def parse_title(html_text: str) -> str:
    match = re.search(r"<title>(.*?)</title>", html_text, re.I | re.S)
    return strip_tags(match.group(1)) if match else ""


def practice_name_from_url(url: str) -> str:
    slug = url.rstrip("/").split("/")[-1]
    return slug.replace("-", " ").strip()


def candidate_rank(label: str, provider_count: int = 0) -> Optional[Tuple[int, str]]:
    cleaned = strip_tags(label)
    if EXCLUDE_PATTERNS.search(cleaned):
        return None
    score = 0
    if INCLUDE_PATTERNS.search(cleaned):
        score += 10
    if provider_count:
        score += 1
    return score, cleaned.lower()


def choose_general_practice(urls: Iterable[str]) -> Optional[str]:
    ranked: List[Tuple[int, str, str]] = []
    for url in urls:
        rank = candidate_rank(practice_name_from_url(url))
        if rank is None:
            continue
        score, label = rank
        ranked.append((score, label, url))
    if not ranked:
        return None
    ranked.sort(key=lambda row: (-row[0], row[1], row[2]))
    return ranked[0][2]


def balanced_json_segment(text: str, start_idx: int, open_char: str, close_char: str) -> str:
    depth = 0
    in_string = False
    escaped = False
    for idx in range(start_idx, len(text)):
        char = text[idx]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
            continue
        if char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1
            if depth == 0:
                return text[start_idx : idx + 1]
    return ""


def extract_balanced_json_array(text: str, marker: str) -> List[dict]:
    unescaped = html.unescape(text)
    marker_idx = unescaped.find(marker)
    if marker_idx == -1:
        return []
    start_idx = unescaped.find("[", marker_idx)
    if start_idx == -1:
        return []
    chunk = balanced_json_segment(unescaped, start_idx, "[", "]")
    if not chunk:
        return []
    try:
        return json.loads(chunk)
    except json.JSONDecodeError:
        return []


def extract_create_marker_objects(text: str) -> List[dict]:
    unescaped = html.unescape(text)
    objects: List[dict] = []
    for match in re.finditer(r"createMarker\(", unescaped):
        brace_start = unescaped.find("{", match.end())
        if brace_start == -1:
            continue
        chunk = balanced_json_segment(unescaped, brace_start, "{", "}")
        if not chunk:
            continue
        try:
            objects.append(json.loads(chunk))
        except json.JSONDecodeError:
            continue
    return objects


def together_practice_links(state_page_html: str, state_slug: str) -> List[str]:
    links = re.findall(r'href="(/locations/[^"]+)"', state_page_html)
    unique_links: List[str] = []
    seen = set()
    for link in links:
        if not link.startswith("/locations/"):
            continue
        parts = link.strip("/").split("/")
        if len(parts) != 4:
            continue
        if parts[1] != state_slug:
            continue
        if link not in seen:
            seen.add(link)
            unique_links.append(urljoin("https://togetherwomenshealth.com", link))
    return unique_links


def axia_practice_links(state_page_html: str) -> List[str]:
    links = re.findall(r'href="(https://axiawh\.com/locations/[^"]+/)"', state_page_html)
    unique_links: List[str] = []
    seen = set()
    for link in links:
        if link.endswith("/locations/"):
            continue
        if link not in seen:
            seen.add(link)
            unique_links.append(link)
    return unique_links


def advantia_practice_links(state_page_html: str) -> List[str]:
    links = re.findall(r'href="(https://www\.advantiahealth\.com/locations/[^"]+/)"', state_page_html)
    unique_links: List[str] = []
    seen = set()
    for link in links:
        slug = link.rstrip("/").split("/")[-1]
        if link.rstrip("/") == "https://www.advantiahealth.com/locations":
            continue
        if "/page/" in link:
            continue
        if slug in {"feed", "category", "tag", "author"}:
            continue
        if link not in seen:
            seen.add(link)
            unique_links.append(link)
    return unique_links


def whasn_location_links(state_page_html: str) -> List[str]:
    links = re.findall(r'href="(https://whasn\.com/locations/[^"]+/)"', state_page_html)
    unique_links: List[str] = []
    seen = set()
    for link in links:
        if link.rstrip("/") == "https://whasn.com/locations":
            continue
        if link not in seen:
            seen.add(link)
            unique_links.append(link)
    return unique_links


def parse_together_practice(practice_url: str) -> dict:
    page = fetch(practice_url)
    title = parse_title(page)
    match = re.match(r"([^|]+?)\s*\|\s*Together Women", title)
    title_left = match.group(1).strip() if match else title
    city = ""
    practice_name = ""
    if " - " in title_left:
        city, practice_name = [part.strip() for part in title_left.split(" - ", 1)]
    else:
        practice_name = title_left.strip()

    address = ""
    if practice_name and city:
        addr_pattern = re.escape(practice_name) + r"</div><div[^>]*>" + r"([^<]*" + re.escape(city) + r"[^<]*)</div>"
        addr_match = re.search(addr_pattern, page, re.I)
        if addr_match:
            address = strip_tags(addr_match.group(1))

    phone_match = re.search(r'href="tel:([^"]+)"', page, re.I)
    phone = phone_match.group(1).strip() if phone_match else ""

    provider_links = re.findall(r'href="(/providers/[^"]+)"', page)
    provider_urls = []
    seen = set()
    for link in provider_links:
        full = urljoin("https://togetherwomenshealth.com", link)
        if full not in seen:
            seen.add(full)
            provider_urls.append(full)

    state_match = re.search(r",\s*([A-Z]{2}),\s*\d{5}", address)
    state = state_match.group(1) if state_match else ""

    return {
        "practice_name": practice_name or practice_name_from_url(practice_url),
        "city": city,
        "state": state,
        "address": address,
        "phone": phone,
        "practice_url": practice_url,
        "provider_urls": provider_urls,
    }


def parse_axia_practice(practice_url: str) -> dict:
    page = fetch(practice_url)
    title = parse_title(page)
    title_left = title.replace("- Axia Women's Health", "").strip()
    city = ""

    og_title_match = re.search(r'<meta property="og:title" content="([^"]+)"', page, re.I)
    og_title = html.unescape(og_title_match.group(1)).replace(" - Axia Women's Health", "").strip() if og_title_match else ""

    name_match = re.search(r'<meta name="description" content="([^"]+)"', page, re.I)
    description = html.unescape(name_match.group(1)) if name_match else ""
    practice_name = ""
    if og_title:
        practice_name = og_title
    if description:
        lead_match = re.match(
            r"^(.*?)(?:\s+(?:has been|is considered|is a proud|provides|offers)\b|$)",
            description,
            re.I,
        )
        description_lead = lead_match.group(1).strip() if lead_match else description.strip()
        if description_lead:
            practice_name = description_lead
    if not practice_name:
        practice_name = title_left

    addr_match = re.search(
        r'<address[^>]*class="location-contact-information__address"[^>]*>.*?'
        r'href="https://www\.google\.com/maps/\?q=([^"]+)".*?'
        r'href="tel:([^"]+)".*?</address>',
        page,
        re.I | re.S,
    )
    address = html.unescape(addr_match.group(1)) if addr_match else ""
    address = clean_address(address.replace("+", " "))
    phone = addr_match.group(2) if addr_match else ""
    phone = re.sub(r"^\+?1", "", phone)

    provider_urls = re.findall(r'href="(https://axiawh\.com/providers/[^"]+/)"', page)
    provider_urls = list(dict.fromkeys(provider_urls))

    state = state_code_from_text(address)
    city = city_from_address(address) or city

    return {
        "practice_name": practice_name or practice_name_from_url(practice_url),
        "city": city,
        "state": state,
        "address": address,
        "phone": phone,
        "practice_url": practice_url,
        "provider_urls": provider_urls,
    }


def parse_advantia_practice(practice_url: str) -> dict:
    page = fetch(practice_url)
    unescaped_page = html.unescape(page)
    title = parse_title(page)
    title_left = title.split("|", 1)[0].strip()
    title_state = ""
    title_parts = [part.strip() for part in title_left.rsplit(", ", 2)]
    if len(title_parts) == 3:
        practice_name, city, title_state = title_parts
    elif len(title_parts) == 2:
        practice_name, city = title_parts
    else:
        practice_name, city = title_left, ""

    street_match = re.search(r'"streetAddress"\s*:\s*"([^"]+)"', unescaped_page, re.I)
    locality_match = re.search(r'"addressLocality"\s*:\s*"([^"]+)"', unescaped_page, re.I)
    region_match = re.search(r'"addressRegion"\s*:\s*"([^"]+)"', unescaped_page, re.I)
    postal_match = re.search(r'"postalCode"\s*:\s*"([^"]+)"', unescaped_page, re.I)
    address = ""
    state = ""
    if street_match and locality_match and postal_match:
        street = street_match.group(1)
        locality = locality_match.group(1)
        region = region_match.group(1) if region_match else state_code_from_text(locality)
        locality_city = locality.split(",", 1)[0].strip()
        postal_code = postal_match.group(1)
        if region:
            address = f"{strip_tags(street)}, {locality_city}, {region} {postal_code}"
        else:
            address = f"{strip_tags(street)}, {locality} {postal_code}"
        city = locality_city
        state = region

    phone_match = re.search(r'"telephone"\s*:\s*"([^"]+)"', unescaped_page, re.I)
    if not phone_match:
        phone_match = re.search(r'href="tel:([^"]+)"', page, re.I)
    phone = phone_match.group(1).strip() if phone_match else ""

    provider_links = re.findall(r'href="(https://www\.advantiahealth\.com/team/[^"]+/)"', page)
    provider_urls = list(dict.fromkeys(provider_links))

    return {
        "practice_name": practice_name or practice_name_from_url(practice_url),
        "city": city,
        "state": state or state_code_from_text(address) or state_code_from_text(title_state),
        "address": clean_address(address),
        "phone": phone,
        "practice_url": practice_url,
        "provider_urls": provider_urls,
    }


def parse_womenscare_practice(store: dict) -> dict:
    practice_url = store.get("uri", "")
    page = fetch(practice_url)
    title = parse_title(page)
    practice_name = title.split("|", 1)[0].strip() or "Women's Care"

    address = clean_address(store.get("name", ""))
    phone = store.get("phoneNumber", "").strip()
    staff = extract_balanced_json_array(page, '"staff":[{')
    provider_urls = [
        member.get("url", "")
        for member in staff
        if member.get("url")
    ]

    return {
        "practice_name": practice_name,
        "city": city_from_address(address),
        "state": state_code_from_text(address),
        "address": address,
        "phone": phone,
        "practice_url": practice_url,
        "provider_urls": list(dict.fromkeys(provider_urls)),
    }


def parse_marker_site_practice(marker: dict) -> dict:
    practice = marker.get("practice") or {}
    practice_name = practice.get("name") or marker.get("name") or ""
    practice_url = practice.get("url", "")
    address = clean_address(marker.get("address", ""))
    provider_urls = [
        provider.get("url", "")
        for provider in (marker.get("providers") or {}).values()
        if provider.get("url")
    ]

    return {
        "practice_name": practice_name,
        "city": text_value(marker.get("city")) or city_from_address(address),
        "state": state_code_from_text(text_value(marker.get("state"))) or state_code_from_text(address),
        "address": address,
        "phone": strip_tags(marker.get("phone", "")),
        "practice_url": practice_url,
        "provider_urls": list(dict.fromkeys(provider_urls)),
    }


def parse_whasn_practice(practice_url: str) -> dict:
    page = fetch(practice_url)
    title = parse_title(page)
    practice_name = title.split("·", 1)[0].split("|", 1)[0].strip()

    address_match = re.search(r"<h3>\s*Address\s*</h3>\s*<p>(.*?)</p>", page, re.I | re.S)
    address = clean_address(address_match.group(1)) if address_match else ""
    phone_match = re.search(r'<a href="tel:[^"]+">\s*([^<]+)\s*</a>', page, re.I | re.S)
    phone = strip_tags(phone_match.group(1)) if phone_match else ""

    provider_links = re.findall(r'href="(https://whasn\.com/providers/[^"]+/?)"', page)
    provider_urls = list(dict.fromkeys(provider_links))

    return {
        "practice_name": practice_name or practice_name_from_url(practice_url),
        "city": city_from_address(address),
        "state": state_code_from_text(address),
        "address": address,
        "phone": phone,
        "practice_url": practice_url,
        "provider_urls": provider_urls,
    }


def parse_together_provider(provider_url: str) -> Tuple[str, str]:
    page = fetch(provider_url)
    title = parse_title(page)
    name = title.split("|", 1)[0].strip()
    practice_match = re.search(r'<meta property="og:title" content="[^"]+ - ([^"]+)"', page, re.I)
    practice_name = html.unescape(practice_match.group(1)).strip() if practice_match else ""
    return name, practice_name


def parse_axia_provider(provider_url: str) -> Tuple[str, str]:
    page = fetch(provider_url)
    title = parse_title(page)
    name = title.replace("- Axia Women's Health", "").strip()
    name = " ".join(part.strip() for part in reversed([p.strip() for p in name.split(",", 1)]))
    practice_match = re.search(
        r'<meta name="description" content="Dr\.\s+[^"]+?\s+is a leading provider of trusted health care for the women of\s+([^"]+?)\."',
        page,
        re.I,
    )
    practice_name = html.unescape(practice_match.group(1)).strip() if practice_match else ""
    return name, practice_name


def parse_generic_provider(provider_url: str) -> Tuple[str, str]:
    page = fetch(provider_url)
    title = parse_title(page)
    name = title.split("|", 1)[0].split("·", 1)[0].strip()
    return name, ""


def looks_like_physician(name: str) -> bool:
    return bool(re.search(r"\b(MD|DO)\b", name, re.I))


def choose_advantia_practice(state_html: str, state: str) -> Optional[dict]:
    links = choose_general_candidates_from_urls(advantia_practice_links(state_html))
    for practice_url in links:
        practice = parse_advantia_practice(practice_url)
        if practice.get("state") == state:
            return practice
    return None


def choose_general_candidates_from_urls(urls: Iterable[str]) -> List[str]:
    ranked: List[Tuple[int, str, str]] = []
    for url in urls:
        rank = candidate_rank(practice_name_from_url(url))
        if rank is None:
            continue
        score, label = rank
        ranked.append((score, label, url))
    ranked.sort(key=lambda row: (-row[0], row[1], row[2]))
    return [row[2] for row in ranked]


def choose_womenscare_practice(state_html: str, state: str) -> Optional[dict]:
    stores = extract_balanced_json_array(state_html, '"stores":[{')
    ranked: List[Tuple[int, str, str, dict]] = []
    for store in stores:
        address = store.get("name", "")
        if state_code_from_text(address) != state:
            continue
        specialties = " ".join(store.get("specialties") or [])
        rank = candidate_rank(specialties or address)
        if rank is None:
            continue
        score, label = rank
        ranked.append((score, label, store.get("uri", ""), store))
    ranked.sort(key=lambda row: (-row[0], row[1], row[2]))
    return parse_womenscare_practice(ranked[0][3]) if ranked else None


def choose_marker_site_practice(state_html: str, state: str) -> Optional[dict]:
    candidates: List[Tuple[int, str, str, dict]] = []
    for marker in extract_create_marker_objects(state_html):
        marker_state = state_code_from_text(text_value(marker.get("state"))) or state_code_from_text(marker.get("address", ""))
        if marker_state != state:
            continue
        practice = marker.get("practice") or {}
        label = practice.get("name") or marker.get("name") or ""
        rank = candidate_rank(label, provider_count=len(marker.get("providers") or {}))
        if rank is None:
            continue
        score, label_key = rank
        candidates.append((score, label_key, practice.get("url", ""), marker))
    candidates.sort(key=lambda row: (-row[0], row[1], row[2]))
    return parse_marker_site_practice(candidates[0][3]) if candidates else None


def choose_whasn_practice(state_html: str, state: str) -> Optional[dict]:
    candidates: List[Tuple[int, str, str, dict]] = []
    for location_url in whasn_location_links(state_html):
        practice = parse_whasn_practice(location_url)
        practice_state = practice.get("state") or state
        if practice_state != state:
            continue
        rank = candidate_rank(practice.get("practice_name", ""), provider_count=len(practice.get("provider_urls", [])))
        if rank is None:
            continue
        score, label = rank
        candidates.append((score, label, location_url, practice))
    candidates.sort(key=lambda row: (-row[0], row[1], row[2]))
    return candidates[0][3] if candidates else None


def build_practice_for_state(platform: PlatformConfig, state: str, state_page_url: str) -> Optional[dict]:
    state_html = fetch(state_page_url)

    if platform.parser_type == "together":
        state_slug = state_page_url.rstrip("/").split("/")[-1]
        chosen = choose_general_practice(together_practice_links(state_html, state_slug=state_slug))
        return parse_together_practice(chosen) if chosen else None
    if platform.parser_type == "axia":
        chosen = choose_general_practice(axia_practice_links(state_html))
        return parse_axia_practice(chosen) if chosen else None
    if platform.parser_type == "advantia":
        return choose_advantia_practice(state_html, state)
    if platform.parser_type == "womenscare":
        return choose_womenscare_practice(state_html, state)
    if platform.parser_type == "uwh_marker":
        return choose_marker_site_practice(state_html, state)
    if platform.parser_type == "uwh_whasn":
        return choose_whasn_practice(state_html, state)
    return None


def provider_parser_for_platform(platform: PlatformConfig):
    if platform.parser_type == "together":
        return parse_together_provider
    if platform.parser_type == "axia":
        return parse_axia_provider
    return parse_generic_provider


def main() -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    _, full_index, first_last_index = read_canonical()

    practice_rows: List[dict] = []
    physician_rows: List[dict] = []

    for platform in PLATFORMS:
        for state, state_page_url in platform.state_pages.items():
            practice = build_practice_for_state(platform, state, state_page_url)
            if not practice:
                continue

            practice_state = practice.get("state") or state
            practice_row = {
                "state": practice_state,
                "city": practice.get("city", ""),
                "platform": platform.platform,
                "pe_group": platform.pe_group,
                "practice_name": practice.get("practice_name", ""),
                "address": practice.get("address", ""),
                "phone": practice.get("phone", ""),
                "practice_url": practice.get("practice_url", ""),
                "ownership_source_url": platform.ownership_source_url,
                "ownership_source_note": platform.ownership_source_note,
                "n_physician_pages_found": len(practice.get("provider_urls", [])),
            }
            practice_rows.append(practice_row)

            provider_parser = provider_parser_for_platform(platform)
            seen_provider_urls = set()
            for provider_url in practice.get("provider_urls", []):
                if not provider_url or provider_url in seen_provider_urls:
                    continue
                seen_provider_urls.add(provider_url)
                provider_name, provider_practice_name = provider_parser(provider_url)
                npi, matched_name, match_status = match_provider(
                    provider_name=provider_name,
                    state=practice_state,
                    full_index=full_index,
                    first_last_index=first_last_index,
                )
                if not npi and not looks_like_physician(provider_name):
                    continue
                physician_rows.append(
                    {
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
                )

    practice_rows.sort(key=lambda row: (row["state"], row["platform"], row["practice_name"]))
    physician_rows.sort(
        key=lambda row: (
            row["state"],
            row["platform"],
            row["practice_name"],
            row["matched_physician_name"] or row["provider_name_scraped"],
        )
    )

    with open(PRACTICE_OUTPUT, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(practice_rows[0].keys()))
        writer.writeheader()
        writer.writerows(practice_rows)

    with open(PHYSICIAN_OUTPUT, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(physician_rows[0].keys()))
        writer.writeheader()
        writer.writerows(physician_rows)

    print(f"Wrote {len(practice_rows)} practice rows to {PRACTICE_OUTPUT}")
    print(f"Wrote {len(physician_rows)} physician rows to {PHYSICIAN_OUTPUT}")


if __name__ == "__main__":
    main()
