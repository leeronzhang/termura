/**
 * Termura WebRenderer — receives chunk data from Swift via evaluateJavaScript,
 * renders Markdown with syntax highlighting, and manages incremental DOM updates.
 */
(function () {
  "use strict";

  var contentEl = document.getElementById("content");

  // Initialize markdown-it with highlight.js integration
  var md = window.markdownit({
    html: false,
    linkify: true,
    typographer: false,
    highlight: function (str, lang) {
      if (lang && hljs.getLanguage(lang)) {
        try {
          return hljs.highlight(str, { language: lang }).value;
        } catch (_) {
          // Fall through to default
        }
      }
      // Auto-detect for unlabeled code blocks
      try {
        return hljs.highlightAuto(str).value;
      } catch (_) {
        return "";
      }
    },
  });

  // Enable KaTeX rendering for $...$ and $$...$$ blocks.
  if (window.markdownitKatex) {
    try {
      md.use(window.markdownitKatex);
    } catch (e) {
      console.error("Failed to enable markdown-it-katex:", e);
    }
  }

  // Enable footnotes: [^1] ... [^1]: content
  if (window.markdownitFootnote) {
    try {
      md.use(window.markdownitFootnote);
    } catch (e) {
      console.error("Failed to enable markdown-it-footnote:", e);
    }
  }

  // Enable superscript: ^text^
  if (window.markdownitSup) {
    try {
      md.use(window.markdownitSup);
    } catch (e) {
      console.error("Failed to enable markdown-it-sup:", e);
    }
  }

  // Enable subscript: ~text~
  if (window.markdownitSub) {
    try {
      md.use(window.markdownitSub);
    } catch (e) {
      console.error("Failed to enable markdown-it-sub:", e);
    }
  }

  // Enable backlinks: [[note-name]] or [[note-name|display text]]
  if (window.markdownitBacklink) {
    try {
      md.use(window.markdownitBacklink);
    } catch (e) {
      console.error("Failed to enable markdown-it-backlink:", e);
    }
  }

  // Enable highlight / mark: ==text== → <mark>text</mark> (loaded from markdown-it-extras.js)
  if (window.markdownitMark) {
    try {
      md.use(window.markdownitMark);
    } catch (e) {
      console.error("Failed to enable markdown-it-mark:", e);
    }
  }

  // Enable GFM-style task lists (loaded from markdown-it-extras.js)
  if (window.markdownitTaskLists) {
    try {
      md.use(window.markdownitTaskLists);
    } catch (e) {
      console.error("Failed to enable markdown-it-task-lists:", e);
    }
  }

  /** Mermaid theme — beautiful-mermaid built-in github-dark with transparent bg. */
  var mermaidTheme = window.beautifulMermaid && window.beautifulMermaid.THEMES
    ? Object.assign({}, window.beautifulMermaid.THEMES["github-dark"], { transparent: true })
    : { bg: "#0d1117", fg: "#e6edf3", line: "#3d444d", accent: "#4493f8", muted: "#9198a1", transparent: true };

  /**
   * Normalize mermaid edge syntax for beautiful-mermaid which requires spaces
   * around arrow operators and edge labels.
   *
   * beautiful-mermaid expects:  A -->|label| B   or   A --> B
   * Standard mermaid allows:    A-->|label|B     or   A-->B
   *
   * Rules:
   *  1. Space before arrow operator:        A-->  => A -->
   *  2. Arrow touches label if present:     -->|  => -->|  (no change)
   *  3. Arrow followed by non-|, add space: -->B  => --> B
   *  4. After |label|, space before node:   |x|B  => |x| B
   */
  function normalizeMermaidEdges(code) {
    var arrowPattern = /(-{2,}>|={2,}>|-\.+->>?|-{3,}|={3,}|-\.-)/;
    return code.split("\n").map(function (line) {
      var trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("%%") ||
          /^(graph|flowchart|subgraph|end|classDef|class|style|linkStyle|click)\b/.test(trimmed)) {
        return line;
      }
      if (!arrowPattern.test(line)) return line;

      // 1. Space before arrow: non-space followed by arrow
      line = line.replace(/([^\s])(-\.+->>?|={2,}>|-{2,}>|-{3,}|={3,}|-\.-)/g, "$1 $2");
      // 2+3. After arrow: if next char is |, keep touching; otherwise add space
      //      -\.-(?!>) prevents matching the -.- prefix of -.->
      line = line.replace(/(-\.+->>?|={2,}>|-{2,}>|-{3,}|={3,}|-\.-(?!>))([^\s|])/g, "$1 $2");
      // 4. After |label|, add space before next node if missing
      line = line.replace(/(\|[^|]*\|)([^\s])/g, "$1 $2");
      return line;
    }).join("\n");
  }

  /** Detect mermaid diagram types from code content (first non-empty line). */
  var mermaidKeywords = /^(graph|flowchart|sequenceDiagram|classDiagram|stateDiagram|erDiagram|gantt|pie|gitgraph|mindmap|timeline|xychart|block)\b/;

  /** Render mermaid code blocks using beautiful-mermaid synchronous SVG renderer. */
  function renderMermaidBlocks(container) {
    // Match by class OR by content keywords for resilience against
    // fences with invisible characters or missing language tags.
    var allCodes = container.querySelectorAll("pre > code");
    var blocks = [];
    allCodes.forEach(function (code) {
      if (code.classList.contains("language-mermaid")) {
        blocks.push(code);
      } else if (!code.className || code.className === "hljs") {
        var text = code.textContent.trim();
        var firstLine = text.split("\n")[0].trim();
        // Content-based fallback: first line must match a mermaid keyword,
        // block must be short enough (<80 lines) and not contain markdown
        // headings (which indicate a broken fence swallowing page content).
        if (mermaidKeywords.test(firstLine)
            && text.split("\n").length < 80
            && !/^#{1,6}\s/m.test(text)) {
          blocks.push(code);
        }
      }
    });
    if (blocks.length === 0) return;
    if (!window.beautifulMermaid || !window.beautifulMermaid.renderMermaidSVG) return;
    var opts = mermaidTheme;
    blocks.forEach(function (block) {
      var pre = block.parentElement;
      if (!pre || !pre.parentNode) return;
      var code = normalizeMermaidEdges(block.textContent);
      try {
        var svg = window.beautifulMermaid.renderMermaidSVG(code, opts);
        // Strip Google Fonts @import — WKWebView may block external requests.
        // The SVG already has system-ui fallback in its font-family.
        svg = svg.replace(/@import url\([^)]+\);\s*/g, "");
        var div = document.createElement("div");
        div.className = "mermaid";
        div.innerHTML = svg;
        pre.parentNode.replaceChild(div, pre);
      } catch (e) {
        // Show error inline so it's visible during development.
        var errDiv = document.createElement("div");
        errDiv.className = "mermaid-error";
        errDiv.textContent = "Mermaid error: " + e.message;
        if (pre && pre.parentNode) {
          pre.parentNode.insertBefore(errDiv, pre.nextSibling);
        }
        console.error("Failed to render mermaid diagram:", e);
      }
    });
  }

  /** Escape HTML for safe rendering of references list. */
  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  /**
   * Append a single output chunk to the content area.
   * @param {string} jsonString - JSON-encoded chunk data from Swift
   *   { command: string, lines: [string], contentType: string,
   *     language: string?, exitCode: number? }
   */
  function appendChunk(jsonString) {
    var chunk;
    try {
      chunk = JSON.parse(jsonString);
    } catch (e) {
      console.error("Failed to parse chunk JSON:", e);
      return;
    }

    var wrapper = document.createElement("div");
    wrapper.className = "chunk-block";

    // Separator between chunks (skip for the first one)
    if (contentEl.children.length > 0) {
      var sep = document.createElement("div");
      sep.className = "chunk-separator";
      wrapper.appendChild(sep);
    }

    // Command header (if present)
    if (chunk.command && chunk.command.length > 0) {
      var cmdEl = document.createElement("div");
      cmdEl.className = "chunk-command";
      cmdEl.textContent = "$ " + chunk.command;
      wrapper.appendChild(cmdEl);
    }

    // Render content based on type
    var outputDiv = document.createElement("div");
    var text = (chunk.lines || []).join("\n");

    if (
      chunk.contentType === "markdown" ||
      chunk.contentType === "text" ||
      chunk.contentType === "code"
    ) {
      outputDiv.innerHTML = md.render(text);
    } else if (chunk.contentType === "error") {
      outputDiv.className = "chunk-error";
      outputDiv.innerHTML = md.render(text);
    } else {
      // commandOutput, toolCall, diff — render as preformatted
      var pre = document.createElement("pre");
      var code = document.createElement("code");
      code.textContent = text;
      if (chunk.language) {
        code.className = "language-" + chunk.language;
        hljs.highlightElement(code);
      }
      pre.appendChild(code);
      outputDiv.appendChild(pre);
    }

    wrapper.appendChild(outputDiv);
    contentEl.appendChild(wrapper);
    scrollToBottom();
  }

  /** Remove all rendered content. */
  function clear() {
    contentEl.innerHTML = "";
  }

  /**
   * Replace the :root CSS custom properties with new theme values.
   * @param {string} cssText - Complete `:root { ... }` block from ThemeCSSGenerator
   */
  function updateTheme(cssText) {
    var styleId = "termura-theme-vars";
    var existing = document.getElementById(styleId);
    if (existing) {
      existing.textContent = cssText;
    } else {
      var style = document.createElement("style");
      style.id = styleId;
      style.textContent = cssText;
      document.head.appendChild(style);
    }
    // Mermaid diagrams will pick up new colors on the next renderMarkdown() call.
  }

  /** Scroll the content area to the bottom. */
  function scrollToBottom() {
    window.scrollTo(0, document.body.scrollHeight);
  }

  /**
   * Replace the entire content with rendered markdown.
   * Used by NoteRenderedView for full-document rendering (not chunk append).
   * @param {string} markdownText - Raw markdown source
   * @param {string} referencesJSON - JSON-encoded array of citation strings
   */
  function renderMarkdown(markdownText, referencesJSON, backlinksJSON) {
    // Normalize markdown source before parsing:
    // 1. Strip U+FFFC (Object Replacement Character) — breaks code fences
    //    when pasted from rich-text sources or system clipboard.
    // 2. Auto-tag bare fences whose next line starts with a mermaid keyword,
    //    e.g. "```\ngraph TD" → "```mermaid\ngraph TD".
    var src = (markdownText || "")
      .replace(/\uFFFC/g, "")
      .replace(/^(`{3,})\s*\n((?:graph|flowchart|sequenceDiagram|classDiagram|stateDiagram|erDiagram|gantt|pie|gitgraph|mindmap|timeline|xychart|block)\b)/gm, "$1mermaid\n$2");
    try {
      contentEl.innerHTML = md.render(src);
    } catch (e) {
      console.error("Failed to render markdown:", e);
      contentEl.textContent = String(markdownText || "");
      return;
    }

    // Mermaid post-process: render code.language-mermaid blocks to SVG
    renderMermaidBlocks(contentEl);

    // References section: append at the bottom if any.
    var refs = [];
    try {
      refs = JSON.parse(referencesJSON || "[]");
    } catch (_) {
      refs = [];
    }
    if (Array.isArray(refs) && refs.length > 0) {
      var section = document.createElement("section");
      section.className = "references";
      var heading = "<h2>References</h2>";
      var items = refs.map(function (r) {
        return "<li>" + escapeHtml(r) + "</li>";
      }).join("");
      section.innerHTML = heading + "<ol>" + items + "</ol>";
      contentEl.appendChild(section);
    }

    // Backlinks section: notes that link to this one via [[...]].
    var backlinks = [];
    try { backlinks = JSON.parse(backlinksJSON || "[]"); } catch (_) { backlinks = []; }
    if (Array.isArray(backlinks) && backlinks.length > 0) {
      var blSection = document.createElement("section");
      blSection.className = "backlinks";
      var blItems = backlinks.map(function (title) {
        return '<li><a href="termura-note://open?title='
          + encodeURIComponent(title)
          + '" class="backlink">' + escapeHtml(title) + '</a></li>';
      }).join("");
      blSection.innerHTML = "<h2>Backlinks</h2><ul>" + blItems + "</ul>";
      contentEl.appendChild(blSection);
    }

    window.scrollTo(0, 0);
  }

  // Expose the renderer API to Swift's evaluateJavaScript
  window.termuraRenderer = {
    appendChunk: appendChunk,
    clear: clear,
    updateTheme: updateTheme,
    scrollToBottom: scrollToBottom,
    renderMarkdown: renderMarkdown,
  };
})();
