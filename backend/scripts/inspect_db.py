"""Read-only inspection of the database pointed to by DATABASE_URL.

Prints server version, schemas, tables, row counts and columns. Never prints
the connection string or credentials. Makes no changes.
"""
from sqlalchemy import inspect, text

from app.database import engine


def main() -> None:
    print(f"Connecting to host: {engine.url.host} / db: {engine.url.database}")
    with engine.connect() as conn:
        print("Server:", conn.execute(text("select version()")).scalar_one().split(",")[0])
        pgconn = conn.connection.dbapi_connection.pgconn
        # Client-side TLS status (pg_stat_ssl would describe Neon's pooler hop instead).
        print("Client TLS in use:", bool(pgconn.ssl_in_use))
        insp = inspect(conn)
        for schema in insp.get_schema_names():
            if schema in ("information_schema",) or schema.startswith("pg_"):
                continue
            tables = insp.get_table_names(schema=schema)
            print(f"\nSchema '{schema}': {len(tables)} table(s)")
            for table in tables:
                count = conn.execute(text(f'select count(*) from "{schema}"."{table}"')).scalar_one()
                print(f"  - {table} ({count} rows)")
                for col in insp.get_columns(table, schema=schema):
                    print(f"      {col['name']}: {col['type']}{'' if col['nullable'] else ' NOT NULL'}")


if __name__ == "__main__":
    main()
