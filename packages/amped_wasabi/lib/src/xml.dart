/// A forgiving XML reader for Wasabi skin files.
///
/// Skin XML is rarely well formed: included files are fragments with many
/// root elements, comments are sloppy (`<!-- ... --> -->`), entities go
/// unescaped and attribute case varies (`downImage` / `downimage`). Like the
/// original's parser, this one reads elements and attributes and ignores what
/// it does not understand instead of failing. Tag and attribute names are
/// lower-cased, as Wasabi compares them case-insensitively.
library;

/// An element of a skin XML file.
class XmlNode {
  XmlNode(this.tag, [Map<String, String>? attributes, List<XmlNode>? children])
    : attributes = attributes ?? {},
      children = children ?? [];

  /// The lower-cased element name.
  final String tag;

  /// The attributes, keyed by lower-cased name, values entity-decoded.
  final Map<String, String> attributes;

  final List<XmlNode> children;

  /// The attribute [name] (lower case), or null.
  String? operator [](String name) => attributes[name];

  @override
  String toString() =>
      "<$tag ${attributes.entries.map((e) => '${e.key}="${e.value}"').join(" ")}>";
}

/// Parses [source] into the list of its top-level elements.
List<XmlNode> parseXmlFragment(String source) {
  final root = XmlNode("#root");
  final stack = <XmlNode>[root];
  var i = 0;
  final n = source.length;
  while (i < n) {
    final lt = source.indexOf("<", i);
    if (lt < 0) break;
    i = lt + 1;
    if (i >= n) break;
    if (source.startsWith("!--", i)) {
      final end = source.indexOf("-->", i + 3);
      i = end < 0 ? n : end + 3;
      continue;
    }
    if (source.startsWith("![CDATA[", i)) {
      final end = source.indexOf("]]>", i);
      i = end < 0 ? n : end + 3;
      continue;
    }
    final c = source.codeUnitAt(i);
    if (c == 0x3F /* ? */ || c == 0x21 /* ! */ ) {
      final end = source.indexOf(">", i);
      i = end < 0 ? n : end + 1;
      continue;
    }
    if (c == 0x2F /* / */ ) {
      final end = source.indexOf(">", i);
      final name = source
          .substring(i + 1, end < 0 ? n : end)
          .trim()
          .toLowerCase();
      i = end < 0 ? n : end + 1;
      // Close up to the matching element; a stray end tag is ignored.
      for (var d = stack.length - 1; d > 0; d--) {
        if (stack[d].tag == name) {
          stack.length = d;
          break;
        }
      }
      continue;
    }
    // Start tag.
    var j = i;
    while (j < n &&
        !_isSpace(source.codeUnitAt(j)) &&
        source[j] != ">" &&
        source[j] != "/") {
      j++;
    }
    if (j == i) continue;
    final node = XmlNode(source.substring(i, j).toLowerCase());
    i = j;
    var selfClosing = false;
    while (i < n) {
      while (i < n && _isSpace(source.codeUnitAt(i))) {
        i++;
      }
      if (i >= n) break;
      final ch = source[i];
      if (ch == ">") {
        i++;
        break;
      }
      if (ch == "/") {
        i++;
        if (i < n && source[i] == ">") {
          selfClosing = true;
          i++;
          break;
        }
        continue;
      }
      var k = i;
      while (k < n &&
          !_isSpace(source.codeUnitAt(k)) &&
          source[k] != "=" &&
          source[k] != ">" &&
          source[k] != "/") {
        k++;
      }
      final name = source.substring(i, k).toLowerCase();
      i = k;
      while (i < n && _isSpace(source.codeUnitAt(i))) {
        i++;
      }
      var value = "";
      if (i < n && source[i] == "=") {
        i++;
        while (i < n && _isSpace(source.codeUnitAt(i))) {
          i++;
        }
        if (i < n && (source[i] == '"' || source[i] == "'")) {
          final quote = source[i];
          final end = source.indexOf(quote, i + 1);
          value = source.substring(i + 1, end < 0 ? n : end);
          i = end < 0 ? n : end + 1;
        } else {
          var e = i;
          while (e < n && !_isSpace(source.codeUnitAt(e)) && source[e] != ">") {
            e++;
          }
          value = source.substring(i, e);
          i = e;
        }
      }
      if (name.isNotEmpty) {
        node.attributes[name] = _decode(value);
        // A layer's `regionop` is its `sysregion` (Layer's xml param): skins
        // like Compact-SE cut their corners out with it.
        if (name == "regionop") {
          node.attributes.putIfAbsent("sysregion", () => _decode(value));
        }
      }
    }
    stack.last.children.add(node);
    if (!selfClosing) stack.add(node);
  }
  return root.children;
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

String _decode(String value) {
  if (!value.contains("&")) return value;
  return value.replaceAllMapped(
    RegExp(r"&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos);"),
    (m) {
      final entity = m[1]!;
      switch (entity) {
        case "amp":
          return "&";
        case "lt":
          return "<";
        case "gt":
          return ">";
        case "quot":
          return '"';
        case "apos":
          return "'";
      }
      final code = entity.startsWith("#x")
          ? int.tryParse(entity.substring(2), radix: 16)
          : int.tryParse(entity.substring(1));
      return code == null ? m[0]! : String.fromCharCode(code);
    },
  );
}
