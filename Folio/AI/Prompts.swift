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

    static func storyAngle(past: [String]) -> AIRequest {
        let system = """
        You plan a short, true, motivating story for a daily reading app: a real person or moment of courage, persistence, invention or kindness. Range across eras, countries and fields, and don't only pick the famous. Choose one that hasn't been covered, and a Wikipedia search query likely to find its main article. Reply with JSON only: {"angle": "who or what, and what they faced, in one line", "query": "..."}
        """
        var prompt = "Pick today's story.\n"
        if !past.isEmpty { prompt += "Already covered (avoid these): \(past.suffix(40).joined(separator: "; "))\n" }
        return AIRequest(system: system, prompt: prompt, maxTokens: 2000)
    }

    static func quotePerson(past: [String]) -> AIRequest {
        let system = """
        Choose a person whose English Wikiquote page is likely to hold a memorable, uplifting or thought-provoking quote: a writer, scientist, leader, artist, athlete or thinker. Vary eras, countries and fields. Reply with JSON only: {"person": "their name, as titled on Wikiquote"}
        """
        var prompt = "Pick today's person.\n"
        if !past.isEmpty { prompt += "Quotes and people already covered (avoid these): \(past.suffix(40).joined(separator: "; "))\n" }
        return AIRequest(system: system, prompt: prompt, maxTokens: 2000)
    }

    static func briefWrite(_ r: BriefRequest, angle: String, sources: [RetrievedSource], limit: Int, feedback: String?) -> AIRequest {
        let grounding = "Use ONLY facts stated in the numbered sources below — nothing from memory. If the sources don't support a claim, leave it out."
        let task: String
        var fields = #""title": "...", "standfirst": "...", "body": "...", "sources": [numbers of the sources you actually used]"#
        switch r.kind {
        case .topic:
            task = "You write \"The Brief\": a short, calm article for a reading app. \(grounding)"
        case .story:
            task = """
            You write \"The Brief\": a short, true, motivating story for a reading app, about the person or moment below: what they faced, what they did, and what came of it. Tell it as a story, warm but without clichés or sermonising, and end on what a reader might take from it. \(grounding)
            """
        case .quote where r.quote.isEmpty:
            task = """
            You write \"The Brief\": a short piece explaining one quote. Choose one memorable quote that appears word for word in the Wikiquote source. Say who said it and in what context, using only facts from the sources. Then explain what it means and how it might apply to an ordinary day; this interpretation may be your own. The standfirst is the quote itself in curly quotes, then — and the speaker.
            """
            fields = #""quote": "the exact words, copied from the source", "# + fields
        case .quote:
            task = """
            You write \"The Brief\": a short piece explaining a quote the reader loves. Say who said it and in what context, using only facts from the numbered sources, nothing from memory; if the sources don't say where it comes from, say so plainly rather than guess. Then explain what it means and how it might apply to an ordinary day; this interpretation may be your own. The standfirst is the quote itself in curly quotes, then — and the speaker if the sources name one.
            """
        case .news:
            task = """
            You write \"The Brief\": a calm digest of the most significant technology news for a reading app. From the numbered news items below, pick the 3–4 that matter most and give each its own short paragraph: what happened and why it matters, naming the publication. Skip deals, rumours and product promotions unless they matter. \(grounding) The title sums up the day; the standfirst says what the digest covers.
            """
        }
        let system = """
        \(task)
        Write a title (under 60 characters), a one-sentence standfirst, and a body of 3–6 short paragraphs separated by blank lines. Title, standfirst and body together must be \(limit) characters or fewer. Plain prose; use *asterisks* only for the occasional italic term. No headings, lists or links.
        Reply with JSON only: {\(fields)}
        """
        var prompt: String
        switch r.kind {
        case .topic: prompt = "Topic: \(r.topic)\nAngle: \(angle)\n\n"
        case .story: prompt = "Story: \(angle)\n\n"
        case .quote where r.quote.isEmpty: prompt = "Person: \(angle)\n\n"
        case .quote: prompt = "Quote: \(r.quote)\n" + (r.author.isEmpty ? "" : "The reader says it's by: \(r.author)\n") + "\n"
        case .news: prompt = "Date: \(r.date.formatted(date: .complete, time: .omitted))\n\n"
        }
        for (i, s) in sources.enumerated() {
            prompt += "Source \(i + 1): \(s.title) — \(s.publisher) (\(s.url))\n\(s.text)\n\n"
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
