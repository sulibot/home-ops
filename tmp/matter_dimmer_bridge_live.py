"""Bridge Matter dimmer attribute updates directly to target bulbs."""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass

import voluptuous as vol
from chip.clusters import Objects as clusters

from homeassistant.components.matter.const import DOMAIN as MATTER_DOMAIN
from homeassistant.components.matter.helpers import get_matter
from homeassistant.const import CONF_ENTITY_ID, CONF_NAME, EVENT_HOMEASSISTANT_STARTED
from homeassistant.core import Event, HomeAssistant, callback
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers.event import async_track_state_change_event
from matter_server.common.helpers.util import create_attribute_path
from matter_server.common.models import EventType

DOMAIN = "matter_dimmer_bridge"
CONF_NODE_ID = "node_id"
CONF_SWITCH_ENTITY_ID = "switch_entity_id"
CONF_TARGET_ENTITY_IDS = "target_entity_ids"
CONF_TARGET_SELECTOR = "target_selector"
CONF_TARGETS = "targets"
CONF_LABEL = "label"
CONF_DOUBLE_TAP_WINDOW_SECONDS = "double_tap_window_seconds"
CONF_ENTITY_IDS = "entity_ids"
RETRY_DELAY_SECONDS = 5
DOUBLE_TAP_WINDOW_SECONDS = 0.45
TURN_ON_LEVEL_SUPPRESSION_SECONDS = 1.2
TARGET_SWITCH_LEVEL_SUPPRESSION_SECONDS = 0.9
BRIGHTNESS_DELTA_THRESHOLD = 8
LEVEL_DEDUPE_WINDOW_SECONDS = 0.25
ONOFF_DEBOUNCE_SECONDS = 0.15
DEFAULT_TRANSITION_SECONDS = 0.0
HOLD_CYCLE_WINDOW_SECONDS = 2.0
HOLD_CYCLE_MIN_UPDATES = 3
HOLD_CYCLE_HIGH_EDGE = 235
HOLD_CYCLE_LOW_EDGE = 20
FOCUS_IDLE_RESET_SECONDS = 30.0
SWITCH_SYNC_SUPPRESSION_SECONDS = 1.0

LOGGER = logging.getLogger(__name__)

TARGET_SCHEMA = vol.Schema(
    {
        vol.Required(CONF_LABEL): cv.string,
        vol.Exclusive(CONF_ENTITY_ID, "target_entity"): cv.entity_id,
        vol.Exclusive(CONF_ENTITY_IDS, "target_entity"): vol.All(
            cv.ensure_list, [cv.entity_id]
        ),
    }
)

BRIDGE_SCHEMA = vol.Schema(
    {
        vol.Required(CONF_NAME): cv.string,
        vol.Required(CONF_NODE_ID): vol.Coerce(int),
        vol.Required(CONF_SWITCH_ENTITY_ID): cv.entity_id,
        vol.Optional(CONF_TARGET_ENTITY_IDS): vol.All(
            cv.ensure_list, [cv.entity_id]
        ),
        vol.Optional(CONF_TARGET_SELECTOR): cv.entity_id,
        vol.Optional(CONF_TARGETS): vol.All(
            cv.ensure_list, [TARGET_SCHEMA]
        ),
        vol.Optional(CONF_DOUBLE_TAP_WINDOW_SECONDS): vol.Coerce(float),
    }
)

CONFIG_SCHEMA = vol.Schema(
    {DOMAIN: vol.All(cv.ensure_list, [BRIDGE_SCHEMA])},
    extra=vol.ALLOW_EXTRA,
)


@dataclass
class TargetSpec:
    """Config for one selectable target."""

    label: str
    entity_ids: list[str]


