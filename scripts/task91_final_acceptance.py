#!/usr/bin/env python3
"""Finalize the task 91 catalog/registry and build the strict acceptance report."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path

import task91_provenance_gate


EXPECTED_PROVENANCE_SHA256 = (
    "f71e47e63439ef29e39a7aff955f32f0d45a770b53c2aed2b6adae825a01c943"
)
EXPECTED_CATALOG_CLIPS = 345
EXPECTED_DICTIONARIES = 52
EXPECTED_DICTIONARY_SLOTS = 518


def _canonical_bytes(value: dict) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def _sha256(value: dict) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _profiles(registry: dict) -> dict[str, dict]:
    profiles = registry.get("runtimeProfiles")
    if not isinstance(profiles, list):
        raise ValueError("runtime registry has no profiles")
    result = {profile.get("id"): profile for profile in profiles}
    if len(result) != len(profiles) or None in result:
        raise ValueError("runtime profile ids are missing or duplicated")
    return result


def _binding_for_selector(registry: dict, profile: dict, selector: dict) -> dict:
    matches = [
        binding
        for binding in registry.get("bindings", [])
        if binding.get("actor") == profile.get("actor")
        and binding.get("skin") == profile.get("skin")
        and binding.get("costume") == profile.get("costume")
        and binding.get("context") == profile.get("context")
        and binding.get("action") == selector.get("action")
        and binding.get("variant") == selector.get("variant")
        and binding.get("fallback") is False
    ]
    if len(matches) != 1:
        raise ValueError(
            f"{profile.get('id')}: selector does not resolve one exact binding"
        )
    return matches[0]


def _clip_id(binding: dict) -> str:
    source = binding.get("clip")
    if not isinstance(source, str) or not source.endswith(".animation.json"):
        raise ValueError("runtime binding has no authored clip")
    return f"clip-{source.removesuffix('.animation.json')}"


def _catalog_clips(catalog: dict) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for clip in catalog.get("clips", []):
        source = clip.get("source")
        if not isinstance(source, str) or source in result:
            raise ValueError(f"catalog clip source is missing or duplicated: {source}")
        result[source] = clip
    return result


def finalize(catalog: dict, registry: dict, provenance: dict) -> tuple[dict, dict, dict]:
    task91_provenance_gate.validate(provenance, registry)
    provenance_sha256 = _sha256(provenance)
    if provenance_sha256 != EXPECTED_PROVENANCE_SHA256:
        raise ValueError("provenance digest does not match the accepted replay")

    if catalog.get("clipCount") != EXPECTED_CATALOG_CLIPS:
        raise ValueError("catalog clip total changed")
    if catalog.get("dictionaryCount") != EXPECTED_DICTIONARIES:
        raise ValueError("catalog dictionary total changed")
    slot_count = sum(len(row.get("slots", [])) for row in catalog.get("dictionaries", []))
    if slot_count != EXPECTED_DICTIONARY_SLOTS:
        raise ValueError("catalog dictionary slot total changed")

    updated_catalog = copy.deepcopy(catalog)
    updated_registry = copy.deepcopy(registry)
    profiles = _profiles(updated_registry)
    catalog_clips = _catalog_clips(updated_catalog)
    proven_bindings: set[str] = set()
    assertions: dict[str, dict] = {}

    for evidence in provenance["evidence"]:
        profile_id = evidence["profile"]
        state_name = evidence["binding"]
        profile = profiles.get(profile_id)
        if profile is None:
            raise ValueError(f"{evidence['bindingKey']}: unknown runtime profile")
        selector = profile["states"].get(state_name)
        if not isinstance(selector, dict):
            raise ValueError(f"{evidence['bindingKey']}: unknown runtime state/event")
        binding = _binding_for_selector(updated_registry, profile, selector)
        if _clip_id(binding) != evidence["assetJoin"]["clip"]:
            raise ValueError(f"{evidence['bindingKey']}: registry clip disagrees with evidence")

        dictionary = evidence["assetJoin"]["dictionary"]
        slot = evidence["assetJoin"]["slot"]
        catalog_clip = catalog_clips.get(binding["clip"])
        if catalog_clip is None:
            raise ValueError(f"{evidence['bindingKey']}: catalog clip disagrees with evidence")
        proven_bindings.add(evidence["bindingKey"])

        proof = {
            "evidenceId": evidence["evidenceId"],
            "dictionary": dictionary,
            "slot": slot,
            "clip": evidence["assetJoin"]["clip"],
            "stateOrEvent": evidence["stateOrEvent"],
        }
        selector["authoredProvenance"] = proof
        catalog_clip.setdefault("authoredRuntimeBindings", []).append({
            "evidenceId": evidence["evidenceId"],
            "runtimeProfile": profile_id,
            "runtimeBinding": state_name,
            "dictionary": dictionary,
            "slot": slot,
            "stateOrEvent": evidence["stateOrEvent"],
        })

        if evidence["bindingKey"] in {
            "asterix-player:jump",
            "asterix-player:double_jump",
        }:
            assertions[evidence["bindingKey"]] = {
                "status": "passed",
                **proof,
            }

    expected_bindings = {row["bindingKey"] for row in provenance["evidence"]}
    if proven_bindings != expected_bindings:
        raise ValueError("catalog/provenance binding coverage is incomplete")
    expected_assertions = {
        "asterix-player:jump": (13, "clip-0031"),
        "asterix-player:double_jump": (35, "clip-0064"),
    }
    for key, (slot, clip) in expected_assertions.items():
        assertion = assertions.get(key)
        if (
            assertion is None
            or assertion["dictionary"] != 0
            or assertion["slot"] != slot
            or assertion["clip"] != clip
        ):
            raise ValueError(f"{key}: dedicated jump assertion failed")

    proof_summary = {
        "schemaVersion": 1,
        "provenanceSha256": provenance_sha256,
        "confirmedBindings": len(provenance["evidence"]),
        "unresolvedBindings": 0,
        "ambiguousBindings": 0,
        "visualOnlyBindings": 0,
    }
    updated_catalog["authoredBindingProvenance"] = proof_summary
    updated_registry["authoredBindingProvenance"] = proof_summary
    report = {
        "schemaVersion": 1,
        "dataset": "XXL1/LVL01",
        "status": "passed",
        "summary": {
            "catalogClips": EXPECTED_CATALOG_CLIPS,
            "dictionaries": EXPECTED_DICTIONARIES,
            "dictionarySlots": EXPECTED_DICTIONARY_SLOTS,
            **proof_summary,
        },
        "jumpAssertions": assertions,
        "artifacts": {
            "catalogSha256": _sha256(updated_catalog),
            "registrySha256": _sha256(updated_registry),
        },
    }
    return updated_catalog, updated_registry, report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("catalog", type=Path)
    parser.add_argument("registry", type=Path)
    parser.add_argument("provenance", type=Path)
    parser.add_argument("catalog_output", type=Path)
    parser.add_argument("registry_output", type=Path)
    parser.add_argument("acceptance_output", type=Path)
    args = parser.parse_args()
    catalog, registry, report = finalize(
        json.loads(args.catalog.read_text()),
        json.loads(args.registry.read_text()),
        json.loads(args.provenance.read_text()),
    )
    for path, value in (
        (args.catalog_output, catalog),
        (args.registry_output, registry),
        (args.acceptance_output, report),
    ):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(_canonical_bytes(value))


if __name__ == "__main__":
    main()
