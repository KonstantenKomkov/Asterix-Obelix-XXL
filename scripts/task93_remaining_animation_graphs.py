#!/usr/bin/env python3
"""Compile every non-Asterix runtime selector into controller dispatch data."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


SCHEMA_VERSION = 1
RESOURCE_TYPE = "asterix.actor-animation-controllers"
EXPECTED_BINDINGS = 318
EXPECTED_PROFILES = 56
CONTEXT_MODES = {
    "gameplay": "controller",
    "scripted": "controller",
    "world": "simultaneous-track-adapter",
    "cinematic": "timeline-adapter",
}


def canonical_bytes(value: dict) -> bytes:
    return (json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ) + "\n").encode("utf-8")


def _require_keys(value: dict, expected: set[str], context: str) -> None:
    if set(value) != expected:
        raise ValueError(
            f"{context}: invalid fields; "
            f"missing={sorted(expected - set(value))}, "
            f"extra={sorted(set(value) - expected)}"
        )


def _binding_key(binding: dict) -> tuple:
    return (
        binding["actor"], binding["skin"], binding["costume"],
        binding["context"], binding["action"], binding["variant"],
    )


def _dictionary_slot(profile: dict, binding: dict) -> int:
    for value in (binding["variant"], *binding.get("catalogVariants", [])):
        match = re.search(r"(?:dictionary-\d+-slot-|hero-slot-)(\d+)$", value)
        if match:
            return int(match.group(1))
    raise ValueError(f"{profile['id']}: binding has no authored dictionary slot")


def validate_resource(resource: dict) -> None:
    _require_keys(
        resource,
        {"schemaVersion", "resourceType", "source", "summary", "profiles"},
        "resource",
    )
    if resource["schemaVersion"] != SCHEMA_VERSION:
        raise ValueError("unsupported actor controller schema")
    if resource["resourceType"] != RESOURCE_TYPE:
        raise ValueError("unexpected actor controller resource type")
    _require_keys(resource["source"], {"sha256"}, "source")
    _require_keys(
        resource["summary"],
        {"profileCount", "bindingCount", "controllerBindings",
         "simultaneousTrackBindings", "timelineBindings"},
        "summary",
    )
    profiles = resource["profiles"]
    if len(profiles) != EXPECTED_PROFILES:
        raise ValueError("actor controller profile coverage is incomplete")
    profile_ids: set[str] = set()
    selectors: set[str] = set()
    bindings = 0
    mode_counts = {
        "controller": 0,
        "simultaneous-track-adapter": 0,
        "timeline-adapter": 0,
    }
    for index, profile in enumerate(profiles):
        _require_keys(
            profile,
            {"id", "actor", "skin", "costume", "context", "dispatchMode",
             "entryState", "terminalStates", "events", "states"},
            f"profile[{index}]",
        )
        profile_id = profile["id"]
        if not isinstance(profile_id, str) or not profile_id or profile_id in profile_ids:
            raise ValueError("duplicate or empty actor controller profile")
        profile_ids.add(profile_id)
        context = profile["context"]
        if CONTEXT_MODES.get(context) != profile["dispatchMode"]:
            raise ValueError(f"{profile_id}: invalid dispatch mode")
        states = profile["states"]
        if not isinstance(states, list) or not states:
            raise ValueError(f"{profile_id}: empty controller graph")
        state_ids: set[str] = set()
        for state in states:
            _require_keys(
                state,
                {"id", "selector", "clip", "loop", "completion",
                 "rootMotion", "deterministicVariantKey"},
                f"{profile_id}.state",
            )
            if state["id"] in state_ids:
                raise ValueError(f"{profile_id}: duplicate state")
            state_ids.add(state["id"])
            selector = state["selector"]
            _require_keys(selector, {"id", "action", "variant"}, "selector")
            if selector["id"] in selectors:
                raise ValueError("selector IDs must be globally unique")
            selectors.add(selector["id"])
            clip = state["clip"]
            _require_keys(clip, {"asset", "dictionary", "slot"}, "clip")
            if (
                not clip["asset"] or clip["dictionary"] < 0 or clip["slot"] < 0
                or state["completion"] not in {"loop", "authoredClipEnd", "terminal"}
                or state["rootMotion"] not in {"inPlace", "authored"}
                or not state["deterministicVariantKey"]
            ):
                raise ValueError(f"{profile_id}: invalid controller state")
        if profile["entryState"] not in state_ids:
            raise ValueError(f"{profile_id}: unknown entry state")
        if any(state not in state_ids for state in profile["terminalStates"]):
            raise ValueError(f"{profile_id}: unknown terminal state")
        seen_event_states: set[str] = set()
        for event in profile["events"]:
            _require_keys(event, {"id", "states"}, f"{profile_id}.event")
            if not event["id"] or not event["states"]:
                raise ValueError(f"{profile_id}: empty event")
            if any(state not in state_ids for state in event["states"]):
                raise ValueError(f"{profile_id}: event selects unknown state")
            if profile["dispatchMode"] != "controller":
                overlap = seen_event_states.intersection(event["states"])
                if overlap:
                    raise ValueError(f"{profile_id}: timeline state is ambiguous")
                seen_event_states.update(event["states"])
        bindings += len(states)
        mode_counts[profile["dispatchMode"]] += len(states)
    if bindings != EXPECTED_BINDINGS or len(selectors) != EXPECTED_BINDINGS:
        raise ValueError("actor controller binding coverage is incomplete")
    expected_summary = {
        "profileCount": EXPECTED_PROFILES,
        "bindingCount": EXPECTED_BINDINGS,
        "controllerBindings": mode_counts["controller"],
        "simultaneousTrackBindings": mode_counts["simultaneous-track-adapter"],
        "timelineBindings": mode_counts["timeline-adapter"],
    }
    if resource["summary"] != expected_summary:
        raise ValueError("actor controller summary is inconsistent")


def _events(profile: dict) -> list[dict]:
    context = profile["context"]
    if context == "world":
        return [
            {"id": event, "states": states}
            for event, states in sorted(profile["eventStates"].items())
        ]
    if context == "cinematic":
        return [
            {"id": f"{profile['scriptEvent']}:{cue.replace('_', '-')}",
             "states": states}
            for cue, states in sorted(
                profile["cueStates"].items(),
                key=lambda item: int(item[0].split("_")[1]),
            )
        ]
    if context == "scripted":
        return [
            {"id": profile["scriptEvent"], "states": list(profile["states"])},
        ]
    return [
        {"id": f"select:{state}", "states": [state]}
        for state in sorted(profile["states"])
    ]


def build_resource(registry: dict) -> dict:
    profiles = []
    binding_index: dict[tuple, list[dict]] = {}
    for binding in registry["bindings"]:
        binding_index.setdefault(_binding_key(binding), []).append(binding)
    consumed: set[tuple] = set()
    for profile in sorted(registry["runtimeProfiles"], key=lambda row: row["id"]):
        if profile["id"] == "asterix-player":
            continue
        states = []
        for state_id, selector in sorted(profile["states"].items()):
            key = (
                profile["actor"], profile["skin"], profile["costume"],
                profile["context"], selector["action"], selector["variant"],
            )
            matches = binding_index.get(key, [])
            if len(matches) != 1:
                raise ValueError(f"{profile['id']}/{state_id}: ambiguous binding")
            binding = matches[0]
            if binding["fallback"]:
                raise ValueError(f"{profile['id']}/{state_id}: fallback is forbidden")
            consumed.add(key)
            states.append({
                "id": state_id,
                "selector": {
                    "id": f"{profile['id']}:select:{state_id}",
                    "action": selector["action"],
                    "variant": selector["variant"],
                },
                "clip": {
                    "asset": binding["clip"],
                    "dictionary": profile["skin"],
                    "slot": _dictionary_slot(profile, binding),
                },
                "loop": binding["loop"],
                "completion": (
                    "loop" if binding["loop"] else
                    "terminal" if "death" in selector["action"] else
                    "authoredClipEnd"
                ),
                "rootMotion": (
                    "authored" if binding["rootMotion"] != "none" else "inPlace"
                ),
                "deterministicVariantKey": (
                    f"{profile['id']}:{selector['action']}:{state_id}"
                ),
            })
        events = _events(profile)
        entry = (
            profile.get("entryState")
            or ("idle" if "idle" in profile["states"] else states[0]["id"])
        )
        terminals = [
            state["id"] for state in states if state["completion"] == "terminal"
        ]
        if profile["context"] == "cinematic":
            terminal_ids = set(events[-1]["states"])
            terminals = list(events[-1]["states"])
            for state in states:
                if state["id"] in terminal_ids:
                    state["completion"] = "terminal"
        profiles.append({
            "id": profile["id"],
            "actor": profile["actor"],
            "skin": profile["skin"],
            "costume": profile["costume"],
            "context": profile["context"],
            "dispatchMode": CONTEXT_MODES[profile["context"]],
            "entryState": entry,
            "terminalStates": terminals,
            "events": events,
            "states": states,
        })
    non_asterix = {
        _binding_key(binding) for binding in registry["bindings"]
        if binding["actor"] != "asterix" or binding["context"] != "gameplay"
        or binding["skin"] != 4 or binding["costume"] != "default"
    }
    if consumed != non_asterix:
        raise ValueError("runtime profiles do not consume all remaining bindings")
    counts = {
        mode: sum(
            len(profile["states"]) for profile in profiles
            if profile["dispatchMode"] == mode
        )
        for mode in set(CONTEXT_MODES.values())
    }
    result = {
        "schemaVersion": SCHEMA_VERSION,
        "resourceType": RESOURCE_TYPE,
        "source": {"sha256": hashlib.sha256(canonical_bytes(registry)).hexdigest()},
        "summary": {
            "profileCount": len(profiles),
            "bindingCount": sum(len(profile["states"]) for profile in profiles),
            "controllerBindings": counts["controller"],
            "simultaneousTrackBindings": counts["simultaneous-track-adapter"],
            "timelineBindings": counts["timeline-adapter"],
        },
        "profiles": profiles,
    }
    validate_resource(result)
    return result


def export(registry_path: Path, output_path: Path) -> bytes:
    result = build_resource(json.loads(registry_path.read_text(encoding="utf-8")))
    payload = canonical_bytes(result)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(payload)
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("registry", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    export(args.registry, args.output)


if __name__ == "__main__":
    main()
