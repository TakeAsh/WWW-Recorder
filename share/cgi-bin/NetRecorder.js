/**
 * @file NetRecorder.js
*/
{
  'use strict';

  class CyclicEnum extends Array {
    constructor(...args) {
      super();
      args.forEach((key, index) => Object.defineProperty(this, key, {
        value: this[index] = Object.freeze({
          toString: () => key,
          index: index,
          next: () => this[(index + 1) % args.length],
        }),
        enumerable: false,
      }));
      Object.freeze(this);
    }

    get(key) {
      return this.hasOwnProperty(key) ?
        this[key] :
        this[0];
    }
  }

  const d = document;
  const TrStatuses = new CyclicEnum(
    'UNCHECKED_HIDE_DETAIL',
    'CHECKED_HIDE_DETAIL',
    'CHECKED_SHOW_DETAIL',
  );

  function init() {
    getNodesByXpath('//input[@type="checkbox" and @name="ProgramId"]')
      .forEach(checkbox => checkbox.addEventListener('change', showSelection));
  }

  function changeMenu() {
    const elmSelectMenu = d.getElementById('selectMenu');
    const selectedMenu = elmSelectMenu.options[elmSelectMenu.selectedIndex].value;
    Array.from(elmSelectMenu.options)
      .map(option => option.value)
      .forEach(menu => {
        const elmMenu = d.getElementById('Menu_' + menu);
        if (!elmMenu) { return; }
        if (menu == selectedMenu) {
          elmMenu.classList.add('ShowMenu');
        } else {
          elmMenu.classList.remove('ShowMenu');
        }
      });
  }

  function sortBy(field) {
    d.getElementById('SortBy').value = field;
    d.getElementById('formQueue').submit();
  }

  function nextTrStatus(elm) {
    const checkbox = elm.getElementsByTagName('input')[0];
    switch (elm.dataset.trStatus = TrStatuses.get(elm.dataset.trStatus).next()) {
      case TrStatuses.UNCHECKED_HIDE_DETAIL:
        checkbox.checked = false;
        elm.classList.remove('tr_show_detail');
        break;
      case TrStatuses.CHECKED_HIDE_DETAIL:
        checkbox.checked = true;
        elm.classList.remove('tr_show_detail');
        break;
      case TrStatuses.CHECKED_SHOW_DETAIL:
        checkbox.checked = true;
        elm.classList.add('tr_show_detail');
        break;
    }
    checkbox.dispatchEvent(new CustomEvent('change'));
  }

  function showSelection(event) {
    if (this.checked) {
      this.parentNode.parentNode.classList.add('tr_checked');
    } else {
      this.parentNode.parentNode.classList.remove('tr_checked');
      this.parentNode.parentNode.classList.remove('tr_show_detail');
      this.parentNode.parentNode.dataset.trStatus = TrStatuses.UNCHECKED_HIDE_DETAIL;
    }
  }

  function abort() {
    d.getElementById('Command').value = 'Abort';
    d.getElementById('formQueue').submit();
  }

  function remove() {
    d.getElementById('Command').value = 'Remove';
    d.getElementById('formQueue').submit();
  }

  function getNodesByXpath(xpath, context) {
    const itr = d.evaluate(
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
}
