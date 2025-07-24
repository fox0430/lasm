import std/[unittest, json, options]

import ../src/lasmpkg/protocol/types
import ../src/lasmpkg/protocol/enums

suite "semantic tokens protocol types tests":
  test "SemanticTokensParams initialization":
    let textDoc = TextDocumentIdentifier()
    textDoc.uri = "file:///test.nim"

    let params = SemanticTokensParams()
    params.textDocument = textDoc

    check params.textDocument.uri == "file:///test.nim"

  test "SemanticTokensDeltaParams initialization":
    let textDoc = TextDocumentIdentifier()
    textDoc.uri = "file:///test.nim"

    let params = SemanticTokensDeltaParams()
    params.textDocument = textDoc
    params.previousResultId = "result-123"

    check params.textDocument.uri == "file:///test.nim"
    check params.previousResultId == "result-123"

  test "SemanticTokensRangeParams initialization":
    let textDoc = TextDocumentIdentifier()
    textDoc.uri = "file:///test.nim"

    let range = Range(
      start: Position(line: 0, character: 0), `end`: Position(line: 5, character: 10)
    )

    let params = SemanticTokensRangeParams()
    params.textDocument = textDoc
    params.range = range

    check params.textDocument.uri == "file:///test.nim"
    check params.range.start.line == 0
    check params.range.start.character == 0
    check params.range.`end`.line == 5
    check params.range.`end`.character == 10

  test "SemanticTokens initialization":
    let tokens = SemanticTokens()
    tokens.resultId = some("result-456")
    tokens.data = @[uinteger(0), uinteger(0), uinteger(8), uinteger(14), uinteger(0)]

    check tokens.resultId.get == "result-456"
    check tokens.data.len == 5
    check tokens.data[0] == 0
    check tokens.data[3] == 14

  test "SemanticTokens with empty result":
    let tokens = SemanticTokens()
    tokens.resultId = none(string)
    tokens.data = @[]

    check tokens.resultId.isNone
    check tokens.data.len == 0

  test "SemanticTokensDelta initialization":
    let edit = SemanticTokensEdit()
    edit.start = uinteger(5)
    edit.deleteCount = uinteger(2)
    edit.data = some(@[uinteger(1), uinteger(2), uinteger(3)])

    let delta = SemanticTokensDelta()
    delta.resultId = some("delta-result-789")
    delta.edits = @[edit]

    check delta.resultId.get == "delta-result-789"
    check delta.edits.len == 1
    check delta.edits[0].start == 5
    check delta.edits[0].deleteCount == 2
    check delta.edits[0].data.get.len == 3
    check delta.edits[0].data.get[1] == 2

  test "SemanticTokensEdit with no data":
    let edit = SemanticTokensEdit()
    edit.start = uinteger(10)
    edit.deleteCount = uinteger(5)
    edit.data = none(seq[uinteger])

    check edit.start == 10
    check edit.deleteCount == 5
    check edit.data.isNone

  test "SemanticTokensLegend initialization":
    let legend = SemanticTokensLegend()
    legend.tokenTypes =
      @[
        "namespace", "type", "class", "enum", "interface", "struct", "typeParameter",
        "parameter", "variable", "property", "enumMember", "event", "function",
        "method", "macro", "keyword", "modifier", "comment", "string", "number",
        "regexp", "operator", "decorator",
      ]
    legend.tokenModifiers =
      @[
        "declaration", "definition", "readonly", "static", "deprecated", "abstract",
        "async", "modification", "documentation", "defaultLibrary",
      ]

    check legend.tokenTypes.len == 23
    check legend.tokenModifiers.len == 10
    check "function" in legend.tokenTypes
    check "declaration" in legend.tokenModifiers

  test "SemanticTokensOptions initialization":
    let legend = SemanticTokensLegend()
    legend.tokenTypes = @["keyword", "function", "variable"]
    legend.tokenModifiers = @["declaration", "definition"]

    let options = SemanticTokensOptions()
    options.legend = legend
    options.range = some(true)
    options.full = some(%*{"delta": false})

    check options.legend.tokenTypes.len == 3
    check options.legend.tokenModifiers.len == 2
    check options.range.get == true
    check options.full.get.hasKey("delta")
    check options.full.get["delta"].getBool() == false

  test "SemanticTokensOptions with minimal configuration":
    let legend = SemanticTokensLegend()
    legend.tokenTypes = @["keyword"]
    legend.tokenModifiers = @["declaration"]

    let options = SemanticTokensOptions()
    options.legend = legend
    options.range = some(false)
    options.full = some(%true)

    check options.legend.tokenTypes.len == 1
    check options.legend.tokenModifiers.len == 1
    check options.range.get == false
    check options.full.get.getBool() == true

  test "SemanticTokenTypes enum values":
    check ord(SemanticTokenTypes.Namespace) == 0
    check ord(SemanticTokenTypes.Type) == 1
    check ord(SemanticTokenTypes.Class) == 2
    check ord(SemanticTokenTypes.Function) == 12
    check ord(SemanticTokenTypes.Keyword) == 15
    check ord(SemanticTokenTypes.String) == 18
    check ord(SemanticTokenTypes.Decorator) == 22

  test "SemanticTokenModifiers enum values":
    check ord(SemanticTokenModifiers.Declaration) == 0
    check ord(SemanticTokenModifiers.Definition) == 1
    check ord(SemanticTokenModifiers.Readonly) == 2
    check ord(SemanticTokenModifiers.Static) == 3
    check ord(SemanticTokenModifiers.Deprecated) == 4
    check ord(SemanticTokenModifiers.DefaultLibrary) == 9

  test "Complex semantic tokens data structure":
    # Test a realistic semantic tokens data array
    let tokens = SemanticTokens()
    tokens.resultId = some("complex-result")
    tokens.data =
      @[
        # Token 1: "function" keyword at line 0, col 0, length 8, type=keyword, modifiers=none
        uinteger(0),
        uinteger(0),
        uinteger(8),
        uinteger(15),
        uinteger(0),
        # Token 2: function name at same line, col 9, length 4, type=function, modifiers=declaration
        uinteger(0),
        uinteger(9),
        uinteger(4),
        uinteger(12),
        uinteger(1),
        # Token 3: parameter at next line, col 2, length 5, type=parameter, modifiers=none
        uinteger(1),
        uinteger(2),
        uinteger(5),
        uinteger(7),
        uinteger(0),
        # Token 4: type annotation at same line, col 8, length 6, type=type, modifiers=none
        uinteger(0),
        uinteger(8),
        uinteger(6),
        uinteger(1),
        uinteger(0),
      ]

    check tokens.data.len == 20 # 4 tokens * 5 values each
    check tokens.resultId.get == "complex-result"

    # Verify token structure
    # First token (function keyword)
    check tokens.data[0] == 0 # deltaLine
    check tokens.data[1] == 0 # deltaStart
    check tokens.data[2] == 8 # length
    check tokens.data[3] == 15 # tokenType (keyword)
    check tokens.data[4] == 0 # tokenModifiers

    # Second token (function name)
    check tokens.data[5] == 0 # deltaLine (same line)
    check tokens.data[6] == 9 # deltaStart
    check tokens.data[7] == 4 # length
    check tokens.data[8] == 12 # tokenType (function)
    check tokens.data[9] == 1 # tokenModifiers (declaration)