@dataclass
class BridgeState:
    """In-memory state for one mirrored dimmer."""

    name: str
    node_id: int
    switch_entity_id: str
    target_entity_ids: list[str]
    target_selector: str | None = None
    targets: list[TargetSpec] | None = None
    is_on: bool | None = None
    brightness: int = 255
    suppress_level_until: float = 0.0
    pending_single_tap: asyncio.Task | None = None
    last_onoff_timestamp: float = 0.0
    last_onoff_value: bool | None = None
    last_tap_timestamp: float = 0.0
    last_single_tap_completed_at: float = 0.0
    last_level_value: int | None = None
    last_level_timestamp: float = 0.0
    double_tap_window_seconds: float = DOUBLE_TAP_WINDOW_SECONDS
    hold_direction: int | None = None
    hold_start_level: int | None = None
    hold_started_at: float = 0.0
    hold_update_count: int = 0
    target_last_on: dict[str, bool] | None = None
    pending_focus_reset: asyncio.Task | None = None
    ignore_onoff_until: float = 0.0


def _matter_to_ha_brightness(level: int | None) -> int:
    """Convert Matter currentLevel to HA brightness scale."""
    if level is None:
        return 255
    value = max(1, min(254, int(level)))
    return round((value - 1) * 255 / 253)


def _target_cycling_enabled(state: BridgeState) -> bool:
    """Return whether target cycling is configured for this dimmer."""
    return bool(state.target_selector and state.targets)


def _resolve_selected_target(
    state: BridgeState, hass: HomeAssistant
) -> list[str]:
    """Return the currently selected target entities."""
    if not _target_cycling_enabled(state):
        return state.target_entity_ids

    selector_state = hass.states.get(state.target_selector)
    if selector_state is None:
        return state.targets[-1].entity_ids

    for target in state.targets:
        if target.label == selector_state.state:
            return target.entity_ids
    return state.targets[-1].entity_ids


def _resolve_selected_label(
    state: BridgeState, hass: HomeAssistant
) -> str | None:
    """Return the currently selected target label."""
    if not _target_cycling_enabled(state):
        return None

    selector_state = hass.states.get(state.target_selector)
    if selector_state is None:
        return state.targets[-1].label

    labels = [target.label for target in state.targets]
    if selector_state.state in labels:
        return selector_state.state
    return state.targets[-1].label


def _resolve_default_target(
    state: BridgeState,
) -> tuple[str | None, list[str]]:
    """Return the default room/group target."""
    if not _target_cycling_enabled(state):
        return None, state.target_entity_ids
    default = state.targets[-1]
    return default.label, default.entity_ids


def _uniform_target_state(
    hass: HomeAssistant, entity_ids: list[str]
) -> bool | None:
    """Return True/False if all target entities share one state."""
    states = [hass.states.get(entity_id) for entity_id in entity_ids]
    available = [
        entity_state.state
        for entity_state in states
        if entity_state is not None
        and entity_state.state not in ("unknown", "unavailable")
    ]
    if len(available) != len(entity_ids) or not available:
        return None
    if all(value == "on" for value in available):
        return True
    if all(value == "off" for value in available):
        return False
    return None


async def _async_drive_switch_indicator(
    hass: HomeAssistant, state: BridgeState, *, turn_on: bool
) -> None:
    """Best-effort attempt to drive the switch indicator state."""
    state.ignore_onoff_until = (
        time.monotonic() + SWITCH_SYNC_SUPPRESSION_SECONDS
    )
    service = "turn_on" if turn_on else "turn_off"
    LOGGER.info(
        "%s switch indicator sync -> %s via %s",
        state.name,
        turn_on,
        state.switch_entity_id,
    )
    await hass.services.async_call(
        "light",
        service,
        {
            "entity_id": state.switch_entity_id,
            "transition": DEFAULT_TRANSITION_SECONDS,
        },
        blocking=True,
    )


