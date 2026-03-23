"""
CashOut Memory MCP Server

A FastMCP server that provides semantic search over CashOut project documentation,
architectural decisions, and bug fixes. Integrates with Claude Code via MCP.

Usage:
    # Run directly (for testing)
    python tools/memory/mcp_server.py

    # Add to Claude Code
    claude mcp add --transport stdio cashout-memory -- python tools/memory/mcp_server.py
"""

from mcp.server.fastmcp import FastMCP
import pixeltable as pxt
from datetime import date

# Known index names for each searchable column
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


mcp = FastMCP(
    "CashOut Memory",
    instructions="""
    CashOut Memory provides semantic search over project documentation,
    architectural decisions, and past bug fixes for the CashOut project.

    Use search_docs() for documentation, search_issues() for past bugs,
    and search_decisions() for architectural decisions.

    After implementing fixes, use add_issue() to record them.
    After making architectural decisions, use add_decision() to record them.
    """
)

NAMESPACE = "cashout"


def _get_table(name: str):
    """Safely get a Pixeltable table."""
    try:
        return pxt.get_table(f"{NAMESPACE}.{name}")
    except Exception as e:
        raise RuntimeError(
            f"Table '{NAMESPACE}.{name}' not found. "
            f"Run 'python -m tools.memory.schema init' first. Error: {e}"
        )


@mcp.tool()
def search_docs(query: str, limit: int = 5) -> str:
    """
    Semantic search over CashOut project documentation.

    Searches architecture docs, ADRs, technical docs, stories,
    and other markdown documentation.

    Args:
        query: Natural language query
        limit: Maximum number of results to return (default: 5)

    Returns:
        Relevant documentation chunks with similarity scores and source files
    """
    try:
        doc_chunks = _get_table("doc_chunks")
        sim = _get_similarity(doc_chunks.text, query, "text")

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

        if not results:
            return f"No documentation found for: '{query}'"

        output = f"## Documentation Search: '{query}'\n\n"
        for i, row in enumerate(results, 1):
            score = row.get('similarity', 0)
            filename = row.get('filename', 'unknown')
            text = row.get('text', '')[:600]

            output += f"### {i}. [{score:.3f}] `{filename}`\n"
            output += f"{text}\n"
            if len(row.get('text', '')) > 600:
                output += "...\n"
            output += "\n"

        return output

    except Exception as e:
        return f"Error searching documentation: {e}"


@mcp.tool()
def search_issues(query: str, limit: int = 5) -> str:
    """
    Search past bugs, RCAs (Root Cause Analyses), and fixes.

    Use this to find how similar problems were solved before.

    Args:
        query: Symptom or problem description
        limit: Maximum number of results to return (default: 5)

    Returns:
        Related issues with symptoms, root causes, and fixes
    """
    try:
        issues = _get_table("issues")

        if issues.count() == 0:
            return "No issues recorded yet. Use add_issue() to record bug fixes."

        sim = _get_similarity(issues.symptoms, query, "symptoms")

        results = (
            issues
            .order_by(sim, asc=False)
            .select(
                issues.title,
                issues.symptoms,
                issues.root_cause,
                issues.fix,
                issues.prevention,
                issues.date,
                issues.category,
                similarity=sim
            )
            .limit(limit)
            .collect()
        )

        if not results:
            return f"No issues found matching: '{query}'"

        output = f"## Past Issues: '{query}'\n\n"
        for row in results:
            score = row.get('similarity', 0)
            output += f"### {row.get('title', 'Untitled')} [{score:.3f}]\n"
            output += f"**Date:** {row.get('date', 'unknown')} | "
            output += f"**Category:** {row.get('category', 'general')}\n\n"
            output += f"**Symptoms:** {row.get('symptoms', 'N/A')}\n\n"
            output += f"**Root Cause:** {row.get('root_cause', 'N/A')}\n\n"
            output += f"**Fix:** {row.get('fix', 'N/A')}\n\n"
            if row.get('prevention'):
                output += f"**Prevention:** {row.get('prevention')}\n\n"
            output += "---\n\n"

        return output

    except Exception as e:
        return f"Error searching issues: {e}"


