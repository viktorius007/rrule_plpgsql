import pytest
import psycopg2
import os
from hypothesis import settings, Verbosity

# Register profiles for different testing scenarios
settings.register_profile("ci", max_examples=1000)
settings.register_profile("dev", max_examples=100)
settings.register_profile("debug", max_examples=10, verbosity=Verbosity.verbose)

@pytest.fixture(scope="session")
def db():
    """Database connection fixture with connection pooling."""
    conn = psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=int(os.environ.get("PGPORT", "54322")),
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD", "postgres"),
        dbname=os.environ.get("PGDATABASE", "rrule_test")
    )
    yield conn
    conn.close()