def _schedule_focus_reset(hass: HomeAssistant, state: BridgeState) -> None:
    """Reset focus to the room default after idle time."""
    if not _target_cycling_enabled(state):
        return

    pending = state.pending_focus_reset
    if pending is not None and not pending.done():
        pending.cancel()

    async def _reset_focus_later() -> None:
        try:
            await asyncio.sleep(FOCUS_IDLE_RESET_SECONDS)
            current_label = _resolve_selected_label(state, hass)
            default_label, default_entities = _resolve_default_target(state)
            if current_label != default_label and default_label is not None:
                await hass.services.async_call(
                    "input_select",
                    "select_option",
                    {
                        "entity_id": state.target_selector,
                        "option": default_label,
                    },
                    blocking=True,
                )
                LOGGER.info(
                    "%s selected target after idle reset: %s",
                    state.name,
                    default_label,
                )
            uniform_state = _uniform_target_state(hass, default_entities)
            if uniform_state is not None:
                await _async_drive_switch_indicator(
                    hass, state, turn_on=uniform_state
                )
        except asyncio.CancelledError:
            raise
        finally:
            state.pending_focus_reset = None

    state.pending_focus_reset = hass.async_create_task(_reset_focus_later())


async def _async_cycle_target(hass: HomeAssistant, state: BridgeState) -> None:
    """Advance to the next target in the selector."""
    if not _target_cycling_enabled(state):
        return

    labels = [target.label for target in state.targets]
    current_label = _resolve_selected_label(state, hass) or labels[-1]
    LOGGER.info(
        "%s selected target before press: %s",
        state.name,
        current_label,
    )
    try:
        current_index = labels.index(current_label)
    except ValueError:
        current_index = len(labels) - 1
    next_label = labels[(current_index + 1) % len(labels)]
    await hass.services.async_call(
        "input_select",
        "select_option",
        {"entity_id": state.target_selector, "option": next_label},
        blocking=True,
    )
    next_entities: list[str] = []
    for target in state.targets:
        if target.label == next_label:
            next_entities = target.entity_ids
            break
    state.suppress_level_until = (
        time.monotonic() + TARGET_SWITCH_LEVEL_SUPPRESSION_SECONDS
    )
    LOGGER.info(
        "%s selected target after focus advance: %s",
        state.name,
        next_label,
    )
    LOGGER.info(
        "%s entity IDs flashed: %s",
        state.name,
        next_entities,
    )
    if next_entities:
        hass.async_create_task(
            _async_flash_target_entities(hass, next_entities)
        )
    _schedule_focus_reset(hass, state)


def _reset_hold_tracking(state: BridgeState) -> None:
    """Reset brightness-hold gesture tracking."""
    state.hold_direction = None
    state.hold_start_level = None
    state.hold_started_at = 0.0
    state.hold_update_count = 0


async def _async_flash_target_entities(
    hass: HomeAssistant, entity_ids: list[str]
) -> None:
    """Best-effort visual focus indicator for the selected target."""
    states = {
        entity_id: hass.states.get(entity_id)
        for entity_id in entity_ids
    }
    available = {
        entity_id: entity_state
        for entity_id, entity_state in states.items()
        if entity_state is not None
        and entity_state.state not in ("unknown", "unavailable")
    }
    if not available:
        return

    was_on = {
        entity_id
        for entity_id, entity_state in available.items()
        if entity_state.state == "on"
    }

    if was_on:
        await hass.services.async_call(
            "light",
            "turn_off",
            {
                "entity_id": list(was_on),
                "transition": DEFAULT_TRANSITION_SECONDS,
            },
            blocking=True,
        )
        await asyncio.sleep(0.18)
        await hass.services.async_call(
            "light",
            "turn_on",
            {
                "entity_id": list(was_on),
                "transition": DEFAULT_TRANSITION_SECONDS,
            },
            blocking=True,
        )
        return

    await hass.services.async_call(
        "light",
        "turn_on",
        {
            "entity_id": list(available),
            "brightness": 255,
            "transition": DEFAULT_TRANSITION_SECONDS,
        },
        blocking=True,
    )
    await asyncio.sleep(0.18)
    await hass.services.async_call(
        "light",
        "turn_off",
        {
            "entity_id": list(available),
            "transition": DEFAULT_TRANSITION_SECONDS,
        },
        blocking=True,
    )


