/**
 * @file NetRecorder.js
*/
'use strict';

function init() {
  getNodesByXpath('//input[@type="checkbox" and @name="ProgramId"]')
    .forEach(checkbox => checkbox.addEventListener('change', showSelection));
}

function changeMenu() {
  let d = document;
  let elmSelectMenu = d.getElementById('selectMenu');
  let selectedMenu = elmSelectMenu.options[elmSelectMenu.selectedIndex].value;
  Array.from(elmSelectMenu.options)
    .map(option => option.value)
    .forEach(function(menu) {
      let elmMenu = d.getElementById('Menu_' + menu);
      if (!elmMenu) { return; }
      if (menu == selectedMenu) {
        elmMenu.classList.add('ShowMenu');
      } else {
        elmMenu.classList.remove('ShowMenu');
      }
    });
}

function sortBy(field) {
  let d = document;
  d.getElementById('SortBy').value = field;
  d.getElementById('formQueue').submit();
}

function toggleCheckbox(elm) {
  let checkbox = elm.getElementsByTagName('input')[0];
  checkbox.checked = !checkbox.checked;
  let event = new CustomEvent('change');
  checkbox.dispatchEvent(event);
}

function showSelection(event) {
  if (this.checked) {
    this.parentNode.parentNode.classList.add('tr_checked');
  } else {
    this.parentNode.parentNode.classList.remove('tr_checked');
  }
}

function abort() {
  let d = document;
  d.getElementById('Command').value = 'Abort';
  d.getElementById('formQueue').submit();
}

function remove() {
  let d = document;
  d.getElementById('Command').value = 'Remove';
  d.getElementById('formQueue').submit();
}

function getNodesByXpath(xpath, context) {
  let d = document;
  let itr = d.evaluate(
    xpath,
    context || d,
    null,
    XPathResult.ORDERED_NODE_ITERATOR_TYPE,
    null
  );
  let nodes = [];
  let node = null;
  while (node = itr.iterateNext()) {
    nodes.push(node);
  }
  return nodes;
}
