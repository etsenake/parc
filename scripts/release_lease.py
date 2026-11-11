import json
import subprocess

REPO = 'etsenake/parc'
REF = 'tags/parc-release-in-progress'


def api(path, payload=None, method=None):
    args = ['gh', 'api', 'repos/' + REPO + '/' + path]
    if method:
        args += ['--method', method]
    result = subprocess.run(args + (['--input', '-'] if payload is not None else []),
                            input=json.dumps(payload) if payload is not None else None,
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout) if result.stdout.strip() else None


def acquire(owner, commit, saved=None):
    try:
        existing = api('git/ref/' + REF)
    except RuntimeError as error:
        if '404' not in str(error):
            raise
        existing = None
    if existing:
        tag = api('git/tags/' + existing['object']['sha'])
        if json.loads(tag['message']).get('owner') != owner:
            raise ValueError('Another Mac/release owns parc-release-in-progress; no concurrent release started. '
                             'Resume that run on its original Mac; never steal a live lease.')
        return existing['object']['sha']
    if saved:
        raise ValueError('The saved release lease disappeared; refusing to recreate or steal it')
    tag = api('git/tags', {'tag': 'parc-release-in-progress', 'message': json.dumps({'owner': owner}),
                          'object': commit, 'type': 'commit'})
    api('git/refs', {'ref': 'refs/' + REF, 'sha': tag['sha']})
    return tag['sha']


def release(identity):
    try:
        existing = api('git/ref/' + REF)
    except RuntimeError as error:
        if '404' in str(error):
            return
        raise
    if existing['object']['sha'] != identity:
        raise ValueError('Release lease changed owners; it was preserved')
    api('git/refs/' + REF, method='DELETE')
