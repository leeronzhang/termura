/**
 * markdown-it plugin for backlink syntax: [[note-name]] or [[note-name|display text]]
 * Renders as <a href="termura-note://open?title=ENCODED" class="backlink">display</a>
 */
(function () {
  "use strict";

  function backlinkPlugin(md) {
    md.inline.ruler.before("emphasis", "backlink", function (state, silent) {
      var start = state.pos;
      var max = state.posMax;

      // Must start with [[
      if (
        start + 3 >= max ||
        state.src.charCodeAt(start) !== 0x5b ||
        state.src.charCodeAt(start + 1) !== 0x5b
      ) {
        return false;
      }

      // Find closing ]]
      var end = state.src.indexOf("]]", start + 2);
      if (end === -1 || end > max) return false;

      var content = state.src.slice(start + 2, end);
      if (!content) return false;

      if (!silent) {
        var parts = content.split("|");
        var target = parts[0].trim();
        var display = parts.length > 1 ? parts[1].trim() : target;
        var encoded = encodeURIComponent(target);
        var href = "termura-note://open?title=" + encoded;

        var token = state.push("html_inline", "", 0);
        token.content =
          '<a href="' + href + '" class="backlink">' + escapeHtml(display) + "</a>";
      }

      state.pos = end + 2;
      return true;
    });
  }

  function escapeHtml(str) {
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  window.markdownitBacklink = backlinkPlugin;
})();
