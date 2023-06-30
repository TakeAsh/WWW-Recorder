/**
 * @file WwwRecorder.js
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

class WwwRecorder {

  static run() {
    this.prepareProgram();
    this.prepareMenu();
  }

  static prepareProgram() {
    getNodesByXpath('//input[@type="checkbox" and @name="ProgramId"]')
      .forEach(checkbox => checkbox.addEventListener('change', this.#showSelection, false));

    const trs = getNodesByXpath('//tr[contains(@class, "tr_hover")]');
    trs.forEach(tr => {
      tr.addEventListener('click', this.#nextTrStatus, false);
      getNodesByXpath("./td[3]", tr)[0].addEventListener('dblclick', this.#editProgram);
      const series = tr.dataset.series;
      if (series) {
        getNodesByXpath('./td[a[@data-link-type="Series"]]', tr)[0].addEventListener(
          'dblclick',
          (event) => {
            event.preventDefault();
            const status = TrStatuses.get(tr.dataset.trStatus).next().next();
            trs.filter(tr1 => tr1.dataset.series == series)
              .forEach(tr1 => this.#setTrStatus(tr1, status));
            this.#showSelectedPrograms();
          },
          false
        );
      }
    });

    getNodesByXpath('.//a[@data-link-type="Episode" or @data-link-type="Series"]')
      .forEach(a => {
        a.target = '_blank';
        a.addEventListener('click', (event) => event.stopPropagation(), false);
      });
  }

  static prepareMenu() {
    d.getElementById('selectMenu')
      .addEventListener('change', this.#changeMenu, false);

    ['ByStatus', 'ByTitle', 'ByUpdate']
      .forEach(key => {
        d.getElementById(`Button_Sort_${key}`)
          .addEventListener('click', this.#sortBy, false);
      });

    ['Retry', 'Abort', 'Remove']
      .forEach(key => {
        d.getElementById(`Button_Command_${key}`)
          .addEventListener('click', this.#command, false);
      });
    this.#prepareManuAdd();
  }

  static #prepareManuAdd() {
    d.getElementById('formNewPrograms')
      .addEventListener('submit', this.#addPrograms, false);
    d.getElementById('addPrograms_ProgramUris')
      .addEventListener('keyup', (event) => {
        if (event.key != 'Enter' || !event.ctrlKey) { return; }
        d.getElementById('addPrograms_Submit').click();
      }, false);
  }

  static #changeMenu = (event) => {
    const elmSelectMenu = event.target;
    const selectedMenu = elmSelectMenu.options[elmSelectMenu.selectedIndex].value;
    Array.from(elmSelectMenu.options)
      .map(option => option.value)
      .forEach(menu => {
        const elmMenu = d.getElementById(`Menu_${menu}`);
        if (!elmMenu) { return; }
        if (menu == selectedMenu) {
          elmMenu.classList.add('ShowMenu');
        } else {
          elmMenu.classList.remove('ShowMenu');
        }
      });
  }

  static #showSelection = (event) => {
    const checkbox = event.target;
    const tr = checkbox.parentNode.parentNode;
    if (checkbox.checked) {
      tr.classList.add('tr_checked');
    } else {
      tr.classList.remove('tr_checked');
      tr.classList.remove('tr_show_detail');
      tr.dataset.trStatus = TrStatuses.UNCHECKED_HIDE_DETAIL;
    }
  };

  static #nextTrStatus = (event) => {
    const tr = event.currentTarget;
    this.#setTrStatus(tr, TrStatuses.get(tr.dataset.trStatus).next());
    this.#showSelectedPrograms();
  };

  static #setTrStatus = (tr, status) => {
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

  static #showSelectedPrograms = () => {
    const selectedPrograms = getNodesByXpath('//tr[contains(@class, "tr_checked")]').length;
    d.title = d.title.replace(/^\(\d+\)/, '');
    if (selectedPrograms > 0) {
      d.title = `(${selectedPrograms})${d.title}`;
    }
  };

  static #editProgram = (event) => {
    const tr = event.currentTarget.parentNode;
    window.open(`./editProgram.cgi?Provider=${d.querySelector('#Provider').value}&ID=${tr.dataset.id}`, 'editProgram');
  };

  static #addPrograms = (event) => {
    event.preventDefault();
    const data = new FormData(d.getElementById('formNewPrograms'));
    const submit = d.getElementById('addPrograms_Submit');
    submit.disabled = true;
    const textarea = getNodesByXpath('.//form[@id="formNewPrograms"]/textarea')[0];
    textarea.disabled = true;
    fetch('./addPrograms.cgi', {
      method: 'POST',
      body: data,
    }).then(response => response.json())
      .then(result => {
        console.log(new ApiResult(result));
        submit.disabled = false;
        textarea.disabled = false;
        textarea.value = '';
        textarea.focus();
      });
  };

  static #sortBy = (event) => {
    d.getElementById('SortBy').value = event.target.dataset.by;
    d.getElementById('formQueue').submit();
  };

  static #command = (event) => {
    d.getElementById('Command').value = event.target.dataset.command;
    fetch('./command.cgi', {
      method: 'POST',
      body: new FormData(d.getElementById('formQueue')),
    }).then(response => response.json())
      .then(result => {
        console.log(new ApiResult(result));
      });
  };
}

WwwRecorder.run();