suite "JSON serialization tests":
  test "SemanticTokens JSON serialization":
    let tokens = SemanticTokens()
    tokens.resultId = some("json-test")
    tokens.data = @[uinteger(0), uinteger(0), uinteger(5), uinteger(15), uinteger(0)]

    let jsonTokens = %tokens

    check jsonTokens.hasKey("resultId")
    check jsonTokens.hasKey("data")
    check jsonTokens["resultId"].getStr() == "json-test"
    check jsonTokens["data"].len == 5
    check jsonTokens["data"][0].getInt() == 0
    check jsonTokens["data"][3].getInt() == 15

  test "SemanticTokensLegend JSON serialization":
    let legend = SemanticTokensLegend()
    legend.tokenTypes = @["keyword", "function"]
    legend.tokenModifiers = @["declaration"]

    let jsonLegend = %legend

    check jsonLegend.hasKey("tokenTypes")
    check jsonLegend.hasKey("tokenModifiers")
    check jsonLegend["tokenTypes"].len == 2
    check jsonLegend["tokenTypes"][0].getStr() == "keyword"
    check jsonLegend["tokenTypes"][1].getStr() == "function"
    check jsonLegend["tokenModifiers"].len == 1
    check jsonLegend["tokenModifiers"][0].getStr() == "declaration"
