import requests
import time
import os

urls = {
    "1_uwh_michigan": "https://uwhmichigan.com/providers",
    "2_together_comprehensive": "https://comprehensivewomanscare.com/",
    "2_together_eastside": "https://togetherwomenshealth.com/practice/eastside-gynecology-obstetrics/",
    "3_nova_womancare": "https://womancarepc.com/find-care/providers",
    "3_nova_healthfirst": "https://www.womenfirst.net/our-providers/",
    "4_topline_md": "https://www.toplinemd.com/find-a-provider/",
    "5_ccrm_fertility": "https://www.ccrmivf.com/fertility-doctors",
    "6_ivi_rma": "https://www.rmanetwork.com/resources/our-fertility-specialists/",
    "7_shady_grove": "https://www.shadygrovefertility.com/our-team/doctors/",
    "8_kindbody": "https://kindbody.com/our-doctors/",
    "9_womens_care": "https://www.womenscareobgyn.com/providers/",
    "10_axia": "https://axiawh.com/providers/"
}

headers = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9"
}

output_dir = "scraped_texts"
os.makedirs(output_dir, exist_ok=True)

for name, url in urls.items():
    print(f"Fetching {name} from {url}...")
    try:
        r = requests.get(url, headers=headers, timeout=20)
        if r.status_code == 200:
            file_path = os.path.join(output_dir, f"{name}.html")
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(r.text)
            print(f"  Success: saved {len(r.text)} bytes to {file_path}")
        else:
            print(f"  Failed: Status Code {r.status_code}")
    except Exception as e:
        print(f"  Error: {e}")
    time.sleep(1.5)

print("\nHTML fetching complete.")
