"""
CashOut Project Memory - Pixeltable-based long-term memory for Claude Code.

This package provides persistent semantic search across project documentation,
architectural decisions, and issue history.

Quick Start:
    # Initialize schema
    python -m tools.memory.schema init

    # Ingest docs
    python -m tools.memory.ingest dir docs/ --category general

    # Search
    python -m tools.memory.query docs "CloudKit sync"

Modules:
    schema: Database schema initialization and management
    ingest: Document and data ingestion
    query: Semantic search across all data sources
    mcp_server: FastMCP server for Claude Code integration
"""

__version__ = "0.1.0"
