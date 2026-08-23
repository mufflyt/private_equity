#!/usr/bin/env python3
"""Extract PitchBook search results via AppleScript + Chrome JavaScript."""
import subprocess
import csv
import os
import time
import json
import sys

TAB_NUM = 2  # PitchBook tab number in Chrome
OUTPUT_DIR = "."

def run_js(tab, js_code):
    """Execute JavaScript in Chrome tab via AppleScript and return result."""
    # Escape for AppleScript
    js_escaped = js_code.replace('\\', '\\\\').replace('"', '\\"')
    applescript = f'''tell application "Google Chrome"
  set jsResult to execute tab {tab} of front window javascript "{js_escaped}"
  return jsResult
end tell'''
    try:
        result = subprocess.run(
            ['osascript', '-e', applescript],
            capture_output=True, text=True, timeout=60
        )
        if result.returncode != 0:
            print(f"  AppleScript error: {result.stderr.strip()[:200]}")
            return None
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        print("  Timeout!")
        return None

def get_page_info(tab):
    """Get current page title and result count."""
    return run_js(tab, "document.title")

def get_total_count(tab):
    """Get total entity count from the page."""
    result = run_js(tab, """
        (function() {
            var el = document.querySelector('.search-results-count, .as-results-header__count');
            if (el) return el.innerText.trim();
            var spans = document.querySelectorAll('span');
            for (var i = 0; i < spans.length; i++) {
                var t = spans[i].innerText.trim();
                if (t.match(/^[\\d,]+$/) && parseInt(t.replace(/,/g,'')) > 100) return t;
            }
            return 'unknown';
        })()
    """)
    return result

def scrape_current_page(tab):
    """Scrape all rows from the current page of results."""
    # First get header columns
    headers_json = run_js(tab, """
        (function() {
            var cells = document.querySelectorAll('.data-table__cell_header-cell');
            var h = [];
            for (var i = 0; i < cells.length; i++) h.push(cells[i].innerText.trim());
            return JSON.stringify(h);
        })()
    """)
    
    # Get row data - scrape in batches to avoid output truncation
    all_rows = []
    batch_size = 25
    total_rows_js = run_js(tab, "document.querySelectorAll('.data-table__row_fixed').length - 1")
    try:
        total_rows = int(total_rows_js) if total_rows_js else 0
    except ValueError:
        total_rows = 250
    
    for start in range(0, total_rows, batch_size):
        end = min(start + batch_size, total_rows)
        rows_json = run_js(tab, f"""
            (function() {{
                var nameTable = document.querySelectorAll('.data-table__table')[1];
                var dataTable = document.querySelectorAll('.data-table__table')[3];
                var nameRows = nameTable ? nameTable.querySelectorAll('.data-table__row') : [];
                var dataRows = dataTable ? dataTable.querySelectorAll('.data-table__row') : [];
                var batch = [];
                for (var i = {start + 1}; i <= {end} && i < nameRows.length; i++) {{
                    var row = [];
                    var fCells = nameRows[i] ? nameRows[i].querySelectorAll('.data-table__cell') : [];
                    for (var j = 0; j < fCells.length; j++) {{
                        row.push(fCells[j].innerText.trim().replace(/\\n/g, ' | '));
                    }}
                    if (dataRows[i]) {{
                        var sCells = dataRows[i].querySelectorAll('.data-table__cell');
                        for (var j = 0; j < sCells.length; j++) {{
                            row.push(sCells[j].innerText.trim().replace(/\\n/g, ' | '));
                        }}
                    }}
                    batch.push(row);
                }}
                return JSON.stringify(batch);
            }})()
        """)
        
        if rows_json:
            try:
                batch_rows = json.loads(rows_json)
                all_rows.extend(batch_rows)
            except json.JSONDecodeError:
                print(f"  JSON parse error for batch {start}-{end}")
    
    headers = []
    if headers_json:
        try:
            headers = json.loads(headers_json)
        except json.JSONDecodeError:
            pass
    
    return headers, all_rows

