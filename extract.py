#!/usr/bin/env python3
"""Extract PitchBook data from Chrome via CDP WebSocket."""
import json
import time
import sys
import os

try:
    import websocket
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "websocket-client"])
    import websocket

# Approach: Connect to browser-level WebSocket, then find PitchBook tab
# We need to bypass the origin check that Chrome enforces

print("=== PitchBook Data Extractor ===")

def try_connect(ws_url, **kwargs):
    """Try connecting with various origin strategies."""
    strategies = [
        {"header": {"Origin": ""}},
        {"header": {}},
        {"header": {"Origin": "chrome-devtools://devtools"}},
        {},
    ]
    for i, extra in enumerate(strategies):
        try:
            print(f"  Strategy {i+1}: connecting to {ws_url}...")
            ws = websocket.create_connection(ws_url, timeout=5, **extra)
            print(f"  Connected!")
            return ws
        except Exception as e:
            print(f"  Strategy {i+1} failed: {e}")
    return None

# Try HTTP endpoint first (standard CDP)
import urllib.request
http_endpoints = [
    "http://127.0.0.1:9222/json",
    "http://127.0.0.1:9222/json/list",
]

pages = None
for ep in http_endpoints:
    try:
        response = urllib.request.urlopen(ep, timeout=3)
        data = response.read().decode()
        if data.strip():
            pages = json.loads(data)
            print(f"Got page list from {ep}: {len(pages)} pages")
            break
    except Exception as e:
        print(f"{ep}: {e}")

if pages:
    # Standard path: find PitchBook tab and connect to its WebSocket
    pb_page = None
    for p in pages:
        url = p.get("url", "")
        print(f"  Tab: {url[:80]}")
        if "my.pitchbook.com" in url:
            pb_page = p
    
    if pb_page:
        ws_url = pb_page["webSocketDebuggerUrl"]
        print(f"Connecting to PitchBook tab: {ws_url}")
        ws = try_connect(ws_url)
    else:
        print("PitchBook tab not found!")
        sys.exit(1)
else:
    # Alternative: connect to browser-level WebSocket
    print("\nHTTP endpoints unavailable. Trying browser WebSocket directly...")
    browser_ws_urls = [
        "ws://127.0.0.1:9222/devtools/browser",
        "ws://localhost:9222/devtools/browser",
        "ws://127.0.0.1:9222",
    ]
    
    ws = None
    for url in browser_ws_urls:
        ws = try_connect(url)
        if ws:
            break
    
    if not ws:
        print("\nERROR: Cannot connect to Chrome DevTools.")
        print("Chrome may need --remote-allow-origins=* flag.")
        print("Try restarting Chrome with:")
        print('  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=9222 --remote-allow-origins=*')
        sys.exit(1)
    
    # Use browser-level WS to find targets
    print("Finding PitchBook target...")
    msg_id = 1
    msg = {"id": msg_id, "method": "Target.getTargets", "params": {}}
    ws.send(json.dumps(msg))
    
    res = json.loads(ws.recv())
    targets = res.get("result", {}).get("targetInfos", [])
    
    pb_target = None
    for t in targets:
        if t.get("type") == "page" and "my.pitchbook.com" in t.get("url", ""):
            pb_target = t
            print(f"Found PitchBook tab: {t['url'][:80]}")
            break
    
    if not pb_target:
        print("PitchBook tab not found among targets!")
        for t in targets:
            if t.get("type") == "page":
                print(f"  Page: {t.get('url', '')[:80]}")
        sys.exit(1)
    
    # Attach to target
    msg_id += 1
    attach_msg = {
        "id": msg_id,
        "method": "Target.attachToTarget",
        "params": {"targetId": pb_target["targetId"], "flatten": True}
    }
    ws.send(json.dumps(attach_msg))
    attach_res = json.loads(ws.recv())
    session_id = attach_res.get("result", {}).get("sessionId")
    print(f"Attached to target, session: {session_id}")

# Now we have a WS connection to Chrome
msg_id = 100

def evaluate_js(expression, session_id=None):
    global msg_id
    msg_id += 1
    msg = {
        "id": msg_id,
        "method": "Runtime.evaluate",
        "params": {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": True
        }
    }
    if session_id:
        msg["sessionId"] = session_id
    
    ws.send(json.dumps(msg))
    
    deadline = time.time() + 30
    while time.time() < deadline:
        raw = ws.recv()
        res = json.loads(raw)
        if "id" in res and res["id"] == msg_id:
            if "exceptionDetails" in res.get("result", {}):
                print(f"JS Error: {json.dumps(res['result']['exceptionDetails'])[:200]}")
                return None
            if "result" in res and "result" in res["result"]:
                return res["result"]["result"].get("value")
            return None
    print("Timeout waiting for JS result")
    return None

def navigate_to(url, session_id=None):
    global msg_id
    msg_id += 1
    msg = {
        "id": msg_id,
        "method": "Page.navigate",
        "params": {"url": url}
    }
    if session_id:
        msg["sessionId"] = session_id
    ws.send(json.dumps(msg))
    
    deadline = time.time() + 10
    while time.time() < deadline:
        res = json.loads(ws.recv())
        if "id" in res and res["id"] == msg_id:
            break
    time.sleep(5)

sid = locals().get('session_id')

