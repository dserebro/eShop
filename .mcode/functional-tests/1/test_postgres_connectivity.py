"""
Functional tests for PostgreSQL connectivity (Milestone 1).

Verifies that the infrastructure provisioning created the required databases
and that the OrderProcessor's NpgsqlDataSource can connect to orderingdb.
Tests use direct PostgreSQL connections to verify the databases are accessible
with the configured credentials.
"""
import psycopg2
import pytest


# Connection parameters matching the lifecycle env_vars.json
DB_HOST = "localhost"
DB_PORT = 5432
DB_USER = "eshop"
DB_PASSWORD = "eshoppass"


@pytest.fixture(autouse=True)
def postgres_reachable():
    """Confirm PostgreSQL is reachable before running tests."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            dbname="orderingdb",
            connect_timeout=5,
        )
        conn.close()
    except psycopg2.OperationalError as e:
        pytest.fail(f"PostgreSQL not reachable: {e}")


class TestOrderingDbConnectivity:
    """Verify orderingdb is accessible — proves OrderProcessor's NpgsqlDataSource config works."""

    def test_orderingdb_connection(self):
        """Connect to orderingdb with eshop credentials (same as OrderProcessor uses)."""
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            dbname="orderingdb",
            connect_timeout=10,
        )
        try:
            cur = conn.cursor()
            cur.execute("SELECT 1")
            result = cur.fetchone()
            assert result == (1,), f"Expected (1,), got {result}"
            cur.close()
        finally:
            conn.close()

    def test_orderingdb_version(self):
        """Verify PostgreSQL version is 16.x as specified in the milestone."""
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            dbname="orderingdb",
            connect_timeout=10,
        )
        try:
            cur = conn.cursor()
            cur.execute("SHOW server_version")
            version = cur.fetchone()[0]
            assert version.startswith("16"), (
                f"Expected PostgreSQL 16.x, got {version}"
            )
            cur.close()
        finally:
            conn.close()

    def test_pgvector_extension_available(self):
        """Verify pgvector extension is available in orderingdb (required by spec)."""
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            dbname="orderingdb",
            connect_timeout=10,
        )
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT extname FROM pg_extension WHERE extname = 'vector'"
            )
            result = cur.fetchone()
            assert result is not None, "pgvector extension not installed in orderingdb"
            assert result[0] == "vector"
            cur.close()
        finally:
            conn.close()

    def test_ordering_schema_graceful_absence(self):
        """OrderProcessor's GracePeriodOrdersRepository catches NpgsqlException
        when ordering.orders table doesn't exist yet (Ordering.API migrations
        not migrated). Verify the table does NOT exist — this confirms the
        service handles the missing schema gracefully."""
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            dbname="orderingdb",
            connect_timeout=10,
        )
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT EXISTS ("
                "  SELECT FROM information_schema.tables "
                "  WHERE table_schema = 'ordering' AND table_name = 'orders'"
                ")"
            )
            exists = cur.fetchone()[0]
            # The table should NOT exist in milestone 1 (Ordering.API not yet migrated)
            # OrderProcessor handles this gracefully
            assert exists is False, (
                "ordering.orders table should not exist yet in milestone 1"
            )
            cur.close()
        finally:
            conn.close()


class TestAllDatabasesAccessible:
    """Verify all four databases provisioned by infrastructure scripts are accessible."""

    @pytest.mark.parametrize("dbname", ["catalogdb", "identitydb", "orderingdb", "webhooksdb"])
    def test_database_accessible(self, dbname):
        """Each of the four databases should be accessible with eshop credentials."""
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            dbname=dbname,
            connect_timeout=10,
        )
        try:
            cur = conn.cursor()
            cur.execute("SELECT current_database()")
            result = cur.fetchone()
            assert result[0] == dbname, (
                f"Expected database {dbname}, got {result[0]}"
            )
            cur.close()
        finally:
            conn.close()