@mcp.tool()
def search_decisions(query: str, limit: int = 5) -> str:
    """
    Search architectural decisions and their rationale.

    Use this to understand why certain design choices were made.

    Args:
        query: Topic or decision area
        limit: Maximum number of results to return (default: 5)

    Returns:
        Relevant decisions with rationale and context
    """
    try:
        decisions = _get_table("decisions")

        if decisions.count() == 0:
            return "No decisions recorded yet. Use add_decision() to record architectural decisions."

        sim = _get_similarity(decisions.decision, query, "decision")

        results = (
            decisions
            .order_by(sim, asc=False)
            .select(
                decisions.title,
                decisions.decision,
                decisions.rationale,
                decisions.alternatives_considered,
                decisions.related_files,
                decisions.date,
                decisions.category,
                similarity=sim
            )
            .limit(limit)
            .collect()
        )

        if not results:
            return f"No decisions found matching: '{query}'"

        output = f"## Architectural Decisions: '{query}'\n\n"
        for row in results:
            score = row.get('similarity', 0)
            output += f"### {row.get('title', 'Untitled')} [{score:.3f}]\n"
            output += f"**Date:** {row.get('date', 'unknown')} | "
            output += f"**Category:** {row.get('category', 'general')}\n\n"
            output += f"**Decision:** {row.get('decision', 'N/A')}\n\n"
            output += f"**Rationale:** {row.get('rationale', 'N/A')}\n\n"
            if row.get('alternatives_considered'):
                output += f"**Alternatives Considered:** {row.get('alternatives_considered')}\n\n"
            if row.get('related_files'):
                output += f"**Related Files:** `{row.get('related_files')}`\n\n"
            output += "---\n\n"

        return output

    except Exception as e:
        return f"Error searching decisions: {e}"


@mcp.tool()
def search_all(query: str, limit: int = 3) -> str:
    """
    Search across all memory sources: docs, issues, and decisions.

    Args:
        query: Natural language query
        limit: Results per category (default: 3)

    Returns:
        Combined results from documentation, issues, and decisions
    """
    output = f"# Memory Search: '{query}'\n\n"
    output += search_docs(query, limit)
    output += "\n"
    output += search_issues(query, limit)
    output += "\n"
    output += search_decisions(query, limit)
    return output


@mcp.tool()
def add_decision(
    title: str,
    decision: str,
    rationale: str,
    category: str = "general",
    alternatives_considered: str = "",
    related_files: str = ""
) -> str:
    """
    Record an architectural decision for future reference.

    Args:
        title: Short descriptive title
        decision: What was decided (the WHAT)
        rationale: Why it was decided (the WHY - most important for search!)
        category: Topic area (architecture, ui, api, database, performance, etc.)
        alternatives_considered: What options were rejected and why
        related_files: Comma-separated file paths affected

    Returns:
        Confirmation message
    """
    try:
        decisions = _get_table("decisions")

        decisions.insert([{
            "date": str(date.today()),
            "title": title,
            "decision": decision,
            "rationale": rationale,
            "alternatives_considered": alternatives_considered,
            "related_files": related_files,
            "category": category,
        }])

        return f"Recorded decision: **{title}**\n\nCategory: {category}\nDate: {date.today()}"

    except Exception as e:
        return f"Error recording decision: {e}"


@mcp.tool()
def add_issue(
    title: str,
    symptoms: str,
    root_cause: str,
    fix: str,
    category: str = "general",
    prevention: str = "",
    related_files: str = ""
) -> str:
    """
    Record a bug fix / RCA for future reference.

    Args:
        title: Short descriptive title
        symptoms: What was observed (searchable - be descriptive!)
        root_cause: Why it happened (the underlying reason)
        fix: What fixed it (code changes, configuration, etc.)
        category: Topic area (ui, api, crash, database, performance, etc.)
        prevention: How to prevent this in the future
        related_files: Comma-separated file paths affected

    Returns:
        Confirmation message
    """
    try:
        issues = _get_table("issues")

        issues.insert([{
            "date": str(date.today()),
            "title": title,
            "symptoms": symptoms,
            "root_cause": root_cause,
            "fix": fix,
            "prevention": prevention,
            "related_files": related_files,
            "category": category,
        }])

        return f"Recorded issue: **{title}**\n\nCategory: {category}\nDate: {date.today()}"

    except Exception as e:
        return f"Error recording issue: {e}"


@mcp.tool()
def memory_status() -> str:
    """
    Get the status of the CashOut memory system.

    Returns:
        Summary of indexed documents, issues, and decisions
    """
    try:
        status = "# CashOut Memory Status\n\n"

        tables = [
            ("documents", "Source documents"),
            ("doc_chunks", "Document chunks (searchable)"),
            ("decisions", "Architectural decisions"),
            ("issues", "Bug fixes / RCAs"),
        ]

        for table_name, description in tables:
            try:
                table = pxt.get_table(f"{NAMESPACE}.{table_name}")
                count = table.count()
                status += f"- **{description}**: {count} entries\n"
            except Exception:
                status += f"- **{description}**: NOT INITIALIZED\n"

        status += "\n## Quick Tips\n"
        status += "- `search_docs(query)` - Search documentation\n"
        status += "- `search_issues(query)` - Find past bug fixes\n"
        status += "- `search_decisions(query)` - Find architectural decisions\n"
        status += "- `add_issue(...)` - Record a bug fix\n"
        status += "- `add_decision(...)` - Record a decision\n"

        return status

    except Exception as e:
        return f"Error getting status: {e}"


if __name__ == "__main__":
    mcp.run()
