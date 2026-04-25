import re
import tiktoken

CHUNK_SIZE_TOKENS = 600
OVERLAP_TOKENS = 100

_enc = tiktoken.get_encoding("cl100k_base")  # Close to Gemini tokenization


def count_tokens(text: str) -> int:
    return len(_enc.encode(text))


def chunk_text(text: str, document_name: str = "") -> list[dict]:
    """
    Splits text into overlapping chunks of ~600 tokens.
    Respects sentence boundaries — never cuts mid-sentence.
    Returns list of {content, chunk_index, token_count, metadata}.
    """
    sentences = _split_sentences(text)
    chunks = []
    current_chunk_sentences = []
    current_tokens = 0
    chunk_index = 0

    for sentence in sentences:
        sentence_tokens = count_tokens(sentence)

        if current_tokens + sentence_tokens > CHUNK_SIZE_TOKENS and current_chunk_sentences:
            chunk_text_str = " ".join(current_chunk_sentences)
            chunks.append({
                "content": chunk_text_str,
                "chunk_index": chunk_index,
                "token_count": current_tokens,
                "metadata": {"document_name": document_name},
            })
            chunk_index += 1

            # Overlap: keep tail sentences that fit within OVERLAP_TOKENS
            overlap_sentences = []
            overlap_tokens = 0
            for s in reversed(current_chunk_sentences):
                s_tokens = count_tokens(s)
                if overlap_tokens + s_tokens <= OVERLAP_TOKENS:
                    overlap_sentences.insert(0, s)
                    overlap_tokens += s_tokens
                else:
                    break
            current_chunk_sentences = overlap_sentences
            current_tokens = overlap_tokens

        current_chunk_sentences.append(sentence)
        current_tokens += sentence_tokens

    # Flush remaining sentences
    if current_chunk_sentences:
        chunk_text_str = " ".join(current_chunk_sentences)
        chunks.append({
            "content": chunk_text_str,
            "chunk_index": chunk_index,
            "token_count": current_tokens,
            "metadata": {"document_name": document_name},
        })

    return chunks


def _split_sentences(text: str) -> list[str]:
    """Simple sentence splitter that handles academic text."""
    text = re.sub(r'\s+', ' ', text).strip()
    sentences = re.split(r'(?<=[.!?])\s+(?=[A-Z])', text)
    return [s.strip() for s in sentences if s.strip() and len(s.strip()) > 10]
