import 'dart:math' show max;

import 'package:moor_generator/src/model/specified_column.dart';
import 'package:moor_generator/src/model/sql_query.dart';
import 'package:moor_generator/src/state/session.dart';
import 'package:moor_generator/src/utils/string_escaper.dart';
import 'package:recase/recase.dart';
import 'package:sqlparser/sqlparser.dart';

const queryEngineWarningDesc =
    'No longer needed with Moor 1.6 - see the changelog for details';

const highestAssignedIndexVar = '\$highestIndex';

/// Writes the handling code for a query. The code emitted will be a method that
/// should be included in a generated database or dao class.
class QueryWriter {
  final SqlQuery query;
  final GeneratorSession session;
  SqlSelectQuery get _select => query as SqlSelectQuery;
  UpdatingQuery get _update => query as UpdatingQuery;

  final Set<String> _writtenMappingMethods;

  QueryWriter(this.query, this.session, this._writtenMappingMethods);

  /// The expanded sql that we insert into queries whenever an array variable
  /// appears. For the query "SELECT * FROM t WHERE x IN ?", we generate
  /// ```dart
  /// test(List<int> var1) {
  ///   final expandedvar1 = List.filled(var1.length, '?').join(',');
  ///   customSelect('SELECT * FROM t WHERE x IN ($expandedvar1)', ...);
  /// }
  /// ```
  String _expandedName(FoundVariable v) {
    return 'expanded${v.dartParameterName}';
  }

  void writeInto(StringBuffer buffer) {
    if (query is SqlSelectQuery) {
      _writeSelect(buffer);
    } else if (query is UpdatingQuery) {
      _writeUpdatingQuery(buffer);
    }
  }

  void _writeSelect(StringBuffer buffer) {
    _writeMapping(buffer);
    _writeOneTimeReader(buffer);
    _writeStreamReader(buffer);
  }

  String _nameOfMappingMethod() {
    return '_rowTo${_select.resultClassName}';
  }

  /// Writes a mapping method that turns a "QueryRow" into the desired custom
  /// return type.
  void _writeMapping(StringBuffer buffer) {
    // avoid writing mapping methods twice if the same result class is written
    // more than once.
    if (!_writtenMappingMethods.contains(_nameOfMappingMethod())) {
      buffer
        ..write('${_select.resultClassName} ${_nameOfMappingMethod()}')
        ..write('(QueryRow row) {\n')
        ..write('return ${_select.resultClassName}(');

      for (var column in _select.resultSet.columns) {
        final fieldName = _select.resultSet.dartNameFor(column);
        final readMethod = readFromMethods[column.type];

        var code = "row.$readMethod('${column.name}')";

        if (column.converter != null) {
          final converter = column.converter;
          final infoName = converter.table.tableInfoName;
          final field = '$infoName.${converter.fieldName}';

          code = '$field.mapToDart($code)';
        }

        buffer.write('$fieldName: $code,');
      }

      buffer.write(');\n}\n');
      _writtenMappingMethods.add(_nameOfMappingMethod());
    }
  }

  void _writeOneTimeReader(StringBuffer buffer) {
    buffer.write('Future<List<${_select.resultClassName}>> ${query.name}(');
    _writeParameters(buffer);
    buffer.write(') {\n');
    _writeExpandedDeclarations(buffer);
    buffer
      ..write('return (operateOn ?? this).') // use custom engine, if set
      ..write('customSelect(${_queryCode()},');
    _writeVariables(buffer);
    buffer
      ..write(')')
      ..write(
          '.then((rows) => rows.map(${_nameOfMappingMethod()}).toList());\n')
      ..write('\n}\n');
  }

  void _writeStreamReader(StringBuffer buffer) {
    // turning the query name into pascal case will remove underscores
    final upperQueryName = ReCase(query.name).pascalCase;

    String methodName;
    if (session.options.fixPrivateWatchMethods && query.name.startsWith('_')) {
      methodName = '_watch$upperQueryName';
    } else {
      methodName = 'watch$upperQueryName';
    }

    buffer.write('Stream<List<${_select.resultClassName}>> $methodName(');
    // don't supply an engine override parameter because select streams cannot
    // be used in transaction or similar context, only on the main database
    // engine.
    _writeParameters(buffer, dontOverrideEngine: true);
    buffer.write(') {\n');

    _writeExpandedDeclarations(buffer);
    buffer..write('return customSelectStream(${_queryCode()},');

    _writeVariables(buffer);
    buffer.write(',');
    _writeReadsFrom(buffer);

    buffer
      ..write(')')
      ..write('.map((rows) => rows.map(${_nameOfMappingMethod()}).toList());\n')
      ..write('\n}\n');
  }

  void _writeUpdatingQuery(StringBuffer buffer) {
    /*
      Future<int> test() {
    return customUpdate('', variables: [], updates: {});
  }
     */
    buffer.write('Future<int> ${query.name}(');
    _writeParameters(buffer);
    buffer.write(') {\n');

    _writeExpandedDeclarations(buffer);
    buffer
      ..write('return (operateOn ?? this).')
      ..write('customUpdate(${_queryCode()},');

    _writeVariables(buffer);
    buffer.write(',');
    _writeUpdates(buffer);

    buffer..write(',);\n}\n');
  }

