"""
Document Ingestion for CashOut Project Memory

This module handles ingesting documents into Pixeltable for semantic search.

Usage:
    # Ingest a single file
    python -m tools.memory.ingest file docs/some-doc.md

    # Ingest all files in a directory
    python -m tools.memory.ingest dir docs/

    # Ingest with category
    python -m tools.memory.ingest dir docs/ --category architecture

    # List ingested documents
    python -m tools.memory.ingest list
"""

import pixeltable as pxt
from pathlib import Path
from datetime import datetime
import sys
import argparse

NAMESPACE = "cashout"


def ingest_file(filepath: str, category: str = "general") -> bool:
    """
    Ingest a single document file into Pixeltable.

    Args:
        filepath: Path to the document file
        category: Category for classification

    Returns:
        True if successful, False otherwise
    """
    path = Path(filepath)

    if not path.exists():
        print(f"  [!] File not found: {filepath}")
        return False

    if not path.suffix.lower() in ['.md', '.txt', '.pdf']:
        print(f"  [!] Unsupported file type: {path.suffix}")
        return False

    try:
        documents = pxt.get_table(f"{NAMESPACE}.documents")
    except Exception:
        print(f"  [!] Table not found. Run 'python -m tools.memory.schema init' first.")
        return False

    existing = documents.where(documents.filename == path.name).count()
    if existing > 0:
        print(f"  [~] Already ingested: {path.name} (skipping)")
        return True

    try:
        documents.insert([{
            "document": str(path.absolute()),
            "filename": path.name,
            "category": category,
            "indexed_at": datetime.now(),
        }])
        print(f"  [+] Ingested: {path.name}")
        return True
    except Exception as e:
        print(f"  [!] Error ingesting {path.name}: {str(e)[:100]}")
        return False


def ingest_directory(dirpath: str, category: str = "general", pattern: str = "*.md") -> int:
    """
    Ingest all matching files from a directory.

    Args:
        dirpath: Path to directory
        category: Category for all files
        pattern: Glob pattern for file matching

    Returns:
        Number of files successfully ingested
    """
    path = Path(dirpath)

    if not path.exists():
        print(f"[!] Directory not found: {dirpath}")
        return 0

    if not path.is_dir():
        print(f"[!] Not a directory: {dirpath}")
        return 0

    files = list(path.glob(pattern))
    print(f"\nFound {len(files)} files matching '{pattern}' in {dirpath}")
    print("-" * 50)

    success_count = 0
    for f in sorted(files):
        if f.name.startswith('.'):
            continue
        if ingest_file(str(f), category):
            success_count += 1

    print("-" * 50)
    print(f"Ingested {success_count}/{len(files)} files\n")

    try:
        doc_chunks = pxt.get_table(f"{NAMESPACE}.doc_chunks")
        print(f"Total chunks in index: {doc_chunks.count()}")
    except Exception:
        pass

    return success_count


def list_documents():
    """List all ingested documents."""
    try:
        documents = pxt.get_table(f"{NAMESPACE}.documents")
    except Exception:
        print("No documents table found. Run 'python -m tools.memory.schema init' first.")
        return

    result = documents.select(
        documents.filename,
        documents.category,
        documents.indexed_at
    ).order_by(documents.indexed_at, asc=False).collect()

    print("\nIngested Documents")
    print("=" * 60)

    if len(result) == 0:
        print("  No documents ingested yet.")
    else:
        for row in result:
            print(f"  {row['filename']:<45} [{row['category']}]")

    print(f"\nTotal: {len(result)} documents")

    try:
        doc_chunks = pxt.get_table(f"{NAMESPACE}.doc_chunks")
        print(f"Total chunks: {doc_chunks.count()}")
    except Exception:
        pass


def add_decision(
    title: str,
    decision: str,
    rationale: str,
    alternatives: str = "",
    files: str = "",
    category: str = "general"
) -> bool:
    """Add an architectural decision to the memory."""
    from datetime import date

    try:
        decisions = pxt.get_table(f"{NAMESPACE}.decisions")
    except Exception:
        print("[!] Decisions table not found. Run 'python -m tools.memory.schema init' first.")
        return False

    decisions.insert([{
        "date": str(date.today()),
        "title": title,
        "decision": decision,
        "rationale": rationale,
        "alternatives_considered": alternatives,
        "related_files": files,
        "category": category,
    }])

    print(f"[+] Added decision: {title}")
    return True


def add_issue(
    title: str,
    symptoms: str,
    root_cause: str,
    fix: str,
    prevention: str = "",
    files: str = "",
    category: str = "general"
) -> bool:
    """Add a bug/issue and its fix to the memory."""
    from datetime import date

    try:
        issues = pxt.get_table(f"{NAMESPACE}.issues")
    except Exception:
        print("[!] Issues table not found. Run 'python -m tools.memory.schema init' first.")
        return False

    issues.insert([{
        "date": str(date.today()),
        "title": title,
        "symptoms": symptoms,
        "root_cause": root_cause,
        "fix": fix,
        "prevention": prevention,
        "related_files": files,
        "category": category,
    }])

    print(f"[+] Added issue: {title}")
    return True


def main():
    parser = argparse.ArgumentParser(description="Ingest documents into CashOut memory")
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    file_parser = subparsers.add_parser("file", help="Ingest a single file")
    file_parser.add_argument("path", help="Path to the file")
    file_parser.add_argument("--category", default="general", help="Category for the file")

    dir_parser = subparsers.add_parser("dir", help="Ingest all files in a directory")
    dir_parser.add_argument("path", help="Path to the directory")
    dir_parser.add_argument("--category", default="general", help="Category for all files")
    dir_parser.add_argument("--pattern", default="*.md", help="Glob pattern (default: *.md)")

    subparsers.add_parser("list", help="List ingested documents")

    args = parser.parse_args()

    if args.command == "file":
        ingest_file(args.path, args.category)
    elif args.command == "dir":
        ingest_directory(args.path, args.category, args.pattern)
    elif args.command == "list":
        list_documents()
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
