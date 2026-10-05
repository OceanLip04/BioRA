# Protocol document model

BioRA keeps a Protocol as a structured, versioned document rather than a flat checklist. Its procedural hierarchy remains `block → subblock → atomic step`.

## Document sections

| Section | Data | Purpose |
| --- | --- | --- |
| Objective | `objective` | The experiment's goal |
| Materials | `materials` | Samples, reagents, consumables, equipment, and other preparation items |
| Procedure | `blocks` | Ordered, nested operations; each actionable step may carry duration and resource metadata |
| Principles | `principles` | Short explanations of the method's rationale |
| Precautions | `precautions` | Safety and handling notes |

Material preparation checkmarks are personal workspace state, separate from the Protocol document and its version history. A material is not a procedural step. Actions such as weighing, mixing, loading, or preparing a reagent belong in the procedure when they are real operations.

## Assistant generation and review

The assistant routes a request to a dedicated Protocol workflow, then constructs the structured document. It must not convert section headings, explanatory prose, or a materials list into experimental steps. Unknown quantities or durations should remain explicitly unconfirmed rather than being invented. Generated Protocols are drafts for researcher review; they are not validated experimental instructions.

The app decodes and validates generated data before offering it for review. Validation can catch structural and some obvious semantic errors, but cannot establish scientific correctness or identify every language-level misclassification. Researchers must verify the content, especially reagent amounts, conditions, and safety requirements.

## Timing and compatibility

Each procedural step can hold an estimated duration. After an experiment, researchers can record sample count and actual step durations. Scheduling can use the accumulated observations according to the calibration settings for that step, alongside ordering, instrument availability, and personal availability constraints. A duration of zero or an unconfirmed estimate is not a reliable scheduling estimate.

Existing Protocol hierarchy and versions are preserved when documents are edited. Material checkmarks do not change step counts, timing estimates, or previous versions. Protocol preparation state is not inventory management or a record that an experiment has been completed.
