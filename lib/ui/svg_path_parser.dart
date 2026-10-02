import 'dart:ui';

/// Parses an SVG path data string containing M, C, L, and Z commands into a Flutter [Path].
///
/// Designed with high performance and zero external dependencies:
/// - Supports absolute (M, C, L, Z) and relative (m, c, l, z) commands.
/// - Handles multiple comma/whitespace-separated coordinates.
/// - Handles negative numbers without spaces (e.g., "10-20" or "10.5-3.2").
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = _tokenizeSvgPath(d);
  if (tokens.isEmpty) return path;

  int i = 0;
  String currentCommand = '';
  double currentX = 0.0;
  double currentY = 0.0;
  double startX = 0.0;
  double startY = 0.0;

  while (i < tokens.length) {
    final token = tokens[i];
    final isCommand = _isAlpha(token);

    if (isCommand) {
      currentCommand = token;
      i++;
    }

    switch (currentCommand) {
      case 'M':
        if (i + 1 < tokens.length) {
          final x = double.parse(tokens[i++]);
          final y = double.parse(tokens[i++]);
          path.moveTo(x, y);
          currentX = x;
          currentY = y;
          startX = x;
          startY = y;
          // Subsequent coordinate pairs after M are treated as implicit L
          currentCommand = 'L';
        }
        break;

      case 'm':
        if (i + 1 < tokens.length) {
          final x = currentX + double.parse(tokens[i++]);
          final y = currentY + double.parse(tokens[i++]);
          path.moveTo(x, y);
          currentX = x;
          currentY = y;
          startX = x;
          startY = y;
          currentCommand = 'l';
        }
        break;

      case 'L':
        if (i + 1 < tokens.length) {
          final x = double.parse(tokens[i++]);
          final y = double.parse(tokens[i++]);
          path.lineTo(x, y);
          currentX = x;
          currentY = y;
        }
        break;

      case 'l':
        if (i + 1 < tokens.length) {
          final x = currentX + double.parse(tokens[i++]);
          final y = currentY + double.parse(tokens[i++]);
          path.lineTo(x, y);
          currentX = x;
          currentY = y;
        }
        break;

      case 'C':
        if (i + 5 < tokens.length) {
          final x1 = double.parse(tokens[i++]);
          final y1 = double.parse(tokens[i++]);
          final x2 = double.parse(tokens[i++]);
          final y2 = double.parse(tokens[i++]);
          final x = double.parse(tokens[i++]);
          final y = double.parse(tokens[i++]);
          path.cubicTo(x1, y1, x2, y2, x, y);
          currentX = x;
          currentY = y;
        }
        break;

      case 'c':
        if (i + 5 < tokens.length) {
          final x1 = currentX + double.parse(tokens[i++]);
          final y1 = currentY + double.parse(tokens[i++]);
          final x2 = currentX + double.parse(tokens[i++]);
          final y2 = currentY + double.parse(tokens[i++]);
          final x = currentX + double.parse(tokens[i++]);
          final y = currentY + double.parse(tokens[i++]);
          path.cubicTo(x1, y1, x2, y2, x, y);
          currentX = x;
          currentY = y;
        }
        break;

      case 'Z':
      case 'z':
        path.close();
        currentX = startX;
        currentY = startY;
        break;

      default:
        // Skip unknown token
        if (!isCommand) i++;
        break;
    }
  }

  return path;
}

bool _isAlpha(String s) {
  if (s.isEmpty) return false;
  final code = s.codeUnitAt(0);
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

List<String> _tokenizeSvgPath(String d) {
  final tokens = <String>[];
  final sb = StringBuffer();

  for (int i = 0; i < d.length; i++) {
    final char = d[i];

    if (_isAlpha(char)) {
      if (sb.isNotEmpty) {
        tokens.add(sb.toString());
        sb.clear();
      }
      tokens.add(char);
    } else if (char == ' ' || char == ',' || char == '\t' || char == '\n' || char == '\r') {
      if (sb.isNotEmpty) {
        tokens.add(sb.toString());
        sb.clear();
      }
    } else if (char == '-') {
      // If minus sign appears within a number (e.g. 10-20 or 1e-5), start a new token unless preceded by 'e' or 'E'
      if (sb.isNotEmpty) {
        final lastChar = sb.toString()[sb.length - 1];
        if (lastChar != 'e' && lastChar != 'E') {
          tokens.add(sb.toString());
          sb.clear();
        }
      }
      sb.write(char);
    } else {
      sb.write(char);
    }
  }

  if (sb.isNotEmpty) {
    tokens.add(sb.toString());
  }

  return tokens;
}
