# Dialectics source-package provenance exceptions

The importer verified 379 of 385 files declared by the supplied
`content-manifest.json`. No declared file had a hash or size mismatch. Six
declared integration/schema files were absent from the delivered archive:

1. `INTEGRATION_GUIDE.md`
2. `README.md`
3. `schemas/StudyContentModels.swift`
4. `schemas/course.schema.json`
5. `schemas/module.schema.json`
6. `schemas/quiz.schema.json`

These are documentation or application-schema artifacts, not academic lesson,
guide, exercise, quiz, assignment, exam, bibliography, or glossary content.
Their absence is therefore recorded as a provenance exception rather than
silently ignored. The importer did not synthesize them or use them as the app's
architecture.

Five undeclared filesystem artifacts were also observed: `.DS_Store`,
`CONTENT_INDEX.md`, `VALIDATION_REPORT.json`, `content-manifest.json`, and
`courses/.DS_Store`. They do not replace any declared academic record.

Canonical verification evidence lives in `Tools/dialectics-import-report.json`.
Re-running `Tools/import_dialectics_courses.py` against the same source package
must reproduce the learner package and report or make any difference explicit.
