"""Reconcile a cancelled owned shipping operation; never invent a built receipt."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import sys


def recover(source, workspace, process_group, evidence):
    spec = importlib.util.spec_from_file_location('parc_cancelled_engine', source / 'scripts/engine-source.py')
    engine = importlib.util.module_from_spec(spec); spec.loader.exec_module(engine)
    lock, identity = engine.load_lock()
    with (workspace / '.parc-operation.lock').open('rb') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state = engine.read_marker(workspace, identity)
        receipt = engine.read_shipping_marker(workspace, identity, state)
        if receipt.get('phase') not in ('generation-in-progress', 'build-in-progress'):
            return
        try:
            os.killpg(process_group, 0)
        except ProcessLookupError:
            pass
        else:
            raise ValueError('Cancelled engine process group is still alive; no receipt was changed')
        env = engine.shipping_environment(workspace, lock, state['symbol_level'])
        engine.verify_workspace(workspace, lock, state, env)
        engine.recorded_overlay(workspace, state)
        arguments = engine.shipping_arguments(workspace, env)
        output = workspace / 'chromium/src/out' / engine.SHIPPING_CONFIGURATION
        if ((output / 'args.gn').read_bytes() != arguments
                or receipt['args_sha256'] != engine.digest(arguments)
                or receipt['source_fingerprint'] != state['source_fingerprint']
                or receipt['overlay'] != state.get('overlay')):
            raise ValueError('Cancelled build inputs changed; receipt and objects preserved')
        # The previous bytes remain evidence. Only convert the verified cancelled
        # operation to a resumable failure; GN/Ninja still must actually succeed.
        evidence.parent.mkdir(parents=True, exist_ok=True)
        if not evidence.exists():
            evidence.write_bytes((workspace / engine.SHIPPING_MARKER).read_bytes())
        receipt.update(phase=receipt['phase'].replace('-in-progress', '-failed'),
                       error='Owner cancelled process group ' + str(process_group) + '; unchanged inputs verified for incremental resume')
        engine.write_marker(workspace, receipt, engine.SHIPPING_MARKER)
        print('Verified cancelled engine operation; preserved objects/cache and enabled incremental resume', flush=True)


if __name__ == '__main__':
    recover(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), Path(sys.argv[4]))
