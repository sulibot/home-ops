from pathlib import Path

path = Path("/config/custom_components/matter_dimmer_bridge/__init__.py")
text = path.read_text()

old_import = "from homeassistant.helpers import config_validation as cv\n"
new_import = (
    "from homeassistant.helpers import config_validation as cv\n"
    "from homeassistant.helpers.event import async_track_state_change_event\n"
)
if "async_track_state_change_event" not in text:
    text = text.replace(old_import, new_import)

start = text.index("def _setup_bridge(hass: HomeAssistant, state: BridgeState) -> list[callable]:")
end = text.index("\n\nasync def async_setup(", start)

replacement = """def _setup_bridge(hass: HomeAssistant, state: BridgeState) -> list[callable]:
    \"\"\"Subscribe to switch entity state updates for one dimmer.\"\"\"
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
            LOGGER.debug(\"%s ignoring off edge in target mode\", state.name)
            return
        if now < state.ignore_onoff_until:
            LOGGER.info(
                \"%s ignoring switch state echo -> %s\",
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
            LOGGER.debug(\"%s ignoring on/off bounce -> %s\", state.name, value)
            return
        state.last_onoff_timestamp = now
        state.last_onoff_value = value
        state.is_on = value
        LOGGER.info(\"%s on/off -> %s\", state.name, value)
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
            LOGGER.debug(\"%s ignoring duplicate level -> %s\", state.name, value)
            return
        if (
            previous_value is not None
            and abs(value - previous_value) < BRIGHTNESS_DELTA_THRESHOLD
        ):
            LOGGER.debug(\"%s ignoring small level delta -> %s\", state.name, value)
            state.last_level_value = value
            state.last_level_timestamp = now
            return
        state.last_level_value = value
        state.last_level_timestamp = now
        state.brightness = _matter_to_ha_brightness(value)
        LOGGER.info(\"%s brightness -> %s\", state.name, state.brightness)
        if time.monotonic() < state.suppress_level_until:
            LOGGER.debug(
                \"%s ignoring immediate level update to preserve adaptive_lighting\",
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
        new_state = event.data.get(\"new_state\")
        old_state = event.data.get(\"old_state\")
        if new_state is None:
            return

        if old_state is None or old_state.state != new_state.state:
            onoff_updated(
                EventType.ATTRIBUTE_UPDATED,
                new_state.state == \"on\",
            )

        old_brightness = (
            None
            if old_state is None
            else old_state.attributes.get(\"brightness\")
        )
        new_brightness = new_state.attributes.get(\"brightness\")
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
"""

text = text[:start] + replacement + text[end:]
path.write_text(text)
print("patched")