# Check if CSV data is already in memory
print("\nChecking for pre-scraped CSV data in window...")
csv_check = evaluate_js("typeof window.companiesCsv !== 'undefined' ? 'EXISTS:' + window.companiesCsv.length : 'NOT_FOUND'", sid)
print(f"Companies CSV: {csv_check}")

deals_check = evaluate_js("typeof window.dealsCsv !== 'undefined' ? 'EXISTS:' + window.dealsCsv.length : 'NOT_FOUND'", sid)
print(f"Deals CSV: {deals_check}")

def escape_csv(val):
    if val is None: return ''
    s = str(val).strip().replace('\r\n', ' ').replace('\n', ' ').replace('\r', ' ')
    if ',' in s or '"' in s:
        return '"' + s.replace('"', '""') + '"'
    return s

if csv_check and csv_check.startswith("EXISTS:"):
    # Extract pre-scraped CSV data in chunks
    csv_len = int(csv_check.split(":")[1])
    print(f"\nExtracting Companies CSV ({csv_len} chars)...")
    chunk_size = 100000
    csv_data = ""
    for start in range(0, csv_len, chunk_size):
        chunk = evaluate_js(f"window.companiesCsv.substring({start}, {start + chunk_size})", sid)
        if chunk:
            csv_data += chunk
            print(f"  Chunk {start//chunk_size + 1}: {len(chunk)} chars (total: {len(csv_data)})")
    
    os.makedirs("/Users/tylermuffly/private_equity", exist_ok=True)
    with open("/Users/tylermuffly/private_equity/companies_export.csv", "w", encoding="utf-8") as f:
        f.write(csv_data)
    print(f"Saved companies_export.csv ({len(csv_data)} chars)")

if deals_check and deals_check.startswith("EXISTS:"):
    csv_len = int(deals_check.split(":")[1])
    print(f"\nExtracting Deals CSV ({csv_len} chars)...")
    chunk_size = 100000
    csv_data = ""
    for start in range(0, csv_len, chunk_size):
        chunk = evaluate_js(f"window.dealsCsv.substring({start}, {start + chunk_size})", sid)
        if chunk:
            csv_data += chunk
            print(f"  Chunk {start//chunk_size + 1}: {len(chunk)} chars (total: {len(csv_data)})")
    
    with open("/Users/tylermuffly/private_equity/deals_export.csv", "w", encoding="utf-8") as f:
        f.write(csv_data)
    print(f"Saved deals_export.csv ({len(csv_data)} chars)")

# If CSV data wasn't in memory, scrape page by page
if (not csv_check or csv_check == "NOT_FOUND") and (not deals_check or deals_check == "NOT_FOUND"):
    print("\nNo pre-scraped data found. Scraping tables page-by-page...")
    
    def scrape_tab(tab_url, csv_path, headers):
        print(f"\nNavigating to {tab_url}...")
        navigate_to(tab_url, sid)
        time.sleep(3)
        
        all_data = []
        page = 1
        
        while True:
            print(f"Scraping page {page}...")
            page_rows = evaluate_js("""
                (() => {
                    const rows = document.querySelectorAll('tr[class*="data-table"], .data-table__row');
                    const pageData = [];
                    rows.forEach((row, i) => {
                        if (i === 0) return; // skip header
                        const cells = row.querySelectorAll('td, .data-table__cell');
                        const rowData = Array.from(cells).map(c => (c.innerText || '').trim());
                        if (rowData.length > 0 && rowData.some(v => v !== '')) {
                            pageData.push(rowData);
                        }
                    });
                    return pageData;
                })()
            """, sid)
            
            if not page_rows or len(page_rows) == 0:
                print("No rows found. Done.")
                break
            
            all_data.extend(page_rows)
            print(f"  Got {len(page_rows)} rows (total: {len(all_data)})")
            
            # Check for Next button
            has_next = evaluate_js("""
                (() => {
                    const btns = document.querySelectorAll('button');
                    for (const b of btns) {
                        if (b.innerText.trim() === 'Next' && !b.disabled) return true;
                    }
                    return false;
                })()
            """, sid)
            
            if not has_next:
                print("No more pages.")
                break
            
            evaluate_js("""
                (() => {
                    const btns = document.querySelectorAll('button');
                    for (const b of btns) {
                        if (b.innerText.trim() === 'Next' && !b.disabled) { b.click(); break; }
                    }
                })()
            """, sid)
            time.sleep(3)
            page += 1
        
        print(f"Writing {len(all_data)} rows to {csv_path}...")
        os.makedirs(os.path.dirname(csv_path), exist_ok=True)
        with open(csv_path, 'w', encoding='utf-8') as f:
            f.write(','.join(headers) + '\n')
            for row in all_data:
                f.write(','.join(escape_csv(c) for c in row) + '\n')
        print(f"Saved {csv_path}")
    
    scrape_tab(
        "https://my.pitchbook.com/search-results/s655975417/companies",
        "/Users/tylermuffly/private_equity/companies_export.csv",
        ["Rank", "Company", "Details"]
    )
    
    scrape_tab(
        "https://my.pitchbook.com/search-results/s655975417/deals",
        "/Users/tylermuffly/private_equity/deals_export.csv",
        ["Rank", "Company", "Details"]
    )

ws.close()
print("\n=== Done! ===")
