/**
 * Termura Knowledge Graph — D3.js force-directed visualization.
 *
 * Receives graph data from Swift via evaluateJavaScript:
 *   window.termuraGraph.render(jsonString)
 *   window.termuraGraph.updateTheme(cssText)
 *
 * Nodes: note (circle) / tag (diamond).
 * Links: backlink (solid) / tag (dashed).
 * Interactions: drag, zoom/pan, hover tooltip, click to navigate.
 */
(function () {
  "use strict";

  var container = document.getElementById("graph-container");
  var tooltipEl = document.getElementById("tooltip");
  var svg, gRoot, linkGroup, nodeGroup, simulation;

  // Theme colors — updated by updateTheme().
  var colors = {
    bg: "#1e1e1e",
    noteFill: "#5e81f4",
    noteStroke: "#4468d0",
    tagFill: "#75b85b",
    tagStroke: "#5a9442",
    linkBacklink: "rgba(255,255,255,0.25)",
    linkTag: "rgba(255,255,255,0.12)",
    labelColor: "#ccc",
    hoverFill: "#fed04c"
  };

  /** Scale node radius by weight. */
  function nodeRadius(d) {
    var base = d.type === "tag" ? 5 : 7;
    return base + Math.min(d.weight, 20) * 0.8;
  }

  /** Diamond path for tag nodes. */
  function diamondPath(r) {
    return "M 0 " + (-r) + " L " + r + " 0 L 0 " + r + " L " + (-r) + " 0 Z";
  }

  function render(jsonString) {
    var data;
    try { data = JSON.parse(jsonString); } catch (e) {
      console.error("Failed to parse graph JSON:", e);
      return;
    }

    // Clear previous.
    container.innerHTML = "";
    tooltipEl.classList.remove("visible");

    if (!data.nodes || data.nodes.length === 0) {
      var empty = document.createElement("div");
      empty.className = "empty-state";
      empty.textContent = "No notes to visualize.";
      container.appendChild(empty);
      return;
    }

    var width = container.clientWidth || window.innerWidth;
    var height = container.clientHeight || window.innerHeight;

    svg = d3.select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height);

    // Zoom behavior.
    var zoom = d3.zoom()
      .scaleExtent([0.2, 5])
      .on("zoom", function (event) { gRoot.attr("transform", event.transform); });
    svg.call(zoom);

    gRoot = svg.append("g");

    // Build D3 simulation.
    var nodes = data.nodes.map(function (d) { return Object.assign({}, d); });
    var links = data.links.map(function (d) { return Object.assign({}, d); });

    simulation = d3.forceSimulation(nodes)
      .force("link", d3.forceLink(links).id(function (d) { return d.id; }).distance(80))
      .force("charge", d3.forceManyBody().strength(-200))
      .force("center", d3.forceCenter(width / 2, height / 2))
      .force("collision", d3.forceCollide().radius(function (d) { return nodeRadius(d) + 4; }));

    // Links.
    linkGroup = gRoot.append("g").attr("class", "links");
    var linkEls = linkGroup.selectAll("line")
      .data(links).enter().append("line")
      .attr("stroke", function (d) {
        return d.type === "backlink" ? colors.linkBacklink : colors.linkTag;
      })
      .attr("stroke-width", function (d) { return d.type === "backlink" ? 1.5 : 1; })
      .attr("stroke-dasharray", function (d) { return d.type === "tag" ? "4 3" : null; });

    // Node groups.
    nodeGroup = gRoot.append("g").attr("class", "nodes");
    var nodeEls = nodeGroup.selectAll("g")
      .data(nodes).enter().append("g")
      .attr("cursor", "pointer")
      .call(d3.drag()
        .on("start", dragStarted)
        .on("drag", dragged)
        .on("end", dragEnded));

    // Draw shapes.
    nodeEls.each(function (d) {
      var el = d3.select(this);
      var r = nodeRadius(d);
      if (d.type === "tag") {
        el.append("path")
          .attr("d", diamondPath(r))
          .attr("fill", colors.tagFill)
          .attr("stroke", colors.tagStroke)
          .attr("stroke-width", 1.5);
      } else {
        el.append("circle")
          .attr("r", r)
          .attr("fill", colors.noteFill)
          .attr("stroke", colors.noteStroke)
          .attr("stroke-width", 1.5);
      }
    });

    // Labels (only for nodes with enough weight to be readable).
    nodeEls.filter(function (d) { return d.weight >= 2 || d.type === "tag"; })
      .append("text")
      .text(function (d) {
        var label = d.label || "";
        return label.length > 20 ? label.substring(0, 18) + "\u2026" : label;
      })
      .attr("dy", function (d) { return nodeRadius(d) + 12; })
      .attr("text-anchor", "middle")
      .attr("fill", colors.labelColor)
      .attr("font-size", "10px")
      .attr("pointer-events", "none");

    // Hover.
    nodeEls.on("mouseenter", function (event, d) {
      d3.select(this).select("circle, path")
        .transition().duration(120)
        .attr("fill", colors.hoverFill);
      var prefix = d.type === "tag" ? "#" : "";
      tooltipEl.textContent = prefix + d.label + (d.weight > 1 ? " (" + d.weight + ")" : "");
      tooltipEl.classList.add("visible");
    })
    .on("mousemove", function (event) {
      tooltipEl.style.left = (event.pageX + 12) + "px";
      tooltipEl.style.top = (event.pageY - 28) + "px";
    })
    .on("mouseleave", function (event, d) {
      var fill = d.type === "tag" ? colors.tagFill : colors.noteFill;
      d3.select(this).select("circle, path")
        .transition().duration(120)
        .attr("fill", fill);
      tooltipEl.classList.remove("visible");
    });

    // Click: navigate.
    nodeEls.on("click", function (event, d) {
      event.stopPropagation();
      if (d.type === "note") {
        window.location.href = "termura-note://open?title=" + encodeURIComponent(d.label);
      } else if (d.type === "tag") {
        window.location.href = "termura-note://filter-tag?tag=" + encodeURIComponent(d.label);
      }
    });

    // Tick.
    simulation.on("tick", function () {
      linkEls
        .attr("x1", function (d) { return d.source.x; })
        .attr("y1", function (d) { return d.source.y; })
        .attr("x2", function (d) { return d.target.x; })
        .attr("y2", function (d) { return d.target.y; });
      nodeEls.attr("transform", function (d) { return "translate(" + d.x + "," + d.y + ")"; });
    });

    // Initial zoom to fit after simulation settles.
    simulation.on("end", function () { zoomToFit(svg, gRoot, zoom, width, height); });
  }

  function zoomToFit(svgEl, rootG, zoom, w, h) {
    var bounds = rootG.node().getBBox();
    if (bounds.width === 0 || bounds.height === 0) return;
    var padding = 40;
    var scale = Math.min(
      (w - padding * 2) / bounds.width,
      (h - padding * 2) / bounds.height,
      1.5
    );
    var tx = w / 2 - (bounds.x + bounds.width / 2) * scale;
    var ty = h / 2 - (bounds.y + bounds.height / 2) * scale;
    svgEl.transition().duration(500)
      .call(zoom.transform, d3.zoomIdentity.translate(tx, ty).scale(scale));
  }

  // Drag handlers.
  function dragStarted(event, d) {
    if (!event.active) simulation.alphaTarget(0.3).restart();
    d.fx = d.x; d.fy = d.y;
  }
  function dragged(event, d) { d.fx = event.x; d.fy = event.y; }
  function dragEnded(event, d) {
    if (!event.active) simulation.alphaTarget(0);
    d.fx = null; d.fy = null;
  }

  /**
   * Update CSS custom properties from Swift theme.
   * @param {string} cssText - `:root { ... }` block
   */
  function updateTheme(cssText) {
    var id = "termura-theme-vars";
    var existing = document.getElementById(id);
    if (existing) { existing.textContent = cssText; }
    else {
      var s = document.createElement("style");
      s.id = id; s.textContent = cssText;
      document.head.appendChild(s);
    }
    // Extract key colors from CSS variables for D3 elements.
    var root = getComputedStyle(document.documentElement);
    var bg = root.getPropertyValue("--termura-background").trim();
    if (bg) {
      colors.bg = bg;
      document.documentElement.style.setProperty("--bg", bg);
    }
    var fg = root.getPropertyValue("--termura-foreground").trim();
    if (fg) {
      document.documentElement.style.setProperty("--fg", fg);
      colors.labelColor = fg;
    }
    var blue = root.getPropertyValue("--termura-ansi-blue").trim();
    if (blue) { colors.noteFill = blue; colors.noteStroke = blue; }
    var green = root.getPropertyValue("--termura-ansi-green").trim();
    if (green) { colors.tagFill = green; colors.tagStroke = green; }
  }

  // Expose API to Swift.
  window.termuraGraph = {
    render: render,
    updateTheme: updateTheme
  };
})();
