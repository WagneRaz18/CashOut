"""
Pixeltable Schema for CashOut Project Memory

This module defines the database schema for long-term memory storage,
enabling semantic search across project documentation and decisions.

Usage:
    python -m tools.memory.schema init     # Initialize schema
    python -m tools.memory.schema status   # Check schema status
    python -m tools.memory.schema repair   # Fix embedding index issues
    python -m tools.memory.schema reset    # Reset all data (DESTRUCTIVE)
"""

import pixeltable as pxt
from pixeltable.functions.huggingface import sentence_transformer
from pixeltable.functions.document import document_splitter
import sys

# Embedding model for semantic search
EMBED_MODEL = sentence_transformer.using(model_id='intfloat/e5-base-v2')

# Namespace for all CashOut project data — completely separate from other projects
NAMESPACE = "cashout"


def init_schema() -> dict:
    """
    Initialize the Pixeltable schema for CashOut project memory.

    Creates:
        - cashout.documents: Source documents (architecture docs, etc.)
        - cashout.doc_chunks: Chunked view with embeddings for search
        - cashout.decisions: Architectural decisions (manual entries)
        - cashout.issues: Bug reports and RCAs

    Returns:
        dict with table references
    """
    print(f"Initializing Pixeltable schema in namespace '{NAMESPACE}'...")

    pxt.create_dir(NAMESPACE, if_exists="ignore")
    print(f"  [+] Namespace '{NAMESPACE}' ready")

    # ==========================================================================
    # Table 1: Documents (source files)
    # ==========================================================================
    documents = pxt.create_table(
        f"{NAMESPACE}.documents",
        {
            "document": pxt.Document,
            "filename": pxt.String,
            "category": pxt.String,
            "indexed_at": pxt.Timestamp,
        },
        if_exists="ignore"
    )
    print(f"  [+] Table '{NAMESPACE}.documents' ready")

    # ==========================================================================
    # View: Document Chunks (for semantic search)
    # ==========================================================================
    try:
        doc_chunks = pxt.get_table(f"{NAMESPACE}.doc_chunks")
        print(f"  [+] View '{NAMESPACE}.doc_chunks' already exists")
    except Exception:
        doc_chunks = pxt.create_view(
            f"{NAMESPACE}.doc_chunks",
            documents,
            iterator=document_splitter(
                document=documents.document,
                separators="token_limit",
                limit=500,
                overlap=50,
                metadata="title,heading",
            )
        )
        print(f"  [+] View '{NAMESPACE}.doc_chunks' created")

    try:
        doc_chunks.add_embedding_index(
            "text", idx_name="text_idx", string_embed=EMBED_MODEL, if_exists="ignore"
        )
        print(f"  [+] Embedding index 'text_idx' added to doc_chunks.text")
    except Exception as e:
        if "already exists" in str(e).lower():
            print(f"  [+] Embedding index already exists on doc_chunks.text")
        else:
            print(f"  [!] Warning: Could not add embedding index: {e}")

    # ==========================================================================
    # Table 2: Decisions (manual architectural decisions)
    # ==========================================================================
    decisions = pxt.create_table(
        f"{NAMESPACE}.decisions",
        {
            "date": pxt.String,
            "title": pxt.String,
            "decision": pxt.String,
            "rationale": pxt.String,
            "alternatives_considered": pxt.String,
            "related_files": pxt.String,
            "category": pxt.String,
        },
        if_exists="ignore"
    )
    print(f"  [+] Table '{NAMESPACE}.decisions' ready")

    try:
        decisions.add_embedding_index(
            "decision", idx_name="decision_idx", string_embed=EMBED_MODEL, if_exists="ignore"
        )
        decisions.add_embedding_index(
            "rationale", idx_name="rationale_idx", string_embed=EMBED_MODEL, if_exists="ignore"
        )
        print(f"  [+] Embedding indexes added to decisions")
    except Exception as e:
        if "already exists" in str(e).lower() or "duplicate index name" in str(e).lower():
            print(f"  [+] Embedding indexes already exist on decisions")
        else:
            print(f"  [!] Warning: {e}")

    # ==========================================================================
    # Table 3: Issues (bugs, RCAs, fixes)
    # ==========================================================================
    issues = pxt.create_table(
        f"{NAMESPACE}.issues",
        {
            "date": pxt.String,
            "title": pxt.String,
            "symptoms": pxt.String,
            "root_cause": pxt.String,
            "fix": pxt.String,
            "prevention": pxt.String,
            "related_files": pxt.String,
            "category": pxt.String,
        },
        if_exists="ignore"
    )
    print(f"  [+] Table '{NAMESPACE}.issues' ready")

    try:
        issues.add_embedding_index(
            "symptoms", idx_name="symptoms_idx", string_embed=EMBED_MODEL, if_exists="ignore"
        )
        issues.add_embedding_index(
            "root_cause", idx_name="root_cause_idx", string_embed=EMBED_MODEL, if_exists="ignore"
        )
        print(f"  [+] Embedding indexes added to issues")
    except Exception as e:
        if "already exists" in str(e).lower() or "duplicate index name" in str(e).lower():
            print(f"  [+] Embedding indexes already exist on issues")
        else:
            print(f"  [!] Warning: {e}")

    print("\nSchema initialization complete!")
    return {
        "documents": documents,
        "doc_chunks": doc_chunks,
        "decisions": decisions,
        "issues": issues,
    }


def get_status() -> dict:
    """Get status of all tables and their row counts."""
    status = {}
    tables = [
        f"{NAMESPACE}.documents",
        f"{NAMESPACE}.doc_chunks",
        f"{NAMESPACE}.decisions",
        f"{NAMESPACE}.issues",
    ]

    for table_name in tables:
        try:
            table = pxt.get_table(table_name)
            count = table.count()
            status[table_name] = {"exists": True, "count": count}
        except Exception as e:
            status[table_name] = {"exists": False, "error": str(e)}

    return status


def print_status():
    """Print formatted status of all tables."""
    print("\nPixeltable Schema Status")
    print("=" * 50)

    status = get_status()
    for table_name, info in status.items():
        if info["exists"]:
            print(f"  {table_name}: {info['count']} rows")
        else:
            print(f"  {table_name}: NOT FOUND")
    print()


def reset_schema():
    """Reset all data (DESTRUCTIVE - requires confirmation)."""
    confirm = input("This will DELETE ALL DATA in 'cashout' namespace. Type 'yes' to confirm: ")
    if confirm.lower() != 'yes':
        print("Aborted.")
        return

    print("Resetting schema...")
    pxt.drop_dir(NAMESPACE, force=True)
    print(f"  [-] Namespace '{NAMESPACE}' dropped")

    init_schema()


def repair_indices():
    """
    Repair embedding indices by dropping old unnamed indices and adding properly named ones.
    """
    print("Repairing embedding indices...")

    # Repair doc_chunks view
    try:
        doc_chunks = pxt.get_table(f"{NAMESPACE}.doc_chunks")
        print(f"  [*] Repairing {NAMESPACE}.doc_chunks...")

        try:
            doc_chunks.drop_embedding_index(column="text")
            print(f"      [-] Dropped old index on 'text'")
        except Exception as e:
            if "does not have an index" not in str(e).lower():
                for idx_name in ["idx0", "idx1", "idx2", "text_idx"]:
                    try:
                        doc_chunks.drop_embedding_index(idx_name=idx_name)
                        print(f"      [-] Dropped index '{idx_name}'")
                    except Exception:
                        pass

        doc_chunks.add_embedding_index(
            "text", idx_name="text_idx", string_embed=EMBED_MODEL, if_exists="replace"
        )
        print(f"      [+] Added 'text_idx' index")

    except Exception as e:
        print(f"  [!] Error repairing doc_chunks: {e}")

    # Repair decisions table
    try:
        decisions = pxt.get_table(f"{NAMESPACE}.decisions")
        print(f"  [*] Repairing {NAMESPACE}.decisions...")

        try:
            decisions.drop_embedding_index(column="decision")
            print(f"      [-] Dropped old index on 'decision'")
        except Exception as e:
            if "does not have an index" not in str(e).lower():
                for idx_name in ["idx0", "idx1", "idx2", "decision_idx"]:
                    try:
                        decisions.drop_embedding_index(idx_name=idx_name)
                        print(f"      [-] Dropped index '{idx_name}'")
                    except Exception:
                        pass

        try:
            decisions.drop_embedding_index(column="rationale")
            print(f"      [-] Dropped old index on 'rationale'")
        except Exception as e:
            if "does not have an index" not in str(e).lower():
                for idx_name in ["idx3", "idx4", "idx5", "rationale_idx"]:
                    try:
                        decisions.drop_embedding_index(idx_name=idx_name)
                        print(f"      [-] Dropped index '{idx_name}'")
                    except Exception:
                        pass

        decisions.add_embedding_index(
            "decision", idx_name="decision_idx", string_embed=EMBED_MODEL, if_exists="replace"
        )
        print(f"      [+] Added 'decision_idx' index")
        decisions.add_embedding_index(
            "rationale", idx_name="rationale_idx", string_embed=EMBED_MODEL, if_exists="replace"
        )
        print(f"      [+] Added 'rationale_idx' index")

    except Exception as e:
        print(f"  [!] Error repairing decisions: {e}")

    # Repair issues table
    try:
        issues = pxt.get_table(f"{NAMESPACE}.issues")
        print(f"  [*] Repairing {NAMESPACE}.issues...")

        try:
            issues.drop_embedding_index(column="symptoms")
            print(f"      [-] Dropped old index on 'symptoms'")
        except Exception as e:
            if "does not have an index" not in str(e).lower():
                for idx_name in ["idx0", "idx1", "idx2", "symptoms_idx"]:
                    try:
                        issues.drop_embedding_index(idx_name=idx_name)
                        print(f"      [-] Dropped index '{idx_name}'")
                    except Exception:
                        pass

        try:
            issues.drop_embedding_index(column="root_cause")
            print(f"      [-] Dropped old index on 'root_cause'")
        except Exception as e:
            if "does not have an index" not in str(e).lower():
                for idx_name in ["idx3", "idx4", "idx5", "root_cause_idx"]:
                    try:
                        issues.drop_embedding_index(idx_name=idx_name)
                        print(f"      [-] Dropped index '{idx_name}'")
                    except Exception:
                        pass

        issues.add_embedding_index(
            "symptoms", idx_name="symptoms_idx", string_embed=EMBED_MODEL, if_exists="replace"
        )
        print(f"      [+] Added 'symptoms_idx' index")
        issues.add_embedding_index(
            "root_cause", idx_name="root_cause_idx", string_embed=EMBED_MODEL, if_exists="replace"
        )
        print(f"      [+] Added 'root_cause_idx' index")

    except Exception as e:
        print(f"  [!] Error repairing issues: {e}")

    print("\nIndex repair complete!")
    print("Note: If errors persist, run 'python -m tools.memory.schema reset' to start fresh.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == "init":
        init_schema()
    elif command == "status":
        print_status()
    elif command == "reset":
        reset_schema()
    elif command == "repair":
        repair_indices()
    else:
        print(f"Unknown command: {command}")
        print(__doc__)
        sys.exit(1)
