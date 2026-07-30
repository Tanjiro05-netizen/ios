#!/usr/bin/env python3
"""Fail closed on TestFlight package, question, and bundle invariants."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


EXPECTED_COUNTS = {
    "courses": 2,
    "modules": 26,
    "sections": 221,
    "exercises": 52,
    "quizzes": 26,
    "questions": 246,
    "assignments": 11,
    "finalExamPrompts": 38,
    "learningPaths": 1,
    "learnerPDFs": 0,
    "restrictedMarkingGuides": 2,
}
FORBIDDEN_BUNDLE_TERMS = (
    "RestrictedCourseContent",
    "marking-guide-restricted",
    "MarxistInfo_Course_Content_Only",
    "MarxistForum-GitHub-Pages-HTML",
    "JenaResearchLogo",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def validate_package(root: Path) -> None:
    report_path = root / "Tools/dialectics-import-report.json"
    package_path = root / "Resources/Marxist_Info_Dialectics_v1.study-course.json"
    catalogue_path = root / "Resources/Marxist_Info_Full_Question_Catalogue.json"
    report = json.loads(report_path.read_text())
    package = json.loads(package_path.read_text())
    catalogue = json.loads(catalogue_path.read_text())

    require(report["schemaVersion"] == 3, "unexpected import-report schema")
    for key, value in EXPECTED_COUNTS.items():
        require(report["counts"][key] == value, f"{key} count changed")
    require([course["id"] for course in package["courses"]] == ["PHI111", "PHI211"], "course IDs/order changed")
    path_course_ids = [item["courseID"] for item in package["learningPaths"][0]["courses"]]
    require(path_course_ids == ["PHI111", "PHI211"], "sequel path changed")
    require(len(catalogue["items"]) == 529, "canonical catalogue is incomplete")
    require(len({item["id"] for item in catalogue["items"]}) == 529, "catalogue IDs are not unique")
    require(all(item["qa_status"] != "reviewed" for item in catalogue["items"]), "review status changed without register update")
    require(sum(item["qa_status"] == "flagged" for item in catalogue["items"]) == 1, "flagged-question count changed")
    require(all(question["qaStatus"] == "draft_needs_academic_review" for question in package["questions"]), "course question review state changed")
    require(not report["nativeContentValidation"]["restrictedMarkingGuideTextIncluded"], "restricted marking-guide text entered learner package")
    require(report["sourceManifestAudit"]["hashOrSizeMismatches"] == [], "source manifest contains a hash/size mismatch")
    require(len(report["sourceManifestAudit"]["missingDeclaredFiles"]) == 6, "provenance exception count changed")

    digest = hashlib.sha256(package_path.read_bytes()).hexdigest()
    require(digest == report["generatedPackage"]["sha256"], "learner-package SHA-256 differs from import report")


def validate_bundle(bundle: Path) -> None:
    require(bundle.is_dir(), f"app bundle not found: {bundle}")
    names = [str(path.relative_to(bundle)) for path in bundle.rglob("*")]
    for forbidden in FORBIDDEN_BUNDLE_TERMS:
        require(not any(forbidden.lower() in name.lower() for name in names), f"forbidden bundle artifact: {forbidden}")
    require(any(name.endswith("PrivacyInfo.xcprivacy") for name in names), "privacy manifest missing from app bundle")
    require(any(name.endswith("Marxist_Info_Dialectics_v1.study-course.json") for name in names), "course package missing from app bundle")
    require(any(name.endswith("Marxist_Info_Full_Question_Catalogue.json") for name in names), "question catalogue missing from app bundle")
    require(not any(name.lower().endswith(".pdf") for name in names), "learner app unexpectedly contains a PDF")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--app-bundle", type=Path)
    args = parser.parse_args()
    validate_package(args.root)
    if args.app_bundle:
        validate_bundle(args.app_bundle)
    print("PASS: TestFlight content and bundle invariants")


if __name__ == "__main__":
    main()
