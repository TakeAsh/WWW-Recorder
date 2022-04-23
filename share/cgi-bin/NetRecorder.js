﻿/**
 * @file NetRecorder.js
*/

import { CyclicEnum } from './modules/CyclicEnum.js';
import { getNodesByXpath } from './modules/Util.js';
import { ApiResult } from './modules/ApiResult.js';

const d = document;
const TrStatuses = new CyclicEnum(
  'UNCHECKED_HIDE_DETAIL',
  'CHECKED_HIDE_DETAIL',
  'CHECKED_SHOW_DETAIL',
);

class NetRecorder {

  static run() {
    this.prepareProgram();
    this.prepareMenu();
  }

  static prepareProgram() {
    getNodesByXpath('//input[@type="checkbox" and @name="ProgramId"]')
      .forEach(checkbox => checkbox.addEventListener('change', showSelection, false));

    const trs = getNodesByXpath('//tr[contains(@class, "tr_hover")]');
    trs.forEach(tr => {
      tr.addEventListener('click', nextTrStatus, false);
      const series = tr.dataset.series;
      if (series) {
        getNodesByXpath('./td[a[@data-link-type="Series"]]', tr)[0].addEventListener(
          'dblclick',
          (event) => {
            event.preventDefault();
            const status = TrStatuses.get(tr.dataset.trStatus).next().next();
            trs.filter(tr1 => tr1.dataset.series == series)
              .forEach(tr1 => setTrStatus(tr1, status));
          },
          false
        );
      }
    });

    getNodesByXpath('.//a[@data-link-type="Episode" or @data-link-type="Series"]').forEach(a => {
      a.target = '_blank';
      a.addEventListener('click', (event) => event.stopPropagation(), false);
    });
  }

  static prepareMenu() {
    d.getElementById('selectMenu')
      .addEventListener('change', changeMenu, false);

    ['ByStatus', 'ByTitle', 'ByUpdate']
      .forEach(key => {
        d.getElementById('Button_Sort_' + key)
          .addEventListener('click', sortBy, false);
      });

    ['Retry', 'Abort', 'Remove']
      .forEach(key => {
        d.getElementById('Button_Command_' + key)
          .addEventListener('click', command, false);
      });
    d.getElementById('formNewPrograms')
      .addEventListener('submit', addPrograms, false);
  }
}

NetRecorder.run();

function showSelection(event) {
  if (this.checked) {
    this.parentNode.parentNode.classList.add('tr_checked');
  } else {
    this.parentNode.parentNode.classList.remove('tr_checked');
    this.parentNode.parentNode.classList.remove('tr_show_detail');
    this.parentNode.parentNode.dataset.trStatus = TrStatuses.UNCHECKED_HIDE_DETAIL;
  }
}

function nextTrStatus(event) {
  setTrStatus(this, TrStatuses.get(this.dataset.trStatus).next());
}

function setTrStatus(tr, status) {
  const checkbox = tr.getElementsByTagName('input')[0];
  switch (tr.dataset.trStatus = status) {
    case TrStatuses.UNCHECKED_HIDE_DETAIL:
      checkbox.checked = false;
      tr.classList.remove('tr_show_detail');
      break;
    case TrStatuses.CHECKED_HIDE_DETAIL:
      checkbox.checked = true;
      tr.classList.remove('tr_show_detail');
      break;
    case TrStatuses.CHECKED_SHOW_DETAIL:
      checkbox.checked = true;
      tr.classList.add('tr_show_detail');
      break;
  }
  checkbox.dispatchEvent(new CustomEvent('change'));
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

function sortBy(event) {
  d.getElementById('SortBy').value = this.dataset.by;
  d.getElementById('formQueue').submit();
}

function command(event) {
  d.getElementById('Command').value = this.dataset.command;
  d.getElementById('formQueue').submit();
}

function addPrograms(event) {
  event.preventDefault();
  const xhr = new XMLHttpRequest();
  xhr.open('POST', './addPrograms.cgi');
  xhr.addEventListener('load', () => {
    console.log(new ApiResult(xhr.responseText));
    getNodesByXpath('.//form[@id="formNewPrograms"]/textarea')[0].value = '';
  }, false);
  xhr.send(new FormData(d.getElementById('formNewPrograms')));
}