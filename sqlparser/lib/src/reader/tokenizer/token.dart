import 'package:source_span/source_span.dart';

enum TokenType {
  leftParen,
  rightParen,
  comma,
  dot,
  doublePipe,
  star,
  slash,
  percent,
  plus,
  minus,
  shiftLeft,
  shiftRight,
  ampersand,
  pipe,
  less,
  lessEqual,
  more,
  moreEqual,
  equal,
  doubleEqual,
  exclamationEqual,
  lessMore,
  $is,
  $in,
  not,
  like,
  glob,
  match,
  regexp,
  escape,
  and,
  or,
  tilde,
  between,
  exists,
  collate,

  questionMark,
  colon,
  // todo at and dollarSign are currently not used
  at,
  dollarSign,

  stringLiteral,
  numberLiteral,
  $true,
  $false,
  $null,
  currentTime,
  currentDate,
  currentTimestamp,
  identifier,

  select,
  delete,
  update,
  distinct,
  all,
  from,
  as,
  where,

  natural,
  left,
  outer,
  inner,
  cross,
  join,
  on,
  using,

  group,
  order,
  by,
  asc,
  desc,
  having,

  limit,
  offset,

  $case,
  when,
  then,
  $else,
  end,

  window,
  filter,
  over,
  partition,
  range,
  rows,
  groups,
  unbounded,
  preceding,
  following,
  current,
  row,
  exclude,
  others,
  ties,

  rollback,
  abort,
  replace,
  fail,
  ignore,
  set,

  create,
  table,
  $if,
  without,
  rowid,
  constraint,
  autoincrement,
  primary,
  foreign,
  key,
  unique,
  check,
  $default,
  conflict,
  references,
  cascade,
  restrict,
  no,
  action,

  semicolon,
  eof,
}

const Map<String, TokenType> keywords = {
  'SELECT': TokenType.select,
  'COLLATE': TokenType.collate,
  'DISTINCT': TokenType.distinct,
  'UPDATE': TokenType.update,
  'ALL': TokenType.all,
  'AND': TokenType.and,
  'OR': TokenType.or,
  'EXISTS': TokenType.exists,
  'BETWEEN': TokenType.between,
  'DELETE': TokenType.delete,
  'FROM': TokenType.from,
  'NATURAL': TokenType.natural,
  'LEFT': TokenType.left,
  'OUTER': TokenType.outer,
  'INNER': TokenType.inner,
  'CROSS': TokenType.cross,
  'JOIN': TokenType.join,
  'ON': TokenType.on,
  'USING': TokenType.using,
  'AS': TokenType.as,
  'WHERE': TokenType.where,
  'ORDER': TokenType.order,
  'GROUP': TokenType.group,
  'HAVING': TokenType.having,
  'BY': TokenType.by,
  'ASC': TokenType.asc,
  'DESC': TokenType.desc,
  'LIMIT': TokenType.limit,
  'OFFSET': TokenType.offset,
  'SET': TokenType.set,
  'IS': TokenType.$is,
  'IN': TokenType.$in,
  'LIKE': TokenType.like,
  'GLOB': TokenType.glob,
  'MATCH': TokenType.match,
  'REGEXP': TokenType.regexp,
  'ESCAPE': TokenType.escape,
  'NOT': TokenType.not,
  'TRUE': TokenType.$true,
  'FALSE': TokenType.$false,
  'NULL': TokenType.$null,
  'CURRENT_TIME': TokenType.currentTime,
  'CURRENT_DATE': TokenType.currentDate,
  'CURRENT_TIMESTAMP': TokenType.currentTimestamp,
  'CASE': TokenType.$case,
  'WHEN': TokenType.when,
  'THEN': TokenType.then,
  'ELSE': TokenType.$else,
  'END': TokenType.end,
  'ABORT': TokenType.abort,
  'ROLLBACK': TokenType.rollback,
  'REPLACE': TokenType.replace,
  'FAIL': TokenType.fail,
  'IGNORE': TokenType.ignore,
  'CREATE': TokenType.create,
  'TABLE': TokenType.table,
  'IF': TokenType.$if,
  'WITHOUT': TokenType.without,
  'ROWID': TokenType.rowid,
  'CONSTRAINT': TokenType.constraint,
  'AUTOINCREMENT': TokenType.autoincrement,
  'PRIMARY': TokenType.primary,
  'FOREIGN': TokenType.foreign,
  'KEY': TokenType.key,
  'UNIQUE': TokenType.unique,
  'CHECK': TokenType.check,
  'DEFAULT': TokenType.$default,
  'CONFLICT': TokenType.conflict,
  'REFERENCES': TokenType.references,
  'CASCADE': TokenType.cascade,
  'RESTRICT': TokenType.restrict,
  'NO': TokenType.no,
  'ACTION': TokenType.action,
  'FILTER': TokenType.filter,
  'OVER': TokenType.over,
  'PARTITION': TokenType.partition,
  'RANGE': TokenType.range,
  'ROWS': TokenType.rows,
  'GROUPS': TokenType.groups,
  'UNBOUNDED': TokenType.unbounded,
  'PRECEDING': TokenType.preceding,
  'FOLLOWING': TokenType.following,
  'CURRENT': TokenType.current,
  'ROW': TokenType.row,
  'EXCLUDE': TokenType.exclude,
  'OTHERS': TokenType.others,
  'TIES': TokenType.ties,
  'WINDOW': TokenType.window,
};

class Token {
  final TokenType type;

  final FileSpan span;
  String get lexeme => span.text;

  const Token(this.type, this.span);

  @override
  String toString() {
    return '$type: $lexeme';
  }
}

class StringLiteralToken extends Token {
  final String value;

  /// sqlite allows binary strings (x'literal') which are interpreted as blobs.
  final bool binary;

  const StringLiteralToken(this.value, FileSpan span, {this.binary = false})
      : super(TokenType.stringLiteral, span);
}

class IdentifierToken extends Token {
  /// Whether this identifier was escaped by putting it in "double ticks".
  final bool escaped;

  String get identifier {
    if (escaped) {
      return lexeme.substring(1, lexeme.length - 1);
    } else {
      return lexeme;
    }
  }

  const IdentifierToken(this.escaped, FileSpan span)
      : super(TokenType.identifier, span);
}

class TokenizerError {
  final String message;
  final SourceLocation location;

  TokenizerError(this.message, this.location);
}

/// Thrown by the sql engine when a sql statement can't be tokenized.
class CumulatedTokenizerException implements Exception {
  final List<TokenizerError> errors;
  CumulatedTokenizerException(this.errors);

  @override
  String toString() {
    final explanation =
        errors.map((e) => '${e.message} at ${e.location}').join(', ');
    return 'Malformed sql: $explanation';
  }
}
