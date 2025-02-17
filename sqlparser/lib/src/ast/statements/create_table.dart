part of '../ast.dart';

/// A "CREATE TABLE" statement, see https://www.sqlite.org/lang_createtable.html
/// for the individual components.
class CreateTableStatement extends Statement with SchemaStatement {
  final bool ifNotExists;
  final String tableName;
  final List<ColumnDefinition> columns;
  final List<TableConstraint> tableConstraints;
  final bool withoutRowId;

  CreateTableStatement(
      {this.ifNotExists = false,
      @required this.tableName,
      this.columns = const [],
      this.tableConstraints = const [],
      this.withoutRowId = false});

  @override
  T accept<T>(AstVisitor<T> visitor) => visitor.visitCreateTableStatement(this);

  @override
  Iterable<AstNode> get childNodes => [...columns, ...tableConstraints];

  @override
  bool contentEquals(CreateTableStatement other) {
    return other.ifNotExists == ifNotExists &&
        other.tableName == tableName &&
        other.withoutRowId == withoutRowId;
  }
}
