ACADEMIC_SYSTEM_PROMPT = """You are PrepMind AI — a specialized academic assistant designed exclusively for exam preparation.

YOUR ROLE:
- Help students understand, summarize, and practice their course material
- Generate exam-focused, structured outputs
- Always base responses on the provided academic context
- Be concise, accurate, and exam-ready in your outputs

RESPONSE RULES:
- Always respond in valid JSON matching the schema requested
- Never add conversational filler or preamble before the JSON
- If context is insufficient, say so in the JSON's "note" field
- Prioritize exam-relevant information over background knowledge
- Use simple, clear academic language suitable for university students"""


GENERATION_PROMPTS = {

    "summary": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Based on the following academic content from the subject "{subject_name}", generate a comprehensive bullet-point summary.

ACADEMIC CONTENT:
{context}

Return ONLY this JSON:
{{
  "type": "summary",
  "subject": "{subject_name}",
  "sections": [
    {{
      "title": "Section Title",
      "points": ["Point 1", "Point 2", "Point 3"]
    }}
  ],
  "total_points": 0,
  "note": "<optional: any limitation or missing context>"
}}"""
    },

    "key_points": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """From the following academic content for "{subject_name}", extract the most important exam-relevant key points.

ACADEMIC CONTENT:
{context}

Return ONLY this JSON:
{{
  "type": "key_points",
  "subject": "{subject_name}",
  "points": [
    {{
      "point": "Key point text",
      "importance": "high|medium|low",
      "topic": "Related topic name"
    }}
  ],
  "note": "<optional>"
}}"""
    },

    "mcq": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Generate {count} multiple choice questions (MCQs) for exam practice based on "{subject_name}".

ACADEMIC CONTENT:
{context}

Rules:
- Each question must be directly answerable from the content
- One clearly correct answer, three plausible distractors
- Include brief explanation for the correct answer
- Difficulty: mix of easy (30%), medium (50%), hard (20%)

Return ONLY this JSON:
{{
  "type": "mcq",
  "subject": "{subject_name}",
  "questions": [
    {{
      "id": 1,
      "question": "Question text?",
      "options": {{
        "A": "Option A",
        "B": "Option B",
        "C": "Option C",
        "D": "Option D"
      }},
      "correct": "A",
      "explanation": "Brief explanation of why A is correct",
      "difficulty": "easy|medium|hard",
      "topic": "Related topic"
    }}
  ],
  "note": "<optional>"
}}"""
    },

    "flashcards": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Create {count} flashcards for studying "{subject_name}". Focus on definitions, formulas, concepts, and key facts.

ACADEMIC CONTENT:
{context}

Return ONLY this JSON:
{{
  "type": "flashcards",
  "subject": "{subject_name}",
  "cards": [
    {{
      "id": 1,
      "front": "Term or question",
      "back": "Definition or answer",
      "topic": "Related topic",
      "hint": "<optional hint>"
    }}
  ],
  "note": "<optional>"
}}"""
    },

    "five_mark_qa": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Generate {count} five-mark exam questions with model answers for "{subject_name}".

ACADEMIC CONTENT:
{context}

A 5-mark answer should be 150-200 words with 3-5 clear points.

Return ONLY this JSON:
{{
  "type": "five_mark_qa",
  "subject": "{subject_name}",
  "questions": [
    {{
      "id": 1,
      "question": "Question text",
      "answer": "Model answer 150-200 words",
      "key_points": ["Point 1", "Point 2", "Point 3"],
      "topic": "Related topic"
    }}
  ],
  "note": "<optional>"
}}"""
    },

    "ten_mark_qa": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Generate {count} ten-mark exam questions with detailed model answers for "{subject_name}".

ACADEMIC CONTENT:
{context}

A 10-mark answer should be 300-400 words with introduction, main points, and conclusion.

Return ONLY this JSON:
{{
  "type": "ten_mark_qa",
  "subject": "{subject_name}",
  "questions": [
    {{
      "id": 1,
      "question": "Question text",
      "answer": "Detailed model answer 300-400 words",
      "key_points": ["Point 1", "Point 2", "Point 3", "Point 4", "Point 5"],
      "topic": "Related topic"
    }}
  ],
  "note": "<optional>"
}}"""
    },

    "revision_sheet": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Create a comprehensive revision sheet for "{subject_name}" covering all uploaded material.

ACADEMIC CONTENT:
{context}

Return ONLY this JSON:
{{
  "type": "revision_sheet",
  "subject": "{subject_name}",
  "sections": [
    {{
      "title": "Section Title",
      "content_type": "definitions|formulas|concepts|examples",
      "items": [
        {{"term": "Term", "definition": "Definition"}}
      ]
    }}
  ],
  "quick_reference": ["One-liner 1", "One-liner 2"],
  "note": "<optional>"
}}"""
    },

    "mind_map": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Create a mind map structure for "{subject_name}" that shows how topics are connected.

ACADEMIC CONTENT:
{context}

Return ONLY this JSON:
{{
  "type": "mind_map",
  "subject": "{subject_name}",
  "central_topic": "{subject_name}",
  "branches": [
    {{
      "topic": "Main Branch Topic",
      "color": "#hexcolor",
      "subtopics": [
        {{
          "title": "Subtopic",
          "details": ["Detail 1", "Detail 2"]
        }}
      ]
    }}
  ],
  "note": "<optional>"
}}"""
    },
}


CHAT_SYSTEM_PROMPT = """You are PrepMind AI, an academic study assistant for the subject "{subject_name}".

You help students understand their uploaded course material. You have access to relevant excerpts from their documents.

RULES:
- Answer only based on the provided context excerpts
- If something is not in the context, say: "I don't have information about that in your uploaded documents"
- Keep answers concise and exam-focused
- You can explain concepts, answer questions, and help students understand material
- Never make up facts not present in the context
- Format responses in clean, readable text (not JSON)
- Use bullet points and numbered lists where helpful"""
