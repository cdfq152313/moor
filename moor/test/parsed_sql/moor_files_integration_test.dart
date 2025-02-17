import 'package:moor/moor.dart';
import 'package:test_api/test_api.dart';

import '../data/tables/custom_tables.dart';
import '../data/utils/mocks.dart';

const _createNoIds =
    'CREATE TABLE IF NOT EXISTS no_ids (payload BLOB NOT NULL) WITHOUT ROWID;';

const _createWithDefaults = 'CREATE TABLE IF NOT EXISTS with_defaults ('
    "a VARCHAR DEFAULT 'something', b INTEGER UNIQUE);";

const _createWithConstraints = 'CREATE TABLE IF NOT EXISTS with_constraints ('
    'a VARCHAR, b INTEGER NOT NULL, c REAL, '
    'FOREIGN KEY (a, b) REFERENCES with_defaults (a, b)'
    ');';

const _createConfig = 'CREATE TABLE IF NOT EXISTS config ('
    'config_key VARCHAR not null primary key, '
    'config_value VARCHAR);';

const _createMyTable = 'CREATE TABLE IF NOT EXISTS mytable ('
    'someid INTEGER NOT NULL PRIMARY KEY, '
    'sometext VARCHAR);';

void main() {
  // see ../data/tables/tables.moor
  test('creates tables as specified in .moor files', () async {
    final mockExecutor = MockExecutor();
    final mockQueryExecutor = MockQueryExecutor();
    final db = CustomTablesDb(mockExecutor);
    await Migrator(db, mockQueryExecutor).createAllTables();

    verify(mockQueryExecutor.call(_createNoIds, []));
    verify(mockQueryExecutor.call(_createWithDefaults, []));
    verify(mockQueryExecutor.call(_createWithConstraints, []));
    verify(mockQueryExecutor.call(_createConfig, []));
    verify(mockQueryExecutor.call(_createMyTable, []));
  });

  test('infers primary keys correctly', () async {
    final db = CustomTablesDb(null);

    expect(db.noIds.primaryKey, isEmpty);
    expect(db.withDefaults.primaryKey, isEmpty);
    expect(db.config.primaryKey, [db.config.configKey]);
  });

  test('supports absent values for primary key integers', () async {
    // regression test for #112: https://github.com/simolus3/moor/issues/112
    final mock = MockExecutor();
    final db = CustomTablesDb(mock);

    await db.into(db.mytable).insert(const MytableCompanion());
    verify(mock.runInsert('INSERT INTO mytable DEFAULT VALUES', []));
  });
}
