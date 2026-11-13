#!/usr/bin/env python3
"""Extract production rules for promtool; run in a directory with rules.yaml."""
from pathlib import Path
import argparse
import yaml

parser = argparse.ArgumentParser()
parser.add_argument('output', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
rules = root / 'kubernetes/apps/tier-1-infrastructure/kube-prometheus-stack/rules'
groups = []
for filename in ('prometheusrule-jobs.yaml', 'prometheusrule-cross-layer-storage.yaml',
                 'prometheusrule-datastores.yaml'):
    groups.extend(yaml.safe_load((rules / filename).read_text())['spec']['groups'])
args.output.mkdir(parents=True, exist_ok=True)
(args.output / 'rules.yaml').write_text(yaml.safe_dump({'groups': groups}))
(args.output / 'prometheus-rules.test.yaml').write_text(
    Path(__file__).with_name('prometheus-rules.test.yaml').read_text())

config = yaml.load((rules.parent / 'app/alertmanagerconfig.yaml').read_text(),
                   Loader=yaml.BaseLoader)
receiver = next(r for r in config['spec']['receivers'] if r['name'] == 'pushover')
(args.output / 'pushover-template.txt').write_text(receiver['pushoverConfigs'][0]['message'])
