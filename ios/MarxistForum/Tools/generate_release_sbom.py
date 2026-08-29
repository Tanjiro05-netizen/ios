#!/usr/bin/env python3
"""Generate a deterministic CycloneDX SBOM from SwiftPM and Edge imports."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


LICENSES = {
    "cryptoswift": "Zlib",
    "differencekit": "Apache-2.0",
    "fuzi": "MIT",
    "gcdwebserver": "BSD-3-Clause",
    "sqlite.swift": "MIT",
    "supabase-swift": "MIT",
    "swift-asn1": "Apache-2.0",
    "swift-clocks": "MIT",
    "swift-concurrency-extras": "MIT",
    "swift-crypto": "Apache-2.0",
    "swift-http-types": "Apache-2.0",
    "swift-toolkit": "BSD-3-Clause",
    "swiftsoup": "MIT",
    "xctest-dynamic-overlay": "MIT",
    "zip": "MIT",
    "zipfoundation": "MIT",
}


def component_from_pin(pin: dict) -> dict:
    identity = pin["identity"]
    state = pin["state"]
    version = state.get("version") or state["revision"]
    component = {
        "type": "library",
        "name": identity,
        "version": version,
        "bom-ref": f"pkg:swift/{identity}@{version}",
        "purl": f"pkg:swift/{identity}@{version}",
        "externalReferences": [
            {"type": "vcs", "url": pin["location"]},
        ],
        "properties": [
            {"name": "swiftpm:revision", "value": state["revision"]},
        ],
    }
    if identity in LICENSES:
        component["licenses"] = [{"license": {"id": LICENSES[identity]}}]
    return component


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--resolved", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    resolved = json.loads(args.resolved.read_text())
    components = [component_from_pin(pin) for pin in resolved["pins"]]
    components.extend(
        [
            {
                "type": "library",
                "name": "@supabase/supabase-js",
                "version": "2.49.4",
                "bom-ref": "pkg:npm/%40supabase/supabase-js@2.49.4",
                "purl": "pkg:npm/%40supabase/supabase-js@2.49.4",
                "licenses": [{"license": {"id": "MIT"}}],
            },
            {
                "type": "library",
                "name": "Deno standard/http/server",
                "version": "0.224.0",
                "bom-ref": "pkg:generic/deno-std-http@0.224.0",
                "purl": "pkg:generic/deno-std-http@0.224.0",
                "licenses": [{"license": {"id": "MIT"}}],
            },
        ]
    )
    components.sort(key=lambda item: item["bom-ref"])
    sbom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": "urn:uuid:19d82351-28d7-4ba4-a843-3f46ab3c1792",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "name": "MarxistInfo",
                "version": "1.0+2",
            }
        },
        "components": components,
    }
    args.output.write_text(json.dumps(sbom, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
