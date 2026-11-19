import Foundation
import SkreenrekControl
import SkreenrekTesting
@testable import SkreenrekMCP
import Testing

/// The `tools/list` snapshot: tool names, descriptions and schemas change only on purpose. To update it, read the
/// new output in the failure and paste it below.
@Suite struct ToolsListGoldenTests {
    static func pretty(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test func toolsListMatchesTheGolden() async throws {
        let server = MCPServer(
            environment: MCPEnvironment(
                connector: .init(
                    socketPath: URL(fileURLWithPath: "/nonexistent/c.sock"), executablePath: "/usr/local/bin/skreenrek",
                    launcher: FakeAppLauncher(), clock: ManualClock()),
                home: URL(fileURLWithPath: "/"), currentDirectory: URL(fileURLWithPath: "/"), log: { _ in }))
        let line = try #require(await server.handle(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)))
        let result = try #require(try JSONValue.parse(line)["result"])
        let actual = try Self.pretty(result)
        #expect(actual == Self.golden, "New tools/list:\n\(actual)")
    }

    @Test func everyToolIsPrefixedHasOneSentenceAndNoForbiddenWords() throws {
        #expect(MCPTool.allCases.count == 7)
        for tool in MCPTool.allCases {
            #expect(tool.rawValue.hasPrefix("skreenrek_"))
            let summary = tool.summary
            #expect(summary.hasSuffix("."))
            #expect(!summary.contains(". "), "One sentence: \(summary)")
            let schema = try tool.inputSchema.jsonString()
            for word in ["Raph", "CTO"] {
                #expect(!summary.contains(word))
                #expect(!schema.contains(word))
            }
        }
    }

    static let golden = """
        {
          "tools" : [
            {
              "description" : "List the macOS windows Skreenrek can record, with their IDs, apps, titles and sizes in pixels.",
              "inputSchema" : {
                "additionalProperties" : false,
                "properties" : {
                  "app" : {
                    "description" : "Only windows of this app (name or bundle ID).",
                    "type" : "string"
                  }
                },
                "type" : "object"
              },
              "name" : "skreenrek_list_windows"
            },
            {
              "description" : "Size a window for an exact clip size (a preset like 1080p, or pixels) and read the size back to confirm it.",
              "inputSchema" : {
                "additionalProperties" : false,
                "properties" : {
                  "app" : {
                    "description" : "The app whose window to resize (name or bundle ID).",
                    "type" : "string"
                  },
                  "height" : {
                    "description" : "The clip height in pixels (with width, instead of size).",
                    "minimum" : 1,
                    "type" : "integer"
                  },
                  "size" : {
                    "description" : "The clip size: 720p, 1080p, 1440p, 4k, square, portrait, or WxH in pixels (WxHpx also works). Skreenrek sizes the window to fit its display and records the exact clip size.",
                    "type" : "string"
                  },
                  "title" : {
                    "description" : "With app: a part of the window title.",
                    "type" : "string"
                  },
                  "width" : {
                    "description" : "The clip width in pixels (with height, instead of size).",
                    "minimum" : 1,
                    "type" : "integer"
                  },
                  "windowId" : {
                    "description" : "A window ID from skreenrek_list_windows.",
                    "minimum" : 0,
                    "type" : "integer"
                  }
                },
                "type" : "object"
              },
              "name" : "skreenrek_resize_window"
            },
            {
              "description" : "Start recording a window or screen region at a constant 30 or 60 fps, sizing the window for an exact clip size first when size, or width and height, is given.",
              "inputSchema" : {
                "additionalProperties" : false,
                "properties" : {
                  "allowInexact" : {
                    "default" : false,
                    "description" : "Record even when the size read back isn't exact.",
                    "type" : "boolean"
                  },
                  "app" : {
                    "description" : "The app whose window to record (name or bundle ID).",
                    "type" : "string"
                  },
                  "assetsDir" : {
                    "description" : "Also copy the clip into this HyperFrames assets folder and point the snippet at it.",
                    "type" : "string"
                  },
                  "bitrateMbps" : {
                    "maximum" : 200,
                    "minimum" : 1,
                    "type" : "number"
                  },
                  "codec" : {
                    "default" : "h264",
                    "enum" : [
                      "h264",
                      "hevc",
                      "prores"
                    ],
                    "type" : "string"
                  },
                  "cursor" : {
                    "default" : true,
                    "description" : "Show the cursor in the video.",
                    "type" : "boolean"
                  },
                  "displayId" : {
                    "description" : "With region: the display (default: the main display).",
                    "minimum" : 0,
                    "type" : "integer"
                  },
                  "durationSeconds" : {
                    "description" : "Stop on its own after this many seconds.",
                    "exclusiveMinimum" : 0,
                    "type" : "number"
                  },
                  "events" : {
                    "default" : true,
                    "description" : "Write events.json.",
                    "type" : "boolean"
                  },
                  "format" : {
                    "default" : "mp4",
                    "enum" : [
                      "mp4",
                      "mov"
                    ],
                    "type" : "string"
                  },
                  "fps" : {
                    "description" : "Frames per second (default from Settings, otherwise 60).",
                    "enum" : [
                      30,
                      60
                    ],
                    "type" : "integer"
                  },
                  "height" : {
                    "description" : "Resize the window to this height in pixels first (with width).",
                    "minimum" : 1,
                    "type" : "integer"
                  },
                  "hud" : {
                    "default" : true,
                    "description" : "Show the recording indicator and the Saved confirmation. With false, neither shows; the clip's paths come back in skreenrek_stop_recording's result.",
                    "type" : "boolean"
                  },
                  "outDir" : {
                    "description" : "The folder for the clip folder (default: ~/Movies/Skreenrek or Settings).",
                    "type" : "string"
                  },
                  "quality" : {
                    "default" : "high",
                    "enum" : [
                      "low",
                      "medium",
                      "high",
                      "max"
                    ],
                    "type" : "string"
                  },
                  "region" : {
                    "additionalProperties" : false,
                    "description" : "Record this screen region instead of a window, in pixels, top-left origin.",
                    "properties" : {
                      "height" : {
                        "description" : "The height in pixels.",
                        "minimum" : 1,
                        "type" : "integer"
                      },
                      "width" : {
                        "description" : "The width in pixels.",
                        "minimum" : 1,
                        "type" : "integer"
                      },
                      "x" : {
                        "description" : "Left edge in pixels of the display.",
                        "type" : "integer"
                      },
                      "y" : {
                        "description" : "Top edge in pixels of the display.",
                        "type" : "integer"
                      }
                    },
                    "required" : [
                      "x",
                      "y",
                      "width",
                      "height"
                    ],
                    "type" : "object"
                  },
                  "size" : {
                    "description" : "The clip size: 720p, 1080p, 1440p, 4k, square, portrait, or WxH in pixels (WxHpx also works). Skreenrek sizes the window to fit its display and records the exact clip size.",
                    "type" : "string"
                  },
                  "title" : {
                    "description" : "With app: a part of the window title.",
                    "type" : "string"
                  },
                  "width" : {
                    "description" : "Resize the window to this width in pixels first (with height).",
                    "minimum" : 1,
                    "type" : "integer"
                  },
                  "windowId" : {
                    "description" : "A window ID from skreenrek_list_windows.",
                    "minimum" : 0,
                    "type" : "integer"
                  }
                },
                "type" : "object"
              },
              "name" : "skreenrek_start_recording"
            },
            {
              "description" : "Stop the recording and return the paths of the clip, events.json and hyperframes.html, plus the HyperFrames snippet.",
              "inputSchema" : {
                "additionalProperties" : false,
                "properties" : {
        
                },
                "type" : "object"
              },
              "name" : "skreenrek_stop_recording"
            },
            {
              "description" : "Tell whether Skreenrek is idle, armed, recording, writing or in error, with the current recording and the last clip.",
              "inputSchema" : {
                "additionalProperties" : false,
                "properties" : {
        
                },
                "type" : "object"
              },
              "name" : "skreenrek_status"
            },
            {
              "description" : "Stop the recording and delete its clip folder.",
              "inputSchema" : {
                "additionalProperties" : false,
                "properties" : {
        
                },
                "type" : "object"
              },
              "name" : "skreenrek_discard_recording"
            },
            {
              "description" : "Open the window picker on the Mac so a person can choose a window, and return it or { cancelled: true }.",
              "inputSchema" : {
                "additionalProperties" : false,
                "properties" : {
                  "timeoutSeconds" : {
                    "default" : 60,
                    "description" : "How long to wait for the person to pick, in seconds.",
                    "exclusiveMinimum" : 0,
                    "type" : "number"
                  }
                },
                "type" : "object"
              },
              "name" : "skreenrek_pick_window"
            }
          ]
        }
        """
}
