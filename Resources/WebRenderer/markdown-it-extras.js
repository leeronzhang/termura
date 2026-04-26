/**
 * Extra markdown-it plugins bundled together:
 * - mark (==highlight==)
 * - task-lists (GFM checkboxes)
 *
 * Exposes window.markdownitMark and window.markdownitTaskLists.
 */
(function () {
  "use strict";

  // ==text== → <mark>text</mark>
  function markPlugin(mdInstance) {
    function tokenize(state) {
      var start = state.pos;
      var marker = state.src.charCodeAt(start);
      if (marker !== 0x3d /* = */) return false;
      if (state.src.charCodeAt(start + 1) !== 0x3d) return false;
      var scanned = state.scanDelims(start, true);
      if (scanned.length < 2) return false;
      var token;
      if (scanned.length % 2) {
        token = state.push("text", "", 0);
        token.content = "=";
        scanned.length--;
      }
      for (var i = 0; i < scanned.length; i += 2) {
        token = state.push("mark_open", "mark", 1);
        token.markup = "==";
        state.delimiters.push({
          marker: marker,
          length: 0,
          token: state.tokens.length - 1,
          end: -1,
          open: scanned.can_open,
          close: scanned.can_close,
        });
      }
      state.pos += scanned.length;
      return true;
    }

    function postProcess(state, delimiters) {
      var loneMarkers = [];
      for (var i = 0; i < delimiters.length; i++) {
        var startDelim = delimiters[i];
        if (startDelim.marker !== 0x3d) continue;
        if (startDelim.end === -1) continue;
        var endDelim = delimiters[startDelim.end];
        var tokenO = state.tokens[startDelim.token];
        var tokenC = state.tokens[endDelim.token];
        tokenO.type = "mark_open";
        tokenO.tag = "mark";
        tokenO.nesting = 1;
        tokenO.markup = "==";
        tokenO.content = "";
        tokenC.type = "mark_close";
        tokenC.tag = "mark";
        tokenC.nesting = -1;
        tokenC.markup = "==";
        tokenC.content = "";
        if (
          state.tokens[endDelim.token - 1].type === "text" &&
          state.tokens[endDelim.token - 1].content === "="
        ) {
          loneMarkers.push(endDelim.token - 1);
        }
      }
      while (loneMarkers.length) {
        var idx = loneMarkers.pop();
        var j = idx + 1;
        while (j < state.tokens.length && state.tokens[j].type === "mark_close") j++;
        if (j !== idx + 1) {
          var tok = state.tokens[j - 1];
          state.tokens[j - 1] = state.tokens[idx];
          state.tokens[idx] = tok;
        }
      }
    }

    mdInstance.inline.ruler.before("emphasis", "mark", tokenize);
    mdInstance.inline.ruler2.before("emphasis", "mark", function (state) {
      postProcess(state, state.delimiters);
      if (state.tokens_meta) {
        for (var k = 0; k < state.tokens_meta.length; k++) {
          if (state.tokens_meta[k] && state.tokens_meta[k].delimiters) {
            postProcess(state, state.tokens_meta[k].delimiters);
          }
        }
      }
    });
  }

  // GFM task lists: - [ ] unchecked, - [x] checked → checkboxes
  function taskListsPlugin(mdInstance) {
    mdInstance.core.ruler.after("inline", "task-lists", function (state) {
      var tokens = state.tokens;
      for (var i = 0; i < tokens.length; i++) {
        if (tokens[i].type !== "inline" || !tokens[i].children) continue;
        if (i < 1 || tokens[i - 1].type !== "paragraph_open") continue;
        if (i < 2 || tokens[i - 2].type !== "list_item_open") continue;
        var children = tokens[i].children;
        if (children.length === 0 || children[0].type !== "text") continue;
        var text = children[0].content;
        var checked;
        if (text.indexOf("[ ] ") === 0) {
          checked = false;
        } else if (text.indexOf("[x] ") === 0 || text.indexOf("[X] ") === 0) {
          checked = true;
        } else {
          continue;
        }
        tokens[i - 2].attrJoin("class", "task-list-item");
        var checkbox = new state.Token("html_inline", "", 0);
        checkbox.content =
          '<input type="checkbox" disabled' + (checked ? " checked" : "") + "> ";
        children[0].content = text.slice(4);
        children.unshift(checkbox);
      }
    });
  }

  window.markdownitMark = markPlugin;
  window.markdownitTaskLists = taskListsPlugin;
})();
