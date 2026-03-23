"""
Semantic Search for CashOut Project Memory

This module provides semantic search across all ingested documents and decisions.

Usage:
    # Search documents
    python -m tools.memory.query docs "CloudKit sync"

    # Search decisions
    python -m tools.memory.query decisions "state management"

    # Search issues/bugs
    python -m tools.memory.query issues "crash on launch"

    # Search everything
    python -m tools.memory.query all "expense entry flow"

    # Adjust result count
    python -m tools.memory.query docs "auth" --limit 10

    # Show more context
    python -m tools.memory.query docs "database schema" --context
"""

import pixeltable as pxt
import sys
import argparse
from typing import Optional

NAMESPACE = "cashout"

INDEX_NAMES = {
    "text": "text_idx",
    "symptoms": "symptoms_idx",
    "root_cause": "root_cause_idx",
    "decision": "decision_idx",
    "rationale": "rationale_idx",
}


def _get_similarity(column, query: str, column_name: str):
    """Get similarity expression, handling multiple embedding indices."""
    idx_name = INDEX_NAMES.get(column_name)
    if idx_name:
        try:
            return column.similarity(string=query, idx=idx_name)
        except Exception:
            pass

    return column.similarity(string=query)


def search_documents(query: str, limit: int = 5, show_context: bool = False) -> list:
    """Semantic search across document chunks."""
    try:
        doc_chunks = pxt.get_table(f"{NAMESPACE}.doc_chunks")
    except Exception as e:
        print(f"[!] Error: {e}")
        print("Run 'python -m tools.memory.schema init' and ingest documents first.")
        return []

    sim = _get_similarity(doc_chunks.text, query, "text")

    if show_context:
        results = (
            doc_chunks
            .order_by(sim, asc=False)
            .select(
                doc_chunks.text,
                doc_chunks.filename,
                similarity=sim
            )
            .limit(limit)
            .collect()
        )
    else:
        results = (
            doc_chunks
            .order_by(sim, asc=False)
            .select(
                text_preview=doc_chunks.text.slice(0, 200),
                filename=doc_chunks.filename,
                similarity=sim
            )
            .limit(limit)
            .collect()
        )

    return results


def search_decisions(query: str, limit: int = 5) -> list:
    """Semantic search across architectural decisions."""
    try:
        decisions = pxt.get_table(f"{NAMESPACE}.decisions")
    except Exception:
        return []

    if decisions.count() == 0:
        return []

    sim = _get_similarity(decisions.decision, query, "decision")

    results = (
        decisions
        .order_by(sim, asc=False)
        .select(
            decisions.title,
            decisions.decision,
            decisions.rationale,
            decisions.date,
            decisions.category,
            similarity=sim
        )
        .limit(limit)
        .collect()
    )

    return results


def search_issues(query: str, limit: int = 5) -> list:
    """Semantic search across issues/bugs/RCAs."""
    try:
        issues = pxt.get_table(f"{NAMESPACE}.issues")
    except Exception:
        return []

    if issues.count() == 0:
        return []

    sim = _get_similarity(issues.symptoms, query, "symptoms")

    results = (
        issues
        .order_by(sim, asc=False)
        .select(
            issues.title,
            issues.symptoms,
            issues.root_cause,
            issues.fix,
            issues.date,
            similarity=sim
        )
        .limit(limit)
        .collect()
    )

    return results


def format_doc_results(results: list, show_context: bool = False):
    """Format and print document search results."""
    if not results:
        print("  No matching documents found.")
        return

    for i, row in enumerate(results, 1):
        score = row.get('similarity', 0)
        filename = row.get('filename', 'unknown')

        print(f"\n{i}. [{score:.3f}] {filename}")
        print("-" * 50)

        if show_context:
            text = row.get('text', '')
        else:
            text = row.get('text_preview', '')

        text = text.strip().replace('\n\n', '\n')
        if len(text) > 500 and not show_context:
            text = text[:500] + "..."

        print(text)


def format_decision_results(results: list):
    """Format and print decision search results."""
    if not results:
        print("  No matching decisions found.")
        return

    for i, row in enumerate(results, 1):
        score = row.get('similarity', 0)
        title = row.get('title', 'Untitled')
        date = row.get('date', '')
        category = row.get('category', '')

        print(f"\n{i}. [{score:.3f}] {title} ({date}) [{category}]")
        print("-" * 50)
        print(f"Decision: {row.get('decision', '')}")
        print(f"Rationale: {row.get('rationale', '')}")


def format_issue_results(results: list):
    """Format and print issue search results."""
    if not results:
        print("  No matching issues found.")
        return

    for i, row in enumerate(results, 1):
        score = row.get('similarity', 0)
        title = row.get('title', 'Untitled')
        date = row.get('date', '')

        print(f"\n{i}. [{score:.3f}] {title} ({date})")
        print("-" * 50)
        print(f"Symptoms: {row.get('symptoms', '')}")
        print(f"Root Cause: {row.get('root_cause', '')}")
        print(f"Fix: {row.get('fix', '')}")


def search_all(query: str, limit: int = 3):
    """Search across all data sources."""
    print(f"\n{'='*60}")
    print(f"Searching: \"{query}\"")
    print(f"{'='*60}")

    print(f"\n## Documents")
    doc_results = search_documents(query, limit)
    format_doc_results(doc_results)

    print(f"\n## Decisions")
    decision_results = search_decisions(query, limit)
    format_decision_results(decision_results)

    print(f"\n## Issues/Bugs")
    issue_results = search_issues(query, limit)
    format_issue_results(issue_results)


def main():
    parser = argparse.ArgumentParser(description="Search CashOut project memory")
    parser.add_argument("source", choices=["docs", "decisions", "issues", "all"],
                        help="What to search")
    parser.add_argument("query", help="Search query")
    parser.add_argument("--limit", "-n", type=int, default=5,
                        help="Number of results (default: 5)")
    parser.add_argument("--context", "-c", action="store_true",
                        help="Show full context for documents")

    args = parser.parse_args()

    if args.source == "docs":
        print(f"\nSearching documents for: \"{args.query}\"")
        print("=" * 60)
        results = search_documents(args.query, args.limit, args.context)
        format_doc_results(results, args.context)

    elif args.source == "decisions":
        print(f"\nSearching decisions for: \"{args.query}\"")
        print("=" * 60)
        results = search_decisions(args.query, args.limit)
        format_decision_results(results)

    elif args.source == "issues":
        print(f"\nSearching issues for: \"{args.query}\"")
        print("=" * 60)
        results = search_issues(args.query, args.limit)
        format_issue_results(results)

    elif args.source == "all":
        search_all(args.query, args.limit)

    print()


if __name__ == "__main__":
    main()