  void _writeParameters(StringBuffer buffer,
      {bool dontOverrideEngine = false}) {
    final paramList = query.variables.map((v) {
      var dartType = dartTypeNames[v.type];
      if (v.isArray) {
        dartType = 'List<$dartType>';
      }
      return '$dartType ${v.dartParameterName}';
    }).join(', ');

    buffer.write(paramList);

    // write named optional parameter to configure the query engine used to
    // execute the statement,
    if (!dontOverrideEngine) {
      if (query.variables.isNotEmpty) buffer.write(', ');
      buffer.write('{@Deprecated(${asDartLiteral(queryEngineWarningDesc)}) '
          'QueryEngine operateOn}');
    }
  }

  // Some notes on parameters and generating query code:
  // We expand array parameters to multiple variables at runtime (see the
  // documentation of FoundVariable and SqlQuery for further discussion).
  // To do this. we have to rewrite the sql. Consider this query:
  // SELECT * FROM t WHERE a = ?1 AND b IN :vars OR c IN :vars AND d = ?
  // When expanding an array variable, we write the expanded sql into a local
  // var called "expanded$Name", e.g. when we bind "vars" to [1, 2, 3] in the
  // query, then `expandedVars` would be "(?2, ?3, ?4)".
  // We use explicit indexes when expanding so that we don't have to expand the
  // "vars" variable twice. To do this, a local var called "$currentVarIndex"
  // keeps track of the highest variable number assigned.

  void _writeExpandedDeclarations(StringBuffer buffer) {
    var indexCounterWasDeclared = false;
    var highestIndexBeforeArray = 0;

    for (var variable in query.variables) {
      if (variable.isArray) {
        if (!indexCounterWasDeclared) {
          // we only need the index counter when the query contains an array.
          // add +1 because that's going to be the first index of the expanded
          // array
          final firstVal = highestIndexBeforeArray + 1;
          buffer.write('var $highestAssignedIndexVar = $firstVal;');
          indexCounterWasDeclared = true;
        }

        // final expandedvar1 = $expandVar(<startIndex>, <amount>);
        buffer
          ..write('final ')
          ..write(_expandedName(variable))
          ..write(' = ')
          ..write(r'$expandVar(')
          ..write(highestAssignedIndexVar)
          ..write(', ')
          ..write(variable.dartParameterName)
          ..write('.length);\n');

        // increase highest index for the next array
        buffer
          ..write('$highestAssignedIndexVar += ')
          ..write(variable.dartParameterName)
          ..write('.length;');
      }

      if (!indexCounterWasDeclared) {
        highestIndexBeforeArray = max(highestIndexBeforeArray, variable.index);
      }
    }
  }

  void _writeVariables(StringBuffer buffer) {
    buffer..write('variables: [');

    for (var variable in query.variables) {
      // for a regular variable: Variable.withInt(x),
      // for a list of vars: for (var $ in vars) Variable.withInt($),
      final constructor = createVariable[variable.type];
      final name = variable.dartParameterName;

      if (variable.isArray) {
        buffer.write('for (var \$ in $name) $constructor(\$)');
      } else {
        buffer.write('$constructor($name)');
      }

      buffer.write(',');
    }

    buffer..write(']');
  }

  /// Returns a Dart string literal representing the query after variables have
  /// been expanded. For instance, 'SELECT * FROM t WHERE x IN ?' will be turned
  /// into 'SELECT * FROM t WHERE x IN ($expandedVar1)'.
  String _queryCode() {
    // sort variables by the order in which they appear
    final vars = query.fromContext.root.allDescendants
        .whereType<Variable>()
        .toList()
          ..sort((a, b) => a.firstPosition.compareTo(b.firstPosition));

    final buffer = StringBuffer("'");
    var lastIndex = 0;

    for (var sqlVar in vars) {
      final moorVar = query.variables
          .singleWhere((f) => f.variable.resolvedIndex == sqlVar.resolvedIndex);
      if (!moorVar.isArray) continue;

      // write everything that comes before this var into the buffer
      final currentIndex = sqlVar.firstPosition;
      final queryPart = query.sql.substring(lastIndex, currentIndex);
      buffer.write(escapeForDart(queryPart));
      lastIndex = sqlVar.lastPosition;

      // write the ($expandedVar) par
      buffer.write('(\$${_expandedName(moorVar)})');
    }

    // write the final part after the last variable, plus the ending '
    buffer..write(escapeForDart(query.sql.substring(lastIndex)))..write("'");

    return buffer.toString();
  }

  void _writeReadsFrom(StringBuffer buffer) {
    final from = _select.readsFrom.map((t) => t.tableFieldName).join(', ');
    buffer..write('readsFrom: {')..write(from)..write('}');
  }

  void _writeUpdates(StringBuffer buffer) {
    final from = _update.updates.map((t) => t.tableFieldName).join(', ');
    buffer..write('updates: {')..write(from)..write('}');
  }
}
