"""Download the Sketchfab models listed in scripts/assets/sketchfab.json into .local/sketchfab/raw.

Runs under any Python 3 (Blender's bundled one included):
    python scripts/assets/fetch_sketchfab.py [model_id ...]

Needs a Sketchfab API token, read from the SKETCHFAB_API_TOKEN environment variable or from
.local/sketchfab-key.txt (git-ignored). The token is only sent to api.sketchfab.com and is never
printed or written anywhere else. For every model the licence, author and page URL are taken from
the API, so the credits always match what Sketchfab says, and a model whose licence is not in
ALLOWED_LICENCES is refused.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'scripts/assets/sketchfab.json'
RAW = ROOT / '.local/sketchfab/raw'
API = 'https://api.sketchfab.com/v3'
# Licences the library accepts. Non-commercial ones are kept apart by the library build so they
# can be dropped if Construct is ever sold or open-sourced (see world/assets/library/README.md).
ALLOWED_LICENCES = {'cc0', 'by', 'by-sa', 'by-nc', 'by-nc-sa'}


def token() -> str:
    value = os.environ.get('SKETCHFAB_API_TOKEN', '').strip()
    if not value:
        for name in ('sketchfab-key.txt', 'sketchfab_token.txt'):
            path = ROOT / '.local' / name
            if path.exists():
                value = path.read_text(encoding='utf-8-sig').strip()
                break
    if not value:
        sys.exit('No Sketchfab API token: set SKETCHFAB_API_TOKEN or put it in .local/sketchfab-key.txt')
    return value


def get_json(url: str, auth: str = '') -> dict:
    """GET JSON, waiting and retrying when Sketchfab rate-limits (HTTP 429)."""
    headers = {'Authorization': 'Token ' + auth} if auth else {}
    for attempt in range(6):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == 5:
                raise
            wait = int(error.headers.get('Retry-After') or 0) or 20 * (attempt + 1)
            print(f'CONSTRUCT_SKETCHFAB_WAIT {wait}s (rate limited)', flush=True)
            time.sleep(wait)


def fetch(model: dict, auth: str):
    uid = model['uid']
    dest = RAW / uid
    dest.mkdir(parents=True, exist_ok=True)
    info = get_json(f'{API}/models/{uid}')
    licence = info.get('license') or {}
    user = info.get('user') or {}
    meta = {
        'uid': uid,
        'title': info.get('name'),
        'page': info.get('viewerUrl'),
        'author': user.get('displayName') or user.get('username'),
        'author_page': user.get('profileUrl'),
        'licence': licence.get('slug'),
        'licence_label': licence.get('label'),
        'licence_url': licence.get('url'),
        'fetched': time.strftime('%Y-%m-%d'),
    }
    if meta['licence'] not in ALLOWED_LICENCES:
        print(f'CONSTRUCT_SKETCHFAB_REFUSED {model["id"]}: licence {meta["licence"]}', flush=True)
        return
    (dest / 'meta.json').write_text(json.dumps(meta, indent=1, ensure_ascii=False), encoding='utf-8')
    target = dest / 'model.glb'
    if not target.exists():
        links = get_json(f'{API}/models/{uid}/download', auth)
        if 'glb' not in links:
            print(f'CONSTRUCT_SKETCHFAB_SKIPPED {model["id"]}: no GLB download offered', flush=True)
            return
        urllib.request.urlretrieve(links['glb']['url'], target)
    print(f'CONSTRUCT_SKETCHFAB {model["id"]}: {meta["licence"]} by {meta["author"]}, '
          f'{target.stat().st_size / 1e6:.1f} MB', flush=True)


def main():
    # Model ids to fetch (all when none). Works both standalone and under `blender --python ... --`.
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    wanted = set(args)
    models = json.loads(MANIFEST.read_text(encoding='utf-8'))['models']
    auth = token()
    for model in models:
        if not wanted or model['id'] in wanted:
            try:
                fetch(model, auth)
                time.sleep(2.0)  # be gentle with the API
            except Exception as error:  # keep going; report at the end
                print(f'CONSTRUCT_SKETCHFAB_FAILED {model["id"]}: {error}', flush=True)
    print('CONSTRUCT_SKETCHFAB_DONE', flush=True)


if __name__ == '__main__':
    main()