async def _async_turn_on(
    hass: HomeAssistant, state: BridgeState, *, brightness: int | None = None
) -> None:
    """Mirror dimmer on/brightness to target bulbs."""
    entity_id = (
        _resolve_selected_target(state, hass)
        if _target_cycling_enabled(state)
        else state.target_entity_ids
    )
    LOGGER.info("%s entity IDs toggled: %s", state.name, entity_id)
    service_data: dict[str, object] = {"entity_id": entity_id}
    service_data["transition"] = DEFAULT_TRANSITION_SECONDS
    if brightness is not None:
        service_data["brightness"] = max(1, min(255, brightness))
    await hass.services.async_call(
        "light", "turn_on", service_data, blocking=True
    )
    if _target_cycling_enabled(state):
        state.target_last_on = state.target_last_on or {}
        state.target_last_on["|".join(entity_id)] = True


async def _async_turn_off(hass: HomeAssistant, state: BridgeState) -> None:
    """Mirror dimmer off to target bulbs."""
    entity_id = (
        _resolve_selected_target(state, hass)
        if _target_cycling_enabled(state)
        else state.target_entity_ids
    )
    LOGGER.info("%s entity IDs toggled: %s", state.name, entity_id)
    await hass.services.async_call(
        "light",
        "turn_off",
        {
            "entity_id": entity_id,
            "transition": DEFAULT_TRANSITION_SECONDS,
        },
        blocking=True,
    )
    if _target_cycling_enabled(state):
        state.target_last_on = state.target_last_on or {}
        state.target_last_on["|".join(entity_id)] = False


async def _async_toggle_selected(hass: HomeAssistant, state: BridgeState) -> None:
    """Toggle the currently selected target."""
    selected_label = _resolve_selected_label(state, hass)
    entity_ids = _resolve_selected_target(state, hass)
    if selected_label is not None:
        LOGGER.info(
            "%s selected target before press: %s",
            state.name,
            selected_label,
        )
    states = [hass.states.get(entity_id) for entity_id in entity_ids]
    available_states = [
        entity_state.state
        for entity_state in states
        if entity_state is not None
        and entity_state.state not in ("unknown", "unavailable")
    ]
    if available_states:
        any_on = any(state_value == "on" for state_value in available_states)
    else:
        state.target_last_on = state.target_last_on or {}
        any_on = state.target_last_on.get("|".join(entity_ids), False)
    if any_on:
        await _async_turn_off(hass, state)
        _schedule_focus_reset(hass, state)
        return

    state.suppress_level_until = (
        time.monotonic() + TURN_ON_LEVEL_SUPPRESSION_SECONDS
    )
    await _async_turn_on(hass, state)
    _schedule_focus_reset(hass, state)


def _load_initial_state(hass: HomeAssistant, state: BridgeState) -> None:
    """Prime cached switch state from Matter node data."""
    matter = get_matter(hass)
    node = matter.matter_client.get_node(state.node_id)
    endpoint = node.endpoints[1]
    onoff_cluster = endpoint.get_cluster(clusters.OnOff)
    level_cluster = endpoint.get_cluster(clusters.LevelControl)
    if onoff_cluster is not None:
        state.is_on = bool(getattr(onoff_cluster, "onOff", False))
    if level_cluster is not None:
        level = getattr(level_cluster, "currentLevel", None)
        if isinstance(level, int):
            state.brightness = _matter_to_ha_brightness(level)
            state.last_level_value = int(level)


