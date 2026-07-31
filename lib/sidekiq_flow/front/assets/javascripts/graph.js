import * as d3 from 'https://cdn.jsdelivr.net/npm/d3@7.9.0/+esm';
import * as dagreD3 from 'https://cdn.jsdelivr.net/npm/dagre-d3-es@7.0.14/+esm';

function getWidth(selector) {
  return document.querySelector(selector).getBoundingClientRect().width;
}

function getHeight(selector) {
  return document.querySelector(selector).getBoundingClientRect().height;
}

var graphOuterContainerSelector = '#workflow-graph',
    appPrefix = document.body.dataset.appPrefix,
    graphInnerContainerSelector = graphOuterContainerSelector + ' g',
    graphNodeSelector = graphInnerContainerSelector + '.node',
    taskModal = document.querySelector('#task-modal'),
    taskModalBackdrop = taskModal.querySelector('#task-modal-backdrop'),
    taskModalPanel = taskModal.querySelector('#task-modal-panel'),
    taskModalTitle = taskModal.querySelector('.modal-title'),
    taskModalAttrs = taskModal.querySelector('#task-attrs'),
    taskModalRetryBtn = taskModal.querySelector('#retry-task'),
    taskModalClearBtn = taskModal.querySelector('#clear-task'),
    graph = new dagreD3.graphlib.Graph();

function showModal() {
  taskModal.classList.remove('hidden');
  requestAnimationFrame(function() {
    taskModalBackdrop.classList.remove('opacity-0');
    taskModalPanel.classList.remove('opacity-0', 'scale-95');
  });
}

function hideModal() {
  taskModalBackdrop.classList.add('opacity-0');
  taskModalPanel.classList.add('opacity-0', 'scale-95');
  setTimeout(function() { taskModal.classList.add('hidden'); }, 150);
}

taskModal.querySelectorAll('[data-modal-dismiss]').forEach(function(el) {
  el.addEventListener('click', hideModal);
});

graph.setGraph({ranksep: 60, nodesep: 60});
graph.setDefaultEdgeLabel(function() { return {curve: d3.curveBasis}; });

workflow.tasks.forEach(function(task) {
  graph.setNode(task.klass, {label: task.name, class: task.status, paddingX: 20});
  task.children.forEach(function(childClass) {
    graph.setEdge(task.klass, childClass);
  });
});

var graphOuterContainer = d3.select(graphOuterContainerSelector),
    graphInnerContainer = d3.select(graphInnerContainerSelector),
    zoom = d3.zoom().on('zoom', function(event) {
      graphInnerContainer.attr('transform', event.transform);
    });
graphOuterContainer.call(zoom);

d3.select(graphInnerContainerSelector).call(dagreD3.render(), graph);

// START: fit graph to container
var outerWidth = getWidth(graphOuterContainerSelector),
    outerHeight = getHeight(graphOuterContainerSelector),
    graphWidth = graph.graph().width,
    graphHeight = graph.graph().height,
    fitPadding = 40,
    fitScale = Math.min(1, (outerWidth - fitPadding * 2) / graphWidth, (outerHeight - fitPadding * 2) / graphHeight),
    fitTranslateX = (outerWidth - graphWidth * fitScale) / 2,
    fitTranslateY = (outerHeight - graphHeight * fitScale) / 2;
graphOuterContainer.call(zoom.transform, d3.zoomIdentity.translate(fitTranslateX, fitTranslateY).scale(fitScale));
// END: fit graph to container

d3.selectAll(graphNodeSelector).each(function(taskClass) {
  d3.select(this).attr('data-task', JSON.stringify(workflow.tasks.find(function(task) { return task.klass == taskClass; })));
});

document.querySelectorAll(graphNodeSelector).forEach(function(node) {
  node.addEventListener('click', function() {
    var task = JSON.parse(this.getAttribute('data-task'));
    taskModalTitle.textContent = task.name;
    taskModalAttrs.innerHTML = '';
    Object.keys(task).forEach(function(key) {
      var value = key == 'params' ? JSON.stringify(task[key]) : task[key];
      var row = document.createElement('div');
      row.className = 'flex justify-between gap-4 py-1.5';
      var label = document.createElement('span');
      label.className = 'font-medium text-slate-500';
      label.textContent = key;
      var val = document.createElement('span');
      val.className = 'text-right text-slate-900 break-all font-mono text-xs';
      val.textContent = value;
      row.appendChild(label);
      row.appendChild(val);
      taskModalAttrs.appendChild(row);
    });
    showModal();
    taskModalRetryBtn.onclick = function() {
      if (confirm('Are you sure you want to retry the task?')) {
        fetch(appPrefix + '/workflow/' + workflow.id + '/task/' + task.klass + '/retry').then(function() { location.reload(); });
      }
    };
    taskModalClearBtn.onclick = function() {
      if (confirm('Are you sure you want to clear the task?')) {
        fetch(appPrefix + '/workflow/' + workflow.id + '/task/' + task.klass + '/clear').then(function() { location.reload(); });
      }
    };
  });
});