def click_next_page(tab):
    """Click Next button and wait for page load. Returns False if no next page."""
    # Get current first row to detect page change
    current_first = run_js(tab, """
        (function() {
            var rows = document.querySelectorAll('.data-table__row_fixed');
            if (rows.length > 1) {
                var cell = rows[1].querySelector('.data-table__cell');
                return cell ? cell.innerText.trim().substring(0, 50) : '';
            }
            return '';
        })()
    """)
    
    # Check if Next button exists and is enabled
    has_next = run_js(tab, """
        (function() {
            var btns = document.querySelectorAll('button');
            for (var i = 0; i < btns.length; i++) {
                if (btns[i].innerText.trim() === 'Next') {
                    return !btns[i].disabled && !btns[i].classList.contains('button_disabled') ? 'yes' : 'no';
                }
            }
            return 'no';
        })()
    """)
    
    if has_next != 'yes':
        return False
    
    # Click Next
    run_js(tab, """
        (function() {
            var btns = document.querySelectorAll('button');
            for (var i = 0; i < btns.length; i++) {
                if (btns[i].innerText.trim() === 'Next' && !btns[i].disabled) {
                    btns[i].click();
                    break;
                }
            }
        })()
    """)
    
    # Wait for page to change
    for attempt in range(40):
        time.sleep(0.75)
        new_first = run_js(tab, """
            (function() {
                var rows = document.querySelectorAll('.data-table__row_fixed');
                if (rows.length > 1) {
                    var cell = rows[1].querySelector('.data-table__cell');
                    return cell ? cell.innerText.trim().substring(0, 50) : '';
                }
                return '';
            })()
        """)
        if new_first and new_first != current_first:
            time.sleep(1)  # Extra settle time
            return True
    
    print("  Timeout waiting for next page")
    return False

def navigate_to_tab_url(tab, url):
    """Navigate the tab to a URL."""
    js = f"window.location.href = '{url}'"
    run_js(tab, js)
    time.sleep(5)

def wait_for_table_load(tab, timeout=35):
    """Wait for the table to load by checking for rows."""
    print("  Waiting for table to load...", end="", flush=True)
    for i in range(timeout):
        res = run_js(tab, "document.querySelectorAll('.data-table__row_fixed').length")
        try:
            if res and int(res) > 1:
                print(" Loaded!")
                return True
        except (ValueError, TypeError):
            pass
        time.sleep(1)
        print(".", end="", flush=True)
    print(" Timeout waiting for table!")
    return False

def scrape_full_table(tab, tab_url, csv_path, table_name):
    """Scrape all pages of a table and save to CSV."""
    print(f"\n{'='*60}")
    print(f"Scraping {table_name}")
    print(f"{'='*60}")
    
    # Navigate to the tab
    current_url = run_js(tab, "window.location.href")
    if current_url != tab_url:
        print(f"Navigating to {tab_url}...")
        navigate_to_tab_url(tab, tab_url)
    else:
        print(f"Already on {tab_url}")
    
    if not wait_for_table_load(tab):
        print("Retrying navigation...")
        navigate_to_tab_url(tab, tab_url)
        if not wait_for_table_load(tab):
            print("Failed to load table. Exiting.")
            return 0
    
    title = get_page_info(tab)
    print(f"Page title: {title}")
    
    total = get_total_count(tab)
    print(f"Total entities: {total}")
    
    all_rows = []
    headers = None
    page = 1
    
    while True:
        print(f"\n--- Page {page} ---")
        h, rows = scrape_current_page(tab)
        
        if headers is None and h:
            headers = h
            print(f"Headers: {headers}")
        
        if not rows:
            print("No rows found. Done.")
            break
        
        all_rows.extend(rows)
        print(f"Scraped {len(rows)} rows (Total: {len(all_rows)})")
        
        if not click_next_page(tab):
            print("No more pages.")
            break
        
        page += 1
    
    # Write CSV
    print(f"\nWriting {len(all_rows)} rows to {csv_path}...")
    os.makedirs(os.path.dirname(csv_path), exist_ok=True)
    
    with open(csv_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        if headers:
            writer.writerow(headers)
        for row in all_rows:
            writer.writerow(row)
    
    print(f"✓ Saved {csv_path} ({len(all_rows)} rows)")
    return len(all_rows)

# ============================================================
# MAIN
# ============================================================
if __name__ == "__main__":
    print("=== PitchBook Data Extractor (AppleScript) ===\n")
    
    # Verify we can talk to Chrome
    test = run_js(TAB_NUM, "document.title")
    if not test:
        print("ERROR: Cannot execute JavaScript in Chrome.")
        print("Make sure 'Allow JavaScript from Apple Events' is enabled.")
        sys.exit(1)
    print(f"Connected to Chrome tab {TAB_NUM}: {test}")
    
    # Scrape Companies
    companies_count = scrape_full_table(
        TAB_NUM,
        "https://my.pitchbook.com/search-results/s655975417/companies",
        os.path.join(OUTPUT_DIR, "companies_export.csv"),
        "COMPANIES"
    )
    
    # Scrape Deals
    deals_count = scrape_full_table(
        TAB_NUM,
        "https://my.pitchbook.com/search-results/s655975417/deals",
        os.path.join(OUTPUT_DIR, "deals_export.csv"),
        "DEALS"
    )
    
    print(f"\n{'='*60}")
    print(f"COMPLETE!")
    print(f"  Companies: {companies_count} rows")
    print(f"  Deals: {deals_count} rows")
    print(f"  Output: {OUTPUT_DIR}/")
    print(f"{'='*60}")