def _setup_bridge(hass: HomeAssistant, state: BridgeState) -> list[callable]:
    """Subscribe to switch entity state updates for one dimmer."""
    _load_initial_state(hass, state)

    @callback
    def onoff_updated(event: EventType, value: object) -> None:
        if not isinstance(value, bool):
            return
        now = time.monotonic()
        if _target_cycling_enabled(state) and not value:
            state.last_onoff_timestamp = now
            state.last_onoff_value = value
            _reset_hold_tracking(state)
            LOGGER.debug("%s ignoring off edge in target mode", state.name)
            return
        if now < state.ignore_onoff_until:
            LOGGER.info(
                "%s ignoring switch state echo -> %s",
                state.name,
                value,
            )
            state.last_onoff_timestamp = now
            state.last_onoff_value = value
            state.is_on = value
            return
        if (
            state.last_onoff_value is not None
            and state.last_onoff_value != value
            and now - state.last_onoff_timestamp < ONOFF_DEBOUNCE_SECONDS
        ):
            LOGGER.debug("%s ignoring on/off bounce -> %s", state.name, value)
            return
        state.last_onoff_timestamp = now
        state.last_onoff_value = value
        state.is_on = value
        LOGGER.info("%s on/off -> %s", state.name, value)
        if _target_cycling_enabled(state):
            pending = state.pending_single_tap
            if pending is not None and not pending.done():
                pending.cancel()
                state.pending_single_tap = None
                state.last_single_tap_completed_at = 0.0
                hass.async_create_task(_async_cycle_target(hass, state))
                return

            async def _delayed_single_tap() -> None:
                try:
                    await asyncio.sleep(state.double_tap_window_seconds)
                    await _async_toggle_selected(hass, state)
                    state.last_single_tap_completed_at = time.monotonic()
                except asyncio.CancelledError:
                    raise
                finally:
                    state.pending_single_tap = None

            state.last_tap_timestamp = now
            state.pending_single_tap = hass.async_create_task(
                _delayed_single_tap()
            )
            return

        if value:
            # Let adaptive_lighting choose the initial turn-on state.
            state.suppress_level_until = (
                time.monotonic() + TURN_ON_LEVEL_SUPPRESSION_SECONDS
            )
            hass.async_create_task(_async_turn_on(hass, state))
        else:
            hass.async_create_task(_async_turn_off(hass, state))

    @callback
    def level_updated(event: EventType, value: object) -> None:
        if not isinstance(value, int):
            return
        now = time.monotonic()
        previous_value = state.last_level_value
        if (
            previous_value is not None
            and value == previous_value
            and now - state.last_level_timestamp < LEVEL_DEDUPE_WINDOW_SECONDS
        ):
            LOGGER.debug("%s ignoring duplicate level -> %s", state.name, value)
            return
        if (
            previous_value is not None
            and abs(value - previous_value) < BRIGHTNESS_DELTA_THRESHOLD
        ):
            LOGGER.debug("%s ignoring small level delta -> %s", state.name, value)
            state.last_level_value = value
            state.last_level_timestamp = now
            return
        state.last_level_value = value
        state.last_level_timestamp = now
        state.brightness = _matter_to_ha_brightness(value)
        LOGGER.info("%s brightness -> %s", state.name, state.brightness)
        if time.monotonic() < state.suppress_level_until:
            LOGGER.debug(
                "%s ignoring immediate level update to preserve adaptive_lighting",
                state.name,
            )
            _reset_hold_tracking(state)
            return
        if _target_cycling_enabled(state):
            direction = 0
            if previous_value is not None:
                if value > previous_value:
                    direction = 1
                elif value < previous_value:
                    direction = -1

            if direction == 0:
                return

            if (
                state.hold_direction != direction
                or now - state.hold_started_at > HOLD_CYCLE_WINDOW_SECONDS
            ):
                state.hold_direction = direction
                state.hold_start_level = previous_value
                state.hold_started_at = now
                state.hold_update_count = 1
            else:
                state.hold_update_count += 1

            start_level = (
                state.hold_start_level
                if state.hold_start_level is not None
                else previous_value
            )
            reached_edge = (
                value >= HOLD_CYCLE_HIGH_EDGE
                if direction > 0
                else value <= HOLD_CYCLE_LOW_EDGE
            )
            if (
                start_level is not None
                and state.hold_update_count >= HOLD_CYCLE_MIN_UPDATES
                and reached_edge
                and now - state.hold_started_at <= HOLD_CYCLE_WINDOW_SECONDS
            ):
                _reset_hold_tracking(state)
                state.suppress_level_until = (
                    now + TARGET_SWITCH_LEVEL_SUPPRESSION_SECONDS
                )
                hass.async_create_task(_async_cycle_target(hass, state))
                return
        if state.is_on is not False:
            hass.async_create_task(
                _async_turn_on(hass, state, brightness=state.brightness)
            )
            if _target_cycling_enabled(state):
                _schedule_focus_reset(hass, state)

    @callback
    def state_updated(event: Event) -> None:
        new_state = event.data.get("new_state")
        old_state = event.data.get("old_state")
        if new_state is None:
            return

        if old_state is None or old_state.state != new_state.state:
            onoff_updated(
                EventType.ATTRIBUTE_UPDATED,
                new_state.state == "on",
            )

        old_brightness = (
            None
            if old_state is None
            else old_state.attributes.get("brightness")
        )
        new_brightness = new_state.attributes.get("brightness")
        if (
            new_brightness is not None
            and new_brightness != old_brightness
        ):
            matter_level = max(
                1,
                min(
                    254,
                    round((int(new_brightness) * 253 / 255) + 1),
                ),
            )
            level_updated(EventType.ATTRIBUTE_UPDATED, matter_level)

    return [
        async_track_state_change_event(
            hass,
            [state.switch_entity_id],
            state_updated,
        )
    ]


