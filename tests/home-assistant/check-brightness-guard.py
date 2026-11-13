#!/usr/bin/env python3
"""Evaluate the real condition without calling Home Assistant or any lights."""
from pathlib import Path
from types import SimpleNamespace as State
import jinja2
import yaml

root = Path(__file__).resolve().parents[2]
config = yaml.safe_load((root / 'kubernetes/apps/tier-2-applications/home-assistant/app/configmap-automations.yaml').read_text())
automations = yaml.safe_load(config['data']['automations.yaml'])
automation = next(a for a in automations if a['id'] == 'wall_switches_mirror_room_brightness')
template = jinja2.Environment(undefined=jinja2.StrictUndefined).from_string(automation['condition'][0]['value_template'])

def state(value, brightness=None):
    return State(state=value, attributes={'brightness': brightness})

cases = [
    ('new entity', None, state('on', 127), False),
    ('reconnected', state('unavailable'), state('on', 127), False),
    ('unknown prior state', state('unknown'), state('on', 127), False),
    ('removed entity', state('on', 100), None, False),
    ('off', state('on', 127), state('off'), False),
    ('missing brightness', state('on', 127), state('on'), False),
    ('unchanged', state('on', 127), state('on', 127), False),
    ('real dimmer change', state('on', 127), state('on', 64), True),
    ('real turn on', state('off'), state('on', 127), True),
]
for name, previous, current, expected in cases:
    actual = template.render(trigger=State(from_state=previous, to_state=current)).strip() == 'True'
    assert actual == expected, (name, actual, expected)
print(f'{len(cases)} brightness guard scenarios passed; no device commands sent')
