function getWidth(selector) {
  return document.querySelector(selector).getBoundingClientRect().width;
}

$(document).ready(function() {
  var graphOuterContainerSelector = '#workflow-graph',
      appPrefix = $('body').data('appPrefix'),
      graphInnerContainerSelector = graphOuterContainerSelector + ' g',
      graphNodeSelector = graphInnerContainerSelector + '.node',
      $taskModal = $('#task-modal'),
      $taskModalTitle = $taskModal.find('.modal-title'),
      $taskModalAttrs = $taskModal.find('#task-attrs'),
      $taskModalRetryBtn = $taskModal.find('#retry-task'),
      $taskModalClearBtn = $taskModal.find('#clear-task'),
      graph = new dagreD3.graphlib.Graph();

  graph.setGraph({});
  graph.setDefaultEdgeLabel(function() { return {}; });

  workflow.tasks.forEach(function(task) {
    graph.setNode(task.klass, {label: task.name, class: task.status});
    task.children.forEach(function(childClass) {
      graph.setEdge(task.klass, childClass);
    });
  });

  var graphOuterContainer = d3.select(graphOuterContainerSelector),
      graphInnerContainer = d3.select(graphInnerContainerSelector),
      zoom = d3.zoom().on('zoom', function() {
        graphInnerContainer.attr('transform', d3.event.transform);
      });
  graphOuterContainer.call(zoom);

  d3.select(graphInnerContainerSelector).call(dagreD3.render(), graph);

  $(graphOuterContainerSelector).css('padding-left', (getWidth(graphOuterContainerSelector) - getWidth(graphInnerContainerSelector)) / 2 + 'px')

  d3.selectAll(graphNodeSelector).each(function(taskClass) {
    d3.select(this).attr('data-task', JSON.stringify(workflow.tasks.find(function(task) { return task.klass == taskClass; })));
  });

  $(graphNodeSelector).click(function() {
    var task = $(this).data('task');
    $taskModalTitle.text(task.name);
    $taskModalAttrs.empty();
    Object.keys(task).forEach(function(key) {
      value = key == 'params' ? JSON.stringify(task[key]) : task[key];
      $taskModalAttrs.append($('<p>').text(key + ': ' + value));
    });
    $taskModal.modal();
    $taskModalRetryBtn.click(function() {
      if (confirm('Are you sure you want to retry the task?')) {
        $.get(appPrefix + '/workflow/' + workflow.id + '/task/' + task.klass + '/retry', function() { location.reload(); });
      }
    });
    $taskModalClearBtn.click(function() {
      if (confirm('Are you sure you want to clear the task?')) {
        $.get(appPrefix + '/workflow/' + workflow.id + '/task/' + task.klass + '/clear', function() { location.reload(); });
      }
    });
  });
});
