#!/usr/bin/env python3
"""Convert the dialectics content archive into the app's native StudyCoursePackage.

The archive is deliberately treated as an authoring source. This importer emits the
existing app model with complete native Markdown and structured assessment content.
Learner PDFs are intentionally not registered or copied into the application; the
restricted examiner material remains outside the application target.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path
from typing import Any


COURSE_IDS = ("PHI111", "PHI211")
EXPECTED = {
    "courses": 2,
    "modules": 26,
    "sections": 221,
    "exercises": 52,
    "quizzes": 26,
    "moduleQuestions": 208,
    "writtenExamQuestions": 38,
    "questions": 246,
    "assignments": 11,
    "finalExamPrompts": 38,
    "learningPaths": 1,
    "learnerPDFs": 0,
    "restrictedMarkingGuides": 2,
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def read_text(path: Path) -> str:
    # Markdown used in native course readers must remain an exact authoring-source
    # payload. Reading bytes explicitly avoids universal-newline conversion.
    return path.read_bytes().decode("utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_record(path: Path) -> dict[str, Any]:
    return {"sha256": sha256(path), "byteCount": path.stat().st_size}


def audit_source_manifest(archive: Path) -> dict[str, Any]:
    manifest = read_json(archive / "content-manifest.json")
    declared = {item["path"]: item for item in manifest["files"]}
    missing: list[str] = []
    mismatched: list[dict[str, Any]] = []
    verified = 0
    for relative_path, record in declared.items():
        path = archive / relative_path
        if not path.is_file():
            missing.append(relative_path)
            continue
        actual_size = path.stat().st_size
        actual_hash = sha256(path)
        if actual_size != record["bytes"] or actual_hash != record["sha256"]:
            mismatched.append({
                "path": relative_path,
                "expectedBytes": record["bytes"],
                "actualBytes": actual_size,
                "expectedSHA256": record["sha256"],
                "actualSHA256": actual_hash,
            })
        else:
            verified += 1
    if mismatched:
        raise ValueError(f"Source manifest integrity failed for {len(mismatched)} file(s)")

    actual_files = {
        str(path.relative_to(archive))
        for path in archive.rglob("*")
        if path.is_file()
    }
    return {
        "declaredFiles": len(declared),
        "verifiedDeclaredFiles": verified,
        "missingDeclaredFiles": sorted(missing),
        "hashOrSizeMismatches": mismatched,
        "unlistedFiles": sorted(actual_files - set(declared)),
    }


def first_course_purpose(overview: str) -> str:
    match = re.search(r"^## Course purpose\s*$\n+(.*?)(?:\n\s*\n|\Z)", overview, re.MULTILINE | re.DOTALL)
    if not match:
        raise ValueError("Course overview has no Course purpose paragraph")
    return match.group(1).strip()


def workload_hours(text: str) -> int:
    values = [int(value) for value in re.findall(r"\d+", text)]
    if not values:
        raise ValueError(f"Cannot convert workload: {text}")
    return round(sum(values[:2]) / min(2, len(values)))


MARKER = re.compile(r"^\s*(?:\{\{(?:exercise|quiz):[^}]+\}\}|\[\[(?:EXERCISE|QUIZ|MILESTONE|SOLUTIONS):?[^]]*\]\])\s*$", re.IGNORECASE)


def section_body(source: str) -> tuple[str, int]:
    lines = source.splitlines()
    if lines and re.match(r"^#{1,6}\s+", lines[0]):
        lines = lines[1:]
    removed = sum(1 for line in lines if MARKER.match(line))
    cleaned = [line for line in lines if not MARKER.match(line)]
    return "\n".join(cleaned).strip(), removed


def native_reading_markdown(source: str) -> str:
    """Remove authoring placement tokens without changing the surrounding prose.

    Exercises, quizzes, milestones, and solution sets are represented by native
    structured records. Showing their authoring tokens in a learner document would
    be both incomplete and misleading, so only those token-only lines are omitted.
    """

    return "".join(
        line
        for line in source.splitlines(keepends=True)
        if not MARKER.match(line.rstrip("\r\n"))
    )


def split_guide(markdown: str, course_id: str) -> list[dict[str, str]]:
    sections: list[dict[str, str]] = []
    title: str | None = None
    body: list[str] = []
    index = 0
    for line in markdown.splitlines():
        match = re.match(r"^#\s+(.+?)\s*$", line)
        if match:
            if title is not None:
                index += 1
                sections.append({
                    "id": f"{course_id}-GUIDE-SECTION-{index:02d}",
                    "title": title,
                    "bodyMarkdown": "\n".join(body).strip(),
                })
            title = match.group(1)
            body = []
        else:
            body.append(line)
    if title is not None:
        index += 1
        sections.append({
            "id": f"{course_id}-GUIDE-SECTION-{index:02d}",
            "title": title,
            "bodyMarkdown": "\n".join(body).strip(),
        })
    if not sections:
        raise ValueError(f"{course_id} guide has no top-level sections")
    return sections


MODULE_GUIDE_HEADING = re.compile(
    r"^##[ \t]+(?P<title>Guide to Module[ \t]+(?P<number>\d+)\b[^\r\n]*)$",
    re.MULTILINE,
)
GUIDE_SECTION_BOUNDARY = re.compile(r"^(?:#(?!#)|##)[ \t]+", re.MULTILINE)


def module_reading_guide_chunks(
    markdown: str,
    course_id: str,
    modules: list[dict[str, Any]],
    estimated_minutes: int,
) -> list[dict[str, Any]]:
    """Extract each authored module guide without rewriting its Markdown body.

    The heading text is retained exactly (minus its Markdown ``## `` marker), and
    ``bodyMarkdown`` is the exact source slice from the end of that H2 heading to
    the next H2 or H1 boundary. This intentionally retains author-supplied blank
    lines, thematic breaks, lists, tables, quotations, and lower-level headings.
    """

    matches = list(MODULE_GUIDE_HEADING.finditer(markdown))
    if len(matches) != len(modules):
        raise ValueError(
            f"{course_id} module reading-guide count mismatch: "
            f"expected {len(modules)}, got {len(matches)}"
        )

    chunks: list[dict[str, Any]] = []
    for index, (match, module) in enumerate(zip(matches, modules), start=1):
        source_number = int(match.group("number"))
        if source_number != index:
            raise ValueError(
                f"{course_id} reading guide is out of order: "
                f"expected module {index}, got {source_number}"
            )
        next_boundary = GUIDE_SECTION_BOUNDARY.search(markdown, match.end())
        body_end = next_boundary.start() if next_boundary else len(markdown)
        body = markdown[match.end():body_end]
        chunks.append({
            "id": f"{course_id}-READING-GUIDE-MODULE-{index:02d}",
            "title": match.group("title"),
            "anchorLabel": f"Module {index}",
            "estimatedMinutes": estimated_minutes,
            "terms": [],
            "prompts": [],
            "libraryBookID": None,
            "moduleID": module["id"],
            "bodyMarkdown": body,
        })
    return chunks


def recommended_quiz_minutes(quiz: dict[str, Any]) -> tuple[int | None, int | None]:
    """Normalise both source representations without discarding their ranges."""

    structured = quiz.get("recommended_time_minutes")
    if isinstance(structured, dict):
        return structured.get("minimum"), structured.get("maximum")

    authored = quiz.get("recommended_time")
    if isinstance(authored, str):
        values = [int(value) for value in re.findall(r"\d+", authored)]
        if len(values) >= 2:
            return values[0], values[1]
        if len(values) == 1:
            return values[0], values[0]
        raise ValueError(f"Cannot parse recommended quiz time: {authored}")

    return None, None


def course_conclusion_markdown(course_source: str, course_id: str) -> str | None:
    """Return the exact authored conclusion body when the source contains one."""

    heading = re.search(
        r"^# Course Conclusion - What It Means to Read Marx Dialectically$",
        course_source,
        re.MULTILINE,
    )
    if heading is None:
        return None
    boundary = re.search(r"^# End of the Full Course$", course_source[heading.end():], re.MULTILINE)
    if boundary is None:
        raise ValueError(f"{course_id} course conclusion has no End of the Full Course boundary")
    body_end = heading.end() + boundary.start()
    return course_source[heading.end():body_end]


def candidate_exam_markdown(source: str, course_id: str) -> tuple[str, str]:
    """Extract candidate-facing exam bookends from the archive's native text.

    PHI111's PDF-to-Markdown source placed A1's ``[2 marks]`` token before the
    exam front matter. Removing that isolated token is a formatting correction;
    the question's two-point value remains in its structured native record.
    """

    section_a_markers = {
        "PHI111": "Section A - Precise Distinctions",
        "PHI211": "S ECTION A - 20 MARKS Precise Conceptual Distinctions",
    }
    section_marker = section_a_markers[course_id]
    section_start = source.find(section_marker)
    if section_start < 0:
        raise ValueError(f"Cannot find Section A boundary in {course_id} native examination text")
    instructions = source[:section_start].strip()
    if course_id == "PHI111":
        instructions = instructions.replace(
            "\n\n[2 marks] Final Examination Time allowed",
            "\n\nFinal Examination Time allowed",
            1,
        )
    # PHI211's first three two-mark labels were likewise emitted immediately
    # before the Section A boundary rather than beside their questions.
    instructions = re.sub(r"\n\n(?:\[\d+(?: marks)?\]\s*)+$", "", instructions).rstrip()

    declaration_match = re.search(r"^S UBMISSION Candidate Declaration\b", source, re.MULTILINE)
    if declaration_match is None:
        raise ValueError(f"Cannot find candidate declaration in {course_id} native examination text")
    declaration = source[declaration_match.start():].strip()
    if not instructions or not declaration:
        raise ValueError(f"Empty candidate-facing examination text for {course_id}")
    return instructions, declaration


EXAM_SECTION_MARKERS = {
    "PHI111": {
        "A": "Section A - Precise Distinctions",
        "B": "S ECTION B · 20 MARKS Passage Analysis",
        "C": "S ECTION C · 25 MARKS Logical Reconstruction",
        "D": "S ECTION D · 35 MARKS Synoptic Essay",
    },
    "PHI211": {
        "A": "S ECTION A - 20 MARKS Precise Conceptual Distinctions",
        "B": "S ECTION B - 20 MARKS Primary-Passage Analysis",
        "C": "S ECTION C - 25 MARKS Methodological Reconstruction",
        "D": "S ECTION D - 35 MARKS Synoptic Essay",
    },
}


def exam_section_instructions(
    source: str,
    course_id: str,
    final_exam: dict[str, Any],
) -> dict[str, str]:
    """Extract the exact prose between each section heading and first prompt."""

    result: dict[str, str] = {}
    for section_code in ("A", "B", "C", "D"):
        marker = EXAM_SECTION_MARKERS[course_id][section_code]
        marker_start = source.find(marker)
        if marker_start < 0:
            raise ValueError(f"Cannot find {course_id} examination Section {section_code} heading")
        body_start = marker_start + len(marker)
        first_question = next(
            item for item in final_exam["questions"] if item["section"] == section_code
        )
        prompt_start = source.find(first_question["prompt"], body_start)
        if prompt_start < 0:
            raise ValueError(
                f"Cannot locate first prompt after {course_id} examination Section {section_code}"
            )
        instructions = source[body_start:prompt_start].strip()
        suffixes = []
        if first_question.get("title"):
            suffixes.append(f"{first_question['code']} - {first_question['title']}")
        suffixes.extend((f"{first_question['code']}.", first_question["code"]))
        for suffix in suffixes:
            if instructions.endswith(suffix):
                instructions = instructions[:-len(suffix)].rstrip()
                break
        if not instructions or source.find(instructions, body_start, prompt_start) < 0:
            raise ValueError(
                f"Empty or non-source-derived instructions for {course_id} Section {section_code}"
            )
        result[section_code] = instructions
    return result


def bibliography_records(markdown: str, course_id: str) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for line in markdown.splitlines():
        if not line.startswith("- "):
            continue
        citation = line[2:].strip()
        url_match = re.search(r"\((https?://[^)]+)\)", citation)
        records.append({
            "id": f"{course_id}-BIB-{len(records) + 1:03d}",
            "citation": citation,
            "url": url_match.group(1) if url_match else None,
            "note": None,
        })
    return records


def glossary_records(course_dir: Path, guide_markdown: str, course_id: str) -> list[dict[str, Any]]:
    source = read_json(course_dir / "glossary.json").get("terms", [])
    if source:
        return [{
            "id": term["id"],
            "term": term["term"],
            "definitionMarkdown": term["definition_markdown"],
            "sourceIDs": [course_id],
            "relatedTermIDs": [],
            "displayTitle": term.get("display_title"),
            "legacySourceID": term["id"],
        } for term in source]

    glossary_match = re.search(
        r"^#\s+\d+\.\s+Technical Glossary\s*$\n(.*?)(?=^---\s*$|^#\s+\d+\.)",
        guide_markdown,
        re.MULTILINE | re.DOTALL,
    )
    if not glossary_match:
        raise ValueError(f"{course_id} has neither structured nor guide glossary")
    records = []
    for term, definition in re.findall(r"^\*\*(.+?):\*\*\s*(.+?)\s*$", glossary_match.group(1), re.MULTILINE):
        records.append({
            "id": f"{course_id}-G-GUIDE-{len(records) + 1:03d}",
            "term": term,
            "definitionMarkdown": definition,
            "sourceIDs": [f"{course_id}-STUDY-READING-GUIDE"],
            "relatedTermIDs": [],
            "displayTitle": term,
            "legacySourceID": None,
        })
    return records


def format_assignment_markdown(markdown: str) -> str:
    lines = markdown.splitlines()
    if lines and lines[0].startswith("# "):
        lines = lines[1:]
    body = "\n".join(lines).strip()
    labels = [
        "Purpose and outcomes",
        "Assignment task",
        "Required deliverables",
        "Minimum scholarly requirements",
        "Analytic Rubric",
        "Analytic rubric",
        "Pre-submission audit",
        "ASSESSMENT STANDARDS",
        "OVERALL RESULT",
    ]
    for label in labels:
        body = re.sub(rf"(?<!#)\s+{re.escape(label)}\s+", f"\n\n## {label}\n\n", body)
    return body.strip()


RUBRIC_LEVELS = {
    "excellent": "Precise, independent, and fully supported; distinctions are sustained throughout.",
    "competent": "Substantially accurate and supported, with minor gaps or unevenness.",
    "developing": "Partial command; important distinctions or evidence are underdeveloped.",
    "insufficient": "Major conceptual errors, unsupported claims, or missing required work.",
}


def assignment_rubric(markdown: str, assignment_id: str) -> list[dict[str, str]]:
    """Recover the source rubric as structured native marking criteria.

    The archive's assignment Markdown is a flattened PDF extraction. Its four
    level descriptors are nevertheless exact and repeated after every criterion,
    which lets us restore the table without rewriting any academic wording.
    """

    marker = "Analytic Rubric Criterion Excellent Competent Developing Insufficient "
    if marker not in markdown:
        marker = "Analytic rubric Criterion Excellent Competent Developing Insufficient "
    criteria: list[dict[str, str]] = []
    if marker in markdown:
        rubric = markdown.split(marker, 1)[1]
        sequence = " ".join(RUBRIC_LEVELS.values())
        parts = rubric.split(sequence)
        for index, part in enumerate(parts[:-1], start=1):
            title = part.strip(" \n\r\t•")
            if not title:
                raise ValueError(f"{assignment_id} rubric criterion {index} has no title")
            criteria.append({
                "id": f"{assignment_id}.rubric.{index}",
                "title": title,
                **RUBRIC_LEVELS,
            })
    else:
        # PHI211 supplies a weighted analytic rubric with a single exact
        # "Excellent performance" descriptor rather than four level columns.
        # Preserve that difference; empty lower-level strings are preferable to
        # inventing assessment language that is absent from the source.
        rubric = markdown.split("Analytic rubric Dimension Share Excellent performance ", 1)[-1]
        rubric = rubric.split("Pre-submission audit", 1)[0]
        rubric = re.sub(
            r"(?:1\. 2\. 3\. 4\. )?FORMAL ASSIGNMENTS - VERSION 1\.0 Dimension Share Excellent performance ",
            "",
            rubric,
        )
        matches = re.findall(
            r"(.+?) (\d+)% (Accurate, complete, source-?controlled, and analytically independent\.)",
            rubric,
        )
        for index, (title, _share, excellent) in enumerate(matches, start=1):
            criteria.append({
                "id": f"{assignment_id}.rubric.{index}",
                "title": title.strip(),
                "excellent": excellent,
                "competent": "",
                "developing": "",
                "insufficient": "",
            })
    if not criteria:
        raise ValueError(f"{assignment_id} produced no rubric criteria")
    return criteria


def module_solution_markdown(module: dict[str, Any], exercises: list[dict[str, Any]], quiz: dict[str, Any]) -> str:
    """Assemble exact authored exercise guidance and quiz feedback for one module."""

    lines = [f"### {module['title']}"]
    for exercise in exercises:
        lines.extend((
            "",
            f"#### {exercise['title']}",
            "",
            exercise["prompt"],
        ))
        instructions = exercise.get("instructions", [])
        if instructions:
            lines.extend(("", "**Instructions**", ""))
            lines.extend(f"- {instruction}" for instruction in instructions)
        recommended = exercise.get("recommended_response")
        if recommended:
            lines.extend(("", f"**Recommended response:** {recommended}"))
        lines.extend(("", "**Solution or model guidance**", "", exercise["solution"]))

    lines.extend(("", "#### Module quiz answer guidance"))
    for question in quiz["questions"]:
        lines.extend(("", f"##### {question['id']}", "", question["stem"]))
        for option in question.get("options", []):
            lines.append(f"- **{option['id']}.** {option['text']}")
        if question.get("answer_key"):
            lines.extend(("", f"**Answer key:** {question['answer_key']}"))
        if question.get("expected_answer"):
            lines.extend(("", f"**Expected response:** {question['expected_answer']}"))
        if question.get("commentary"):
            lines.extend(("", f"**Explanation:** {question['commentary']}"))
    return "\n".join(lines).strip()


def native_formative_solutions_markdown(course_dir: Path, course_id: str) -> str:
    """Materialise the source template's solution tokens as complete native text."""

    modules_index = read_json(course_dir / "modules.json")["modules"]
    module_sections: list[str] = []
    replacements: dict[int, str] = {}
    for module_number, indexed_module in enumerate(modules_index, start=1):
        module_dir = course_dir / indexed_module["path"]
        module = read_json(module_dir / "module.json")
        exercises = read_json(module_dir / module["exercise_file"])["exercises"]
        quiz = read_json(module_dir / module["quiz_file"])
        rendered = module_solution_markdown(module, exercises, quiz)
        replacements[module_number] = rendered
        module_sections.append(rendered)

    template_path = course_dir / "guides" / "formative-solutions-source.md"
    if not template_path.is_file():
        return "# Formative Assessment Solutions and Commentary\n\n" + "\n\n---\n\n".join(module_sections) + "\n"

    rendered = read_text(template_path)
    for module_number, replacement in replacements.items():
        rendered = rendered.replace(f"[[SOLUTIONS:{module_number}]]", replacement)
    unresolved = re.findall(r"\[\[SOLUTIONS:[^]]+\]\]", rendered)
    if unresolved:
        raise ValueError(f"Unresolved formative solution markers for {course_id}: {unresolved}")
    return rendered


def normalized_objective_key(question: dict[str, Any]) -> str:
    if question["type"] not in ("single_choice", "multiple_choice"):
        return ""
    valid = {option["id"].upper() for option in question.get("options", [])}
    tokens = [token for token in re.findall(r"\b[A-Z]\b", question.get("answer_key", "").upper()) if token in valid]
    return "".join(dict.fromkeys(tokens))


def matching_pairs(question: dict[str, Any]) -> dict[str, str]:
    if question["type"] != "matching":
        return {}
    candidates = [question.get("expected_answer", ""), question.get("answer_key", "")]
    descriptions = {item["id"] for item in question.get("matching_descriptions", [])}
    pairs: dict[str, str] = {}
    for term in question.get("matching_terms", []):
        for candidate in candidates:
            match = re.search(rf"{re.escape(term['text'])}\s*[-–—]\s*([A-Za-z0-9]+)", candidate)
            if match and match.group(1) in descriptions:
                pairs[term["id"]] = match.group(1)
                break
    return pairs


def native_question(question: dict[str, Any], module_title: str, source_file: str) -> dict[str, Any]:
    options = {option["id"]: option["text"] for option in question.get("options", [])}
    pairs = matching_pairs(question)
    if question["type"] == "matching" and len(pairs) != len(question.get("matching_terms", [])):
        raise ValueError(f"Incomplete matching key for {question['id']}: {pairs}")
    return {
        "bank": "course",
        "chapterSlug": question["module_id"],
        "chapterTitle": module_title,
        "type": question["type"],
        "options": options,
        "stem": question["stem"],
        "printedAnswer": question.get("answer_key", ""),
        "id": question["id"],
        "adjudicatedAnswer": normalized_objective_key(question),
        "qaStatus": "draft_needs_academic_review",
        "adjudicationNote": "Course-authored item; academic review is not completed.",
        "topic": module_title,
        "difficulty": "medium",
        "bloom": "understand",
        "dok": 2,
        "courses": [question["course_id"]],
        "answerNote": question.get("commentary", ""),
        "source": {
            "file": source_file,
            "line": 0,
            "bank": "course",
            "printedNumber": question.get("number", question["id"]),
        },
        "duplicateCluster": None,
        "matchingTerms": question.get("matching_terms"),
        "matchingDescriptions": question.get("matching_descriptions"),
        "matchingAnswerPairs": pairs or None,
        "expectedResponse": question.get("expected_answer"),
        "legacySourceID": question["id"],
    }


def native_exam_response_question(
    question: dict[str, Any],
    course_id: str,
    exam_id: str,
    section_title: str,
    source_file: str,
) -> dict[str, Any]:
    """Create an answer-free question record for an interactive written attempt."""

    return {
        "bank": "course",
        "chapterSlug": exam_id,
        "chapterTitle": "Final Examination",
        "type": "short_response",
        "options": {},
        "stem": question["prompt"],
        "printedAnswer": "",
        "id": f"{question['id']}.written",
        "adjudicatedAnswer": "",
        "qaStatus": "draft_needs_academic_review",
        "adjudicationNote": "Written examination response; no learner answer key or model answer is bundled.",
        "topic": section_title,
        "difficulty": "hard",
        "bloom": "evaluate",
        "dok": 4,
        "courses": [course_id],
        "answerNote": "Requires authorised human assessment; no model answer is included.",
        "source": {
            "file": source_file,
            "line": 0,
            "bank": "course",
            "printedNumber": question["code"],
        },
        "duplicateCluster": None,
        "matchingTerms": None,
        "matchingDescriptions": None,
        "matchingAnswerPairs": None,
        "expectedResponse": None,
        "legacySourceID": question["id"],
        "examCode": question["code"],
        "examSection": question["section"],
        "pointValue": question["marks"],
    }


def exam_section_title(course_id: str, code: str) -> str:
    titles = {
        "PHI111": {"A": "Precise Distinctions", "B": "Passage Analysis", "C": "Logical Reconstruction", "D": "Synoptic Essay"},
        "PHI211": {"A": "Precise Conceptual Distinctions", "B": "Primary-Passage Analysis", "C": "Methodological Reconstruction", "D": "Synoptic Essay"},
    }
    return titles[course_id][code]


def build_course(
    archive: Path,
    course_id: str,
    learning_path_id: str,
) -> tuple[dict[str, Any], dict[str, list[dict[str, Any]]], dict[str, int]]:
    course_dir = archive / "courses" / course_id
    metadata = read_json(course_dir / "course.json")
    qa_metadata = read_json(course_dir / "qa" / "validation.json")
    modules_index = read_json(course_dir / "modules.json")["modules"]
    assignments_source = read_json(course_dir / "assignments" / "assignments.json")["assignments"]
    assignment_ids_by_module: dict[int, list[str]] = {}
    assignments: list[dict[str, Any]] = []
    for item in assignments_source:
        assignment_source = read_text(course_dir / "assignments" / item["content_file"])
        assignment_ids_by_module.setdefault(item["after_module"], []).append(item["id"])
        assignments.append({
            "id": item["id"],
            "courseID": course_id,
            "contentVersion": item["version"],
            "code": item["code"],
            "title": item["title"],
            "afterModuleNumber": item["after_module"],
            "weightPercent": item["weight_percent"],
            "mode": item["mode"],
            "expectedExtent": item["expected_extent"],
            "bodyMarkdown": format_assignment_markdown(assignment_source),
            "sourceStatus": item["status"],
            "rubricCriteria": assignment_rubric(assignment_source, item["id"]),
        })

    total_hours = workload_hours(metadata["estimated_workload"])
    module_minutes = round(total_hours * 60 / len(modules_index))
    modules: list[dict[str, Any]] = []
    exercise_sets: list[dict[str, Any]] = []
    assessments: list[dict[str, Any]] = []
    questions: list[dict[str, Any]] = []
    marker_count = 0
    section_count = 0

    for indexed_module in modules_index:
        module_dir = course_dir / indexed_module["path"]
        module = read_json(module_dir / "module.json")
        exercises_source = read_json(module_dir / module["exercise_file"])["exercises"]
        quiz = read_json(module_dir / module["quiz_file"])
        sections_by_id = {section["id"]: section for section in module["sections"]}
        exercises_by_id = {exercise["id"]: exercise for exercise in exercises_source}
        blocks: list[dict[str, Any]] = []
        lesson_id = f"{module['id']}-LESSON"

        for block in module["blocks"]:
            if block["type"] == "section":
                section = sections_by_id[block["ref"]]
                body, removed = section_body(read_text(module_dir / block["file"]))
                marker_count += removed
                section_count += 1
                blocks.append({
                    "id": section["id"],
                    "kind": "lessonContent",
                    "title": f"{section['number']} {section['title']}",
                    "summary": "",
                    "requirement": "required",
                    "referencedContentID": None,
                    "bodyMarkdown": body,
                })
            elif block["type"] == "exercise":
                exercise = exercises_by_id[block["ref"]]
                set_id = f"{exercise['id']}.set"
                exercise_sets.append({
                    "id": set_id,
                    "title": exercise["title"],
                    "requirement": "recommended",
                    "exercises": [{
                        "id": exercise["id"],
                        "kind": "guidedExercise",
                        "promptMarkdown": exercise["prompt"],
                        "sourceContentIDs": [exercise["placement_after_section_id"]],
                        "rubricMarkdown": None,
                        "relatedLessonIDs": [lesson_id],
                        "title": exercise["title"],
                        "instructions": exercise.get("instructions", []),
                        "recommendedResponse": exercise.get("recommended_response"),
                        "solutionMarkdown": exercise["solution"],
                        "isGraded": exercise["graded"],
                        "sourceStatus": exercise["status"],
                    }],
                })
                blocks.append({
                    "id": f"block.{exercise['id']}",
                    "kind": "exercise",
                    "title": exercise["title"],
                    "summary": exercise["prompt"],
                    "requirement": "recommended",
                    "referencedContentID": set_id,
                    "bodyMarkdown": None,
                })
            elif block["type"] == "quiz":
                blocks.append({
                    "id": f"block.{quiz['id']}",
                    "kind": "moduleQuiz",
                    "title": quiz["title"],
                    "summary": f"{quiz['question_count']} questions · {quiz['points']} points · formative",
                    "requirement": "recommended",
                    "referencedContentID": quiz["id"],
                    "bodyMarkdown": None,
                })
            else:
                raise ValueError(f"Unknown block type in {module['id']}: {block}")

        relative_quiz_file = str((module_dir / module["quiz_file"]).relative_to(archive))
        module_questions = [native_question(item, module["title"], relative_quiz_file) for item in quiz["questions"]]
        questions.extend(module_questions)
        recommended_minimum, recommended_maximum = recommended_quiz_minutes(quiz)
        assessments.append({
            "id": quiz["id"],
            "title": quiz["title"],
            "kind": "moduleQuiz",
            "questionIDs": quiz["question_refs"],
            "requestedQuestionCount": quiz["question_count"],
            "durationSeconds": None,
            "gradeRole": "formative",
            "writtenSections": [],
            "totalPoints": quiz["points"],
            "courseID": course_id,
            "moduleID": module["id"],
            "recommendedTimeMinimumMinutes": recommended_minimum,
            "recommendedTimeMaximumMinutes": recommended_maximum,
            "sourceStatus": quiz["status"],
        })
        modules.append({
            "id": module["id"],
            "title": module["title"],
            "summary": f"{len(module['sections'])} ordered sections with {len(exercises_source)} embedded formative exercises and one module quiz.",
            "estimatedMinutes": module_minutes,
            "lessons": [{
                "id": lesson_id,
                "title": module["title"],
                "summary": f"Module {module['order']} of {len(modules_index)}",
                "estimatedMinutes": module_minutes,
                "blocks": blocks,
            }],
            "moduleQuizID": quiz["id"],
            "assignmentIDs": assignment_ids_by_module.get(module["order"], []),
            "sourceVersion": module["version"],
            "sourceStatus": module["status"],
        })

    module_question_count = len(questions)
    final_exam_json_path = course_dir / "exam" / "final-exam.json"
    final_exam_markdown_path = course_dir / "exam" / "final-exam.md"
    final_exam = read_json(final_exam_json_path)
    final_exam_source_markdown = read_text(final_exam_markdown_path)
    candidate_instructions, candidate_declaration = candidate_exam_markdown(
        final_exam_source_markdown,
        course_id,
    )
    section_instructions = exam_section_instructions(
        final_exam_source_markdown,
        course_id,
        final_exam,
    )
    relative_final_exam_file = str(final_exam_json_path.relative_to(archive))
    exam_sections = []
    for section_code in ("A", "B", "C", "D"):
        section_questions = [item for item in final_exam["questions"] if item["section"] == section_code]
        section_title = exam_section_title(course_id, section_code)
        exam_sections.append({
            "id": f"{final_exam['id']}-SECTION-{section_code}",
            "title": section_title,
            "responsePolicy": final_exam["response_policy"][section_code],
            "instructionsMarkdown": section_instructions[section_code],
            "questions": [{
                "id": item["id"],
                "code": item["code"],
                "title": item.get("title", ""),
                "promptMarkdown": item["prompt"],
                "points": item["marks"],
                "responseQuestionID": f"{item['id']}.written",
            } for item in section_questions],
        })
        questions.extend(
            native_exam_response_question(
                item,
                course_id,
                final_exam["id"],
                section_title,
                relative_final_exam_file,
            )
            for item in section_questions
        )
    written_exam_question_ids = [f"{item['id']}.written" for item in final_exam["questions"]]
    assessments.append({
        "id": final_exam["id"],
        "title": "Final Examination",
        "kind": "courseFinal",
        "questionIDs": written_exam_question_ids,
        "requestedQuestionCount": len(final_exam["questions"]),
        "durationSeconds": final_exam["duration_minutes"] * 60,
        "gradeRole": "summative",
        "writtenSections": [],
        "totalPoints": final_exam["total_marks"],
        "courseID": course_id,
        "courseWeightPercent": final_exam["course_weight_percent"],
        "permittedMaterials": final_exam["permitted_material"],
        "responsePolicy": final_exam["response_policy"],
        "examSections": exam_sections,
        "sourceMarkdown": final_exam_source_markdown,
        "candidateInstructionsMarkdown": candidate_instructions,
        "candidateDeclarationMarkdown": candidate_declaration,
        "restrictedMarkingGuideID": f"{course_id}-MARKING-GUIDE",
        "sourceStatus": final_exam["status"],
    })

    overview = read_text(course_dir / "overview.md")
    introduction = read_text(course_dir / "introduction.md")
    guide_markdown = read_text(course_dir / metadata["files"]["study_reading_guide"])
    authored_course_source_markdown = read_text(course_dir / "assets" / "course-source.md")
    course_source_markdown = native_reading_markdown(authored_course_source_markdown)
    conclusion_markdown = course_conclusion_markdown(authored_course_source_markdown, course_id)
    assignment_handbook_markdown = read_text(course_dir / "assignments" / "handbook-extracted.md")
    formative_solutions_markdown = native_formative_solutions_markdown(course_dir, course_id)
    bibliography = read_text(course_dir / "bibliography.md")
    glossary = glossary_records(course_dir, guide_markdown, course_id)
    bibliography_items = bibliography_records(bibliography, course_id)
    guide_id = f"{course_id}-STUDY-READING-GUIDE"
    reading_guide_id = f"{course_id}-READING-GUIDE-REFERENCE"
    sources = read_json(course_dir / "sources.json")
    source_metadata = {
        "canonicalEditorialSource": sources["canonical_editorial_source"],
        "designedCoursebook": sources["designed_coursebook"],
        "assignmentSource": sources["assignment_source"],
        "examSource": sources["exam_source"],
        "markingSource": sources["marking_source"],
        "primaryTextCitationsEmbeddedInCourse": sources["primary_text_citations_embedded_in_course"],
        "rightsReviewRequired": sources["rights_review_required"],
        "quotationVerificationRequired": sources["quotation_verification_required"],
        "notes": sources["notes"],
        "structuralValidationPassed": qa_metadata["structural_validation_passed"],
        "academicVerificationStatus": qa_metadata["academic_verification_status"],
        "requiredHumanReview": qa_metadata["required_human_review"],
    }
    course = {
        "id": course_id,
        "contentVersion": metadata["version"],
        "title": metadata["title"],
        "subtitle": metadata["subtitle"],
        "summary": first_course_purpose(overview),
        "type": "classicalReading" if course_id == "PHI111" else "seminar",
        "interactionIntensity": "calm" if course_id == "PHI111" else "balanced",
        "mode": "selfPaced",
        "publicationStatus": "draftNeedsReview",
        "estimatedHours": total_hours,
        "prerequisites": metadata["prerequisites"],
        "outcomes": metadata["learning_outcomes"],
        "contributors": [],
        "assessmentSummary": f"Formal assignments: {metadata['formal_assessment']['assignments_weight_percent']}%. Final examination: {metadata['formal_assessment']['final_exam_weight_percent']}%.",
        "modules": modules,
        "level": metadata["level"],
        "primarySubject": metadata["primary_subject"],
        "contentMode": metadata["content_mode"],
        "programmePosition": metadata["programme_position"],
        "estimatedWorkload": metadata["estimated_workload"],
        "deliveryDescription": metadata["delivery"],
        "introductionMarkdown": introduction,
        "overviewMarkdown": overview,
        "bibliographyMarkdown": bibliography,
        "courseSourceMarkdown": course_source_markdown,
        "conclusionMarkdown": conclusion_markdown,
        "assignmentHandbookMarkdown": assignment_handbook_markdown,
        "formativeSolutionsMarkdown": formative_solutions_markdown,
        "studyGuideID": guide_id,
        "readingGuideID": reading_guide_id,
        "assignmentIDs": [item["id"] for item in assignments],
        "finalAssessmentID": final_exam["id"],
        "learningPathIDs": [learning_path_id],
        "recommendedCourseIDs": ["PHI211"] if course_id == "PHI111" else [],
        "academicReviewStatus": metadata["academic_review_status"],
        "rightsStatus": metadata["rights_status"],
        "sourceTextStatus": metadata["source_text_status"],
        "sourceMetadata": source_metadata,
    }
    associated = {
        "studyGuides": [{
            "id": guide_id,
            "contentVersion": metadata["version"],
            "title": f"{course_id} Study and Reading Guide",
            "purpose": "Combined Study and Reading Guide supplied with the course.",
            "outcomes": metadata["learning_outcomes"],
            "essentialQuestions": [],
            "sections": split_guide(guide_markdown, course_id),
            "glossaryTermIDs": [item["id"] for item in glossary],
            "bibliographySourceIDs": [item["id"] for item in bibliography_items],
        }],
        "readingGuides": [{
            "id": reading_guide_id,
            "contentVersion": metadata["version"],
            "title": f"{course_id} Study and Reading Guide",
            "workTitle": metadata["title"],
            "author": "",
            "editionNote": "See the guide's edition and citation policy.",
            "purpose": "Course reading sequence, source hierarchy, edition policy, and module-specific reading guidance.",
            "context": "This record references the canonical combined Study and Reading Guide without duplicating it.",
            "chunks": module_reading_guide_chunks(
                guide_markdown,
                course_id,
                modules,
                module_minutes,
            ),
            "furtherReading": [],
            "canonicalStudyGuideID": guide_id,
        }],
        "exerciseSets": exercise_sets,
        "assessments": assessments,
        "questions": questions,
        "assignments": assignments,
        "glossaryTerms": glossary,
        "bibliographySources": bibliography_items,
    }
    counts = {
        "modules": len(modules),
        "sections": section_count,
        "exercises": len(exercise_sets),
        "quizzes": len(modules),
        "moduleQuestions": module_question_count,
        "writtenExamQuestions": len(written_exam_question_ids),
        "questions": len(questions),
        "assignments": len(assignments),
        "finalExamPrompts": len(final_exam["questions"]),
        "glossaryTerms": len(glossary),
        "bibliographySources": len(bibliography_items),
        "placementMarkersRemoved": marker_count,
    }
    return course, associated, counts


def copy_restricted_resources(archive: Path, ios_root: Path) -> list[dict[str, Any]]:
    restricted_dir = ios_root / "RestrictedCourseContent"
    restricted_dir.mkdir(parents=True, exist_ok=True)
    restricted: list[dict[str, Any]] = []
    for course_id in COURSE_IDS:
        course_dir = archive / "courses" / course_id
        course_restricted_dir = restricted_dir / course_id
        course_restricted_dir.mkdir(parents=True, exist_ok=True)
        source_pdf = course_dir / "exam" / "marking-guide-restricted.pdf"
        source_md = course_dir / "exam" / "marking-guide-restricted.md"
        destination_pdf = course_restricted_dir / source_pdf.name
        destination_md = course_restricted_dir / source_md.name
        shutil.copyfile(source_pdf, destination_pdf)
        shutil.copyfile(source_md, destination_md)
        pdf_record = file_record(source_pdf)
        md_record = file_record(source_md)
        restricted.append({
            "id": f"{course_id}-MARKING-GUIDE",
            "courseID": course_id,
            "title": "Restricted Final Examination Marking Guide",
            "kind": "markingGuide",
            "accessPolicy": "examinerOnly",
            "sourceFilename": str(destination_pdf.relative_to(ios_root)),
            "sourceStatus": "draft_needs_academic_review",
            "sha256": pdf_record["sha256"],
            "byteCount": pdf_record["byteCount"],
            "companionSourceFilename": str(destination_md.relative_to(ios_root)),
            "companionSHA256": md_record["sha256"],
            "companionByteCount": md_record["byteCount"],
        })
    return restricted


def validate_package(
    package: dict[str, Any],
    counts_by_course: dict[str, dict[str, int]],
    archive: Path,
) -> dict[str, Any]:
    if package.get("schemaVersion") != 3:
        raise ValueError(f"Unsupported generated schema version: {package.get('schemaVersion')}")
    module_questions = [item for item in package["questions"] if item.get("examCode") is None]
    written_exam_questions = [item for item in package["questions"] if item.get("examCode") is not None]
    counts = {
        "courses": len(package["courses"]),
        "modules": sum(len(course["modules"]) for course in package["courses"]),
        "sections": sum(item["sections"] for item in counts_by_course.values()),
        "exercises": len(package["exerciseSets"]),
        "quizzes": sum(1 for item in package["assessments"] if item["kind"] == "moduleQuiz"),
        "moduleQuestions": len(module_questions),
        "writtenExamQuestions": len(written_exam_questions),
        "questions": len(package["questions"]),
        "assignments": len(package["assignments"]),
        "finalExamPrompts": sum(
            len(section["questions"])
            for assessment in package["assessments"] if assessment["kind"] == "courseFinal"
            for section in assessment["examSections"]
        ),
        "learningPaths": len(package["learningPaths"]),
        "learnerPDFs": len(package["assets"]),
        "restrictedMarkingGuides": len(package["restrictedResources"]),
    }
    for key, expected in EXPECTED.items():
        if counts[key] != expected:
            raise ValueError(f"Count mismatch for {key}: expected {expected}, got {counts[key]}")

    question_ids = {item["id"] for item in package["questions"]}
    for assessment in package["assessments"]:
        if assessment["kind"] == "moduleQuiz":
            if assessment["questionIDs"] != [item for item in assessment["questionIDs"]]:
                raise ValueError(f"Question order changed in {assessment['id']}")
            missing = set(assessment["questionIDs"]) - question_ids
            if missing:
                raise ValueError(f"Missing questions in {assessment['id']}: {sorted(missing)}")

    courses_by_id = {item["id"]: item for item in package["courses"]}
    reading_guides_by_id = {item["id"]: item for item in package["readingGuides"]}
    final_assessments_by_course = {
        item["courseID"]: item
        for item in package["assessments"]
        if item["kind"] == "courseFinal"
    }
    questions_by_id = {item["id"]: item for item in package["questions"]}
    exact_markdown_checks = 0
    timing_checks = 0
    reading_chunk_checks = 0
    written_exam_checks = 0
    candidate_exam_markdown_checks = 0
    exam_section_instruction_checks = 0

    for course_id in COURSE_IDS:
        course_dir = archive / "courses" / course_id
        course = courses_by_id[course_id]
        exact_fields = {
            "assignmentHandbookMarkdown": course_dir / "assignments" / "handbook-extracted.md",
        }
        for field, source_path in exact_fields.items():
            if course.get(field) != read_text(source_path):
                raise ValueError(f"Exact Markdown mismatch for {course_id}.{field}")
            exact_markdown_checks += 1

        expected_course_source = native_reading_markdown(
            read_text(course_dir / "assets" / "course-source.md")
        )
        if course.get("courseSourceMarkdown") != expected_course_source:
            raise ValueError(f"Native reading Markdown mismatch for {course_id}.courseSourceMarkdown")
        if any(MARKER.match(line) for line in course["courseSourceMarkdown"].splitlines()):
            raise ValueError(f"Authoring placement marker leaked into {course_id}.courseSourceMarkdown")
        exact_markdown_checks += 1

        expected_solutions = native_formative_solutions_markdown(course_dir, course_id)
        if course.get("formativeSolutionsMarkdown") != expected_solutions:
            raise ValueError(f"Native formative solutions mismatch for {course_id}")
        if re.search(r"\[\[SOLUTIONS:[^]]+\]\]", course["formativeSolutionsMarkdown"]):
            raise ValueError(f"Solution template marker leaked into {course_id}")
        exact_markdown_checks += 1

        expected_conclusion = course_conclusion_markdown(
            read_text(course_dir / "assets" / "course-source.md"),
            course_id,
        )
        if course.get("conclusionMarkdown") != expected_conclusion:
            raise ValueError(f"Exact conclusion Markdown mismatch for {course_id}")
        if expected_conclusion is not None:
            exact_markdown_checks += 1

        final_assessment = final_assessments_by_course[course_id]
        final_exam_source = read_text(course_dir / "exam" / "final-exam.md")
        if final_assessment.get("sourceMarkdown") != final_exam_source:
            raise ValueError(f"Exact Markdown mismatch for {course_id} final examination")
        expected_instructions, expected_declaration = candidate_exam_markdown(final_exam_source, course_id)
        if (
            not final_assessment.get("candidateInstructionsMarkdown")
            or final_assessment["candidateInstructionsMarkdown"] != expected_instructions
            or not final_assessment.get("candidateDeclarationMarkdown")
            or final_assessment["candidateDeclarationMarkdown"] != expected_declaration
        ):
            raise ValueError(f"Candidate-facing examination Markdown mismatch for {course_id}")
        candidate_exam_markdown_checks += 2
        exact_markdown_checks += 1

        metadata = read_json(course_dir / "course.json")
        guide_markdown = read_text(course_dir / metadata["files"]["study_reading_guide"])
        reading_guide = reading_guides_by_id[course["readingGuideID"]]
        expected_chunks = module_reading_guide_chunks(
            guide_markdown,
            course_id,
            course["modules"],
            course["modules"][0]["estimatedMinutes"],
        )
        if reading_guide["chunks"] != expected_chunks:
            raise ValueError(f"Exact module reading-guide chunk mismatch for {course_id}")
        reading_chunk_checks += len(expected_chunks)

        modules_source = read_json(course_dir / "modules.json")["modules"]
        quizzes_by_id = {
            assessment["id"]: assessment
            for assessment in package["assessments"]
            if assessment["kind"] == "moduleQuiz" and assessment["courseID"] == course_id
        }
        for indexed_module in modules_source:
            module_dir = course_dir / indexed_module["path"]
            module = read_json(module_dir / "module.json")
            quiz = read_json(module_dir / module["quiz_file"])
            expected_minimum, expected_maximum = recommended_quiz_minutes(quiz)
            assessment = quizzes_by_id[quiz["id"]]
            if (
                assessment.get("recommendedTimeMinimumMinutes") != expected_minimum
                or assessment.get("recommendedTimeMaximumMinutes") != expected_maximum
            ):
                raise ValueError(f"Recommended quiz time mismatch for {quiz['id']}")
            timing_checks += 1

        final_exam = read_json(course_dir / "exam" / "final-exam.json")
        expected_section_instructions = exam_section_instructions(
            final_exam_source,
            course_id,
            final_exam,
        )
        native_sections_by_code = {
            section["id"].rsplit("-", 1)[-1]: section
            for section in final_assessment["examSections"]
        }
        for section_code, expected_instructions in expected_section_instructions.items():
            native_instructions = native_sections_by_code[section_code].get("instructionsMarkdown")
            if not native_instructions or native_instructions != expected_instructions:
                raise ValueError(
                    f"Examination Section {section_code} instructions mismatch for {course_id}"
                )
            if final_exam_source.find(native_instructions) < 0:
                raise ValueError(
                    f"Examination Section {section_code} instructions are not source-derived for {course_id}"
                )
            exam_section_instruction_checks += 1
        expected_response_ids = [f"{item['id']}.written" for item in final_exam["questions"]]
        if final_assessment["questionIDs"] != expected_response_ids:
            raise ValueError(f"Written examination question order mismatch for {course_id}")
        native_exam_questions = {
            item["id"]: item
            for section in final_assessment["examSections"]
            for item in section["questions"]
        }
        for item in final_exam["questions"]:
            response_id = f"{item['id']}.written"
            native_prompt = native_exam_questions[item["id"]]
            response = questions_by_id.get(response_id)
            if native_prompt.get("responseQuestionID") != response_id or response is None:
                raise ValueError(f"Missing written response link for {item['id']}")
            if (
                response["stem"] != item["prompt"]
                or response["type"] != "short_response"
                or response["examCode"] != item["code"]
                or response["examSection"] != item["section"]
                or response["pointValue"] != item["marks"]
                or response["printedAnswer"]
                or response["adjudicatedAnswer"]
                or response["answerNote"] != "Requires authorised human assessment; no model answer is included."
                or response.get("expectedResponse") is not None
            ):
                raise ValueError(f"Written examination record mismatch for {item['id']}")
            written_exam_checks += 1

        # Restricted marking guidance may be catalogued as examiner-only metadata,
        # but its Markdown text must never enter the learner package.
        restricted_text = read_text(course_dir / "exam" / "marking-guide-restricted.md")
        if restricted_text in json.dumps(package, ensure_ascii=False):
            raise ValueError(f"Restricted marking-guide text leaked into {course_id} learner JSON")

    all_ids: list[str] = [package["packageID"]]
    all_ids.extend(item["id"] for item in package["courses"])
    all_ids.extend(item["id"] for item in package["studyGuides"])
    all_ids.extend(item["id"] for item in package["readingGuides"])
    all_ids.extend(item["id"] for item in package["exerciseSets"])
    all_ids.extend(exercise["id"] for item in package["exerciseSets"] for exercise in item["exercises"])
    all_ids.extend(item["id"] for item in package["assessments"])
    all_ids.extend(item["id"] for item in package["questions"])
    all_ids.extend(item["id"] for item in package["assignments"])
    all_ids.extend(item["id"] for item in package["learningPaths"])
    all_ids.extend(item["id"] for item in package["assets"])
    all_ids.extend(item["id"] for item in package["restrictedResources"])
    all_ids.extend(item["id"] for item in package["glossaryTerms"])
    all_ids.extend(item["id"] for item in package["bibliographySources"])
    for course in package["courses"]:
        for module in course["modules"]:
            all_ids.append(module["id"])
            for lesson in module["lessons"]:
                all_ids.append(lesson["id"])
                all_ids.extend(block["id"] for block in lesson["blocks"])
    duplicates = sorted({item for item in all_ids if all_ids.count(item) > 1})
    if duplicates:
        raise ValueError(f"Duplicate canonical IDs: {duplicates[:10]}")

    marker_remainders = [
        block["id"]
        for course in package["courses"]
        for module in course["modules"]
        for lesson in module["lessons"]
        for block in lesson["blocks"]
        if block["bodyMarkdown"] and ("[[EXERCISE" in block["bodyMarkdown"] or "[[QUIZ" in block["bodyMarkdown"] or "[[MILESTONE" in block["bodyMarkdown"])
    ]
    if marker_remainders:
        raise ValueError(f"Unresolved placement markers: {marker_remainders}")

    module_question_types = {kind: sum(1 for item in module_questions if item["type"] == kind) for kind in (
        "single_choice", "multiple_choice", "matching", "short_response", "reconstruction"
    )}
    expected_types = {"single_choice": 104, "multiple_choice": 26, "matching": 26, "short_response": 26, "reconstruction": 26}
    if module_question_types != expected_types:
        raise ValueError(f"Module question type mismatch: {module_question_types}")

    question_types = {kind: sum(1 for item in package["questions"] if item["type"] == kind) for kind in (
        "single_choice", "multiple_choice", "matching", "short_response", "reconstruction"
    )}

    return {
        "schemaVersion": package["schemaVersion"],
        "counts": counts,
        "questionTypes": question_types,
        "moduleQuestionTypes": module_question_types,
        "courseCounts": counts_by_course,
        "nativeContentValidation": {
            "exactMarkdownFields": exact_markdown_checks,
            "moduleReadingGuideChunks": reading_chunk_checks,
            "quizTimingRanges": timing_checks,
            "writtenExamQuestions": written_exam_checks,
            "candidateExamMarkdownFields": candidate_exam_markdown_checks,
            "examSectionInstructions": exam_section_instruction_checks,
            "restrictedMarkingGuideTextIncluded": False,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--ios-root", type=Path, required=True)
    args = parser.parse_args()
    archive = args.archive.resolve()
    ios_root = args.ios_root.resolve()
    if not (archive / "content-manifest.json").is_file():
        raise SystemExit(f"Not a course archive: {archive}")

    learning_source = read_json(archive / "learning-paths" / "dialectics-from-hegel-to-marx.json")
    learning_path = {
        "id": learning_source["id"],
        "contentVersion": learning_source["version"],
        "title": learning_source["title"],
        "language": learning_source["language"],
        "sourceStatus": learning_source["status"],
        "courses": [{
            "courseID": item["course_id"],
            "order": item["order"],
            "isRequired": item["required"],
        } for item in learning_source["courses"]],
        "recommendedNext": [{
            "courseID": item["course_id"],
            "title": item["title"],
            "status": item["status"],
        } for item in learning_source["recommended_next"]],
    }

    package: dict[str, Any] = {
        "schemaVersion": 3,
        "packageID": "Marxist_Info_App_Content_Pack",
        "contentVersion": "1.0.0",
        "locale": "en",
        "minimumAppVersion": "1.0",
        "courses": [],
        "studyGuides": [],
        "readingGuides": [],
        "primaryReadings": [],
        "readingLists": [],
        "videos": [],
        "exerciseSets": [],
        "assessments": [],
        "glossaryTerms": [],
        "bibliographySources": [],
        "questions": [],
        "assignments": [],
        "learningPaths": [learning_path],
        "assets": [],
        "restrictedResources": [],
    }
    counts_by_course: dict[str, dict[str, int]] = {}
    for course_id in COURSE_IDS:
        course, associated, counts = build_course(archive, course_id, learning_path["id"])
        package["courses"].append(course)
        counts_by_course[course_id] = counts
        for key, values in associated.items():
            package[key].extend(values)

    package["restrictedResources"] = copy_restricted_resources(archive, ios_root)
    validation = validate_package(package, counts_by_course, archive)
    validation["sourceManifestAudit"] = audit_source_manifest(archive)

    output = ios_root / "Resources" / "Marxist_Info_Dialectics_v1.study-course.json"
    output.write_text(json.dumps(package, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    validation["generatedPackage"] = {
        "path": str(output.relative_to(ios_root)),
        "sha256": sha256(output),
        "byteCount": output.stat().st_size,
    }
    validation["sourcePackage"] = {
        "path": str(archive),
        "packageID": read_json(archive / "content-manifest.json").get("package_id"),
        "version": read_json(archive / "content-manifest.json").get("version"),
    }
    report = ios_root / "Tools" / "dialectics-import-report.json"
    report.write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(validation, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