async def async_setup(hass: HomeAssistant, config: dict) -> bool:
    """Set up the Matter dimmer bridge."""
    entries = config.get(DOMAIN, [])
    if not entries:
        return True

    domain_data = hass.data.setdefault(DOMAIN, {})
    domain_data["started"] = False
    domain_data["unsubs"] = []

    states = [
        BridgeState(
            name=entry[CONF_NAME],
            node_id=entry[CONF_NODE_ID],
            switch_entity_id=entry[CONF_SWITCH_ENTITY_ID],
            target_entity_ids=list(entry.get(CONF_TARGET_ENTITY_IDS, [])),
            target_selector=entry.get(CONF_TARGET_SELECTOR),
            targets=[
                TargetSpec(
                    label=target[CONF_LABEL],
                    entity_ids=list(
                        target.get(CONF_ENTITY_IDS)
                        or [target[CONF_ENTITY_ID]]
                    ),
                )
                for target in entry.get(CONF_TARGETS, [])
            ]
            or None,
            double_tap_window_seconds=float(
                entry.get(
                    CONF_DOUBLE_TAP_WINDOW_SECONDS,
                    DOUBLE_TAP_WINDOW_SECONDS,
                )
            ),
        )
        for entry in entries
    ]

    async def _async_start(_: Event | None = None) -> None:
        if domain_data["started"]:
            return
        if MATTER_DOMAIN not in hass.data or not hass.data[MATTER_DOMAIN]:
            LOGGER.info("Matter not ready for dimmer bridge; retrying")
            async def _retry(_: object) -> None:
                await _async_start()
            hass.loop.call_later(
                RETRY_DELAY_SECONDS,
                lambda: hass.async_create_task(_retry(None)),
            )
            return
        try:
            unsubs: list[callable] = []
            for state in states:
                unsubs.extend(_setup_bridge(hass, state))
            domain_data["unsubs"] = unsubs
            domain_data["started"] = True
            LOGGER.info(
                "Started Matter dimmer bridge for %s",
                ", ".join(state.name for state in states),
            )
        except Exception:
            LOGGER.exception("Failed to start Matter dimmer bridge")
            async def _retry(_: object) -> None:
                await _async_start()
            hass.loop.call_later(
                RETRY_DELAY_SECONDS,
                lambda: hass.async_create_task(_retry(None)),
            )

    if hass.is_running:
        hass.async_create_task(_async_start())
    else:
        hass.bus.async_listen_once(EVENT_HOMEASSISTANT_STARTED, _async_start)

    return True
