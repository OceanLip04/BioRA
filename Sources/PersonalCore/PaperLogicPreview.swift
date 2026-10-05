import Foundation

extension Workspace {
    /// Only used by the explicitly read-only preview entry point. No paper or
    /// database is read, and this fictional fixture is never installed in a workspace.
    public static func paperLogicPreview() -> Workspace {
        var workspace = Workspace.demo()
        workspace.language = .english
        var graph = ScientificQuestion(title: "Fictional study · signal and interpretation", detail: "Fictional UI fixture, not scientific evidence.")
        for tree in 0..<2 {
            let root = ScienceClaim(kind: .conclusion, text: tree == 0 ? "A scoped signal difference is reproducible" : "A competing imaging explanation remains plausible", sourceNote: "Fictional preview")
            graph.claims.append(root)
            graph.mainline.append(ScienceMainlineStep(claimID: root.id, question: tree == 0 ? "Is a difference present?" : "Could imaging explain the difference?",
                motivation: tree == 0 ? "Establish the measured effect before interpreting it." : "A signal difference alone does not establish its cause.", origin: .inferred))
            var parent = root.id
            let descriptions = tree == 0 ? ["Independent readouts converge on the scoped phenotype", "Matched controls constrain a preparation artifact", "The treated and control groups differ locally"]
                : ["The alternative has not been fully excluded", "Exposure matching reduces one confounding route", "A matched-exposure comparison changes the readout"]
            for description in descriptions {
                let child = ScienceClaim(kind: .conclusion, text: description, sourceNote: "Fictional preview")
                graph.claims.append(child)
                graph.relations.append(ScienceRelation(fromClaimID: child.id, toClaimID: parent, kind: .supports,
                    explanation: "Fictional example of a distinct comparison-to-interpretation step.", limitations: "No real experiment or publication is represented."))
                parent = child.id
            }
            let atom = AtomicExperiment(title: tree == 0 ? "Fictional matched-sample assay" : "Fictional exposure-control assay", method: "Fictional comparison", status: .recorded,
                observedResult: "Fictional observation for UI testing only", sourceNote: "Fictional preview")
            graph.atomicExperiments.append(atom)
            graph.evidenceLinks.append(AtomicEvidenceLink(atomicExperimentID: atom.id, claimID: parent, kind: .supports,
                explanation: "The fictional comparison informs only this local finding.", limitations: "No scientific evidence."))
        }
        let discussion = ScienceClaim(kind: .conclusion, text: "DISCUSSION · integrate the signal, alternatives, and unresolved mechanism", sourceNote: "Fictional preview")
        graph.claims.append(discussion)
        for step in graph.mainline {
            graph.relations.append(ScienceRelation(fromClaimID: step.claimID, toClaimID: discussion.id, kind: .supports,
                explanation: "The scoped finding informs the integrated interpretation; it is not proof of a mechanism.", limitations: "Further controls are needed."))
        }
        graph.mainline.append(ScienceMainlineStep(claimID: discussion.id, question: "What do these findings mean together?",
            motivation: "Integrate the results and retain their uncertainties.", origin: .inferred, role: .discussion))
        var analysis = PaperAnalysis(paper_title: graph.title, authors: [], year: "", doi: "", study_type: .experimental,
            central_question: "How should a measured signal difference be interpreted?", background_and_gap: "Fictional material for interface testing only.",
            summary: "Fictional comparisons illustrate observations, controls, interpretations, and Discussion.",
            methods: [.init(key: "m1", title: "Fictional comparison", system: "Fictional samples", design: "Matched groups", intervention: "Fictional treatment", controls: "Matched exposure", measurements: "Signal", sample_size: "", statistics: "", source_pages: [1], figure_refs: ["Fig. 1a", "Fig. 1b"])],
            findings: [.init(key: "f1", statement: "Fictional signal difference", quantitative_result: "", uncertainty: "No real data", interpretation: "A bounded illustration, not evidence", method_keys: ["m1"], source_pages: [1], figure_refs: ["Fig. 1a", "Fig. 1b"])],
            conclusions: [], limitations: [.init(text: "Every item in this preview is fictional.", origin: .reported, source_pages: [2])], open_questions: [])
        analysis.discussion = .init(summary: discussion.text, origin: .inferred, source_pages: [2])
        analysis.figure_panels = [
            ("p1a", "Fig. 1", "a", "Matched comparison"), ("p1b", "Fig. 1", "b", "Exposure control"),
            ("p2a", "Fig. 2", "a", "Independent readout"), ("p2b", "Fig. 2", "b", "Extended conditions")
        ].map { key, figure, label, title in
            .init(key: key, figure_ref: figure, panel_label: label, title: title,
                question: "What does this fictional comparison establish?", observed_result: "Fictional signal difference", interpretation: "Only a local comparison is illustrated",
                limitations: "Not real data; no causal inference", method_keys: ["m1"], finding_keys: ["f1"], source_pages: [1])
        }
        analysis.panel_links = [
            .init(from_panel: "p1a", to_panel: "p1b", kind: .motivates, explanation: "The signal difference prompts an exposure-matching control.", limitations: "Reconstructed research rationale", origin: .inferred, source_pages: [1]),
            .init(from_panel: "p1b", to_panel: "p1a", kind: .controlsFor, explanation: "The exposure control tests an imaging-based alternative to the first interpretation.", limitations: "Other alternatives remain", origin: .inferred, source_pages: [1]),
            .init(from_panel: "p1a", to_panel: "p2a", kind: .supports, explanation: "Independent readouts provide converging, bounded support.", limitations: "No causal mechanism established", origin: .inferred, source_pages: [1]),
            .init(from_panel: "p2a", to_panel: "p2b", kind: .extends, explanation: "Additional conditions examine whether the pattern extends beyond the first comparison.", limitations: "Scope remains limited", origin: .inferred, source_pages: [1])
        ]
        workspace.literatureReadings = [LiteratureReading(fileName: "Fictional preview — not a publication.pdf", fingerprint: "000000000000", pageCount: 2, graph: graph, analysis: analysis)]
        return workspace
    }
}
