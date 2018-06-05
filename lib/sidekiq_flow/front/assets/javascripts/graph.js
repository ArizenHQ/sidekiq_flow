$(document).ready(function() {
    var graphContainerSelector = '#workflow-graph';
    var graph = new dagreD3.graphlib.Graph();
    graph.setGraph({
      rankdir: 'LR'
    });
    graph.setDefaultEdgeLabel(function() { return {}; });

    $(graphContainerSelector).data('workflow').tasks.forEach(function(task) {
      graph.setNode(task.klass, {label: task.klass, shape: 'circle', class: task.status});
      task.children.forEach(function(childClass) {
        graph.setEdge(task.klass, childClass);
      });
    });

    d3.select(graphContainerSelector + " g").call(dagreD3.render(), graph);
});
