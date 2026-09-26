import Foundation

/// Prompts for each AI feature, with the output rules from SPEC › AI features and rules.
enum Prompts {
    struct WorkContext: Sendable {
        var title: String
        var author: String
        var chapter: String
    }

    static func explain(_ mode: ExplainMode, selection: String, paragraph: String, work: WorkContext) -> AIRequest {
        let task: String
        switch mode {
        case .explain: task = "Explain what the selected words mean in this passage and why they matter here."
        case .define: task = "Define the selected word or phrase as it is used in this passage."
        case .context: task = "Give the context a reader needs for the selection. State dates or facts only if they appear in the passage or in the title and author given; otherwise leave them out."
        case .simpler: task = "Say what the selection means in plainer, simpler words."
        }
        let system = """
        You help someone reading a book. \(task) Answer in 60 words or fewer, as plain prose: no lists, headings, quotation of the question, or markdown. Speak directly to the reader.
        """
        let prompt = """
        Book: \(work.title)\(work.author.isEmpty ? "" : " by \(work.author)")\(work.chapter.isEmpty ? "" : ", chapter “\(work.chapter)”")
        Surrounding paragraph: \(paragraph)
        Selection: \(selection)
        """
        return AIRequest(system: system, prompt: prompt, maxTokens: 4000)
    }

    static func ask(_ question: String, passage: String, work: WorkContext) -> AIRequest {
        let system = """
        Answer the reader's question using only the passage below. If the passage doesn't contain the answer, say so plainly in one sentence. 80 words or fewer, plain prose, no markdown.
        """
        let prompt = """
        Book: \(work.title)\(work.author.isEmpty ? "" : " by \(work.author)")
        Passage:
        \(passage)

        Question: \(question)
        """
        return AIRequest(system: system, prompt: prompt, maxTokens: 4000)
    }

    static func recap(previousPart: String, work: WorkContext) -> AIRequest {
        let system = """
        Summarise the passage in one sentence of 140 characters or fewer, in the past tense, for a reader about to continue the book. Mention nothing that isn't in the passage. Output only the sentence.
        """
        return AIRequest(system: system, prompt: "Book: \(work.title)\n\nPassage:\n\(previousPart)", maxTokens: 2000)
    }

    static func reflection(part: String, work: WorkContext) -> AIRequest {
        let system = """
        Write one open question, 30 words or fewer, that invites the reader to connect the passage to their own day. Tie it to a concrete image or phrase from the text. Output only the question.
        """
        return AIRequest(system: system, prompt: "Book: \(work.title)\n\nPassage:\n\(part)", maxTokens: 2000)
    }

    static func briefAngle(topic: String, pastAngles: [String], deeper: String?) -> AIRequest {
        let system = """
        You plan a short daily article on a topic the reader chose. Pick one specific, concrete angle that hasn't been covered, and a Wikipedia search query likely to find articles about it. Reply with JSON only: {"angle": "...", "query": "..."}
        """
        var prompt = "Topic, in the reader's words: \(topic)\n"
        if !pastAngles.isEmpty { prompt += "Angles already covered (avoid these): \(pastAngles.joined(separator: "; "))\n" }
        if let deeper { prompt += "The reader asked to go deeper on: \(deeper). Choose an angle that follows on from it.\n" }
        return AIRequest(system: system, prompt: prompt, maxTokens: 2000)
    }

    static func briefWrite(topic: String, angle: String, sources: [RetrievedSource], limit: Int, feedback: String?) -> AIRequest {
        let system = """
        You write "The Brief": a short, calm article for a reading app. Use ONLY facts stated in the numbered sources below — nothing from memory. If the sources don't support a claim, leave it out.
        Write a title (under 60 characters), a one-sentence standfirst, and a body of 3–6 short paragraphs separated by blank lines. Title, standfirst and body together must be \(limit) characters or fewer. Plain prose; use *asterisks* only for the occasional italic term. No headings, lists or links.
        Reply with JSON only: {"title": "...", "standfirst": "...", "body": "...", "sources": [numbers of the sources you actually used]}
        """
        var prompt = "Topic: \(topic)\nAngle: \(angle)\n\n"
        for (i, s) in sources.enumerated() {
            prompt += "Source \(i + 1): \(s.title) (\(s.url))\n\(s.text)\n\n"
        }
        if let feedback { prompt += "Your previous attempt was rejected: \(feedback) Fix it.\n" }
        return AIRequest(system: system, prompt: prompt, maxTokens: 16000)
    }

    static func notebook(question: String, notes: [String]) -> AIRequest {
        let system = """
        Answer the reader's question using only their notebook entries below. Cite the entries you used by number in square brackets, like [2]. If the notes don't answer it, say so. 120 words or fewer, plain prose.
        """
        let list = notes.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
        return AIRequest(system: system, prompt: "Notebook:\n\(list)\n\nQuestion: \(question)", maxTokens: 4000)
    }

    /// The first {...} object in a model reply.
    static func jsonObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
    }

    /// Enforces the recap's 140-character rule.
    static func clampRecap(_ text: String) -> String {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        guard s.count > 140 else { return s }
        let cut = s.prefix(139)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }
}
