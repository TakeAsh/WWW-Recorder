// ==UserScript==
// @name         Radio ShinyaBin Plus
// @namespace    https://TakeAsh.net/
// @version      2024-09-02 08:30
// @description  enhance Radio ShinyaBin
// @author       TakeAsh68k
// @match        https://www.nhk.jp/p/shinyabin/rs/*
// @require      https://raw.githubusercontent.com/TakeAsh/js-Modules/main/modules/PrepareElement.js
// @icon         https://www.google.com/s2/favicons?sz=64&domain=nhk.or.jp
// @grant        none
// ==/UserScript==

(async (w, d) => {
  'use strict';
  const keyLocalStorage = 'RSBP';
  const config = JSON.parse(localStorage.getItem(keyLocalStorage) || '{"Keywords": "幼き日の歌\\n声優"}');
  const regKeywords = config.Keywords && config.Keywords.length > 0
    ? new RegExp(`(${config.Keywords.split(/\n+/).join('|')})`, 'g')
    : null;
  await sleep(1000);
  addStyle({
    '.day_header': {
      position: 'sticky',
      top: '3em',
      backgroundColor: '#d0d0d0',
    },
    '.corner_title': {
      backgroundColor: '#c0ffff',
    },
    '.keyword': {
      backgroundColor: '#ffc0c0',
    },
    '.gc-article-text br[data-forceDisplay]': {
      display: 'inline',
    },
    '#RSBP_Config': {
      position: 'fixed',
      top: '0em',
      right: '0em',
      textAlign: 'right',
      backgroundColor: '#d0d0d0',
      zIndex: 600,
    },
    '#RSBP_Config button, textarea': {
      backgroundColor: 'revert',
      borderStyle: 'revert',
    },
  });
  decorate(d.querySelector('div[class="gc-article-text"] div'));
  addConfigEditor();

  function sleep(ms, resolve) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  function decorate(article) {
    if (!article) { return; }
    const days = [];
    let day = d.createElement('div');
    let next = null;
    for (let node = article.firstChild; node != null; node = next) {
      next = node.nextSibling;
      if (['H1', 'H2'].includes(node.tagName) && node.textContent.indexOf('アンカー') >= 0) {
        days.push(day);
        day = d.createElement('div');
        node.classList.add('day_header');
      }
      day.appendChild(node);
      if (node.innerHTML) {
        node.innerHTML = node.innerHTML
          .replace(/(〔[^〕]+〕)/g, (w, q1) => `<span class="corner_title">${q1}</span>`)
          .replace(/<br>/g, (w) => '<br data-forceDisplay>');
        if (regKeywords) {
          node.innerHTML = node.innerHTML
            .replace(regKeywords, (w, q1) => `<span class="keyword">${q1}</span>`);
        }
      }
    }
    days.push(day);
    days.forEach(day => article.appendChild(day));
  }

  function addConfigEditor() {
    d.body.appendChild(prepareElement({
      tag: 'details',
      id: 'RSBP_Config',
      children: [
        { tag: 'summary', textContent: '\u{2699}', },
        {
          tag: 'div',
          children: [
            {
              tag: 'button',
              textContent: 'OK',
              events: {
                click: (event) => {
                  const textareaKeywords = d.querySelector('#RSBP_Config textarea');
                  const keywordsHash = textareaKeywords.value
                    .split(/\n+/)
                    .reduce(
                      (acc, cur) => {
                        if (cur && cur.length > 0) {
                          acc[cur] = 1;
                        }
                        return acc;
                      },
                      {}
                    );
                  config.Keywords = textareaKeywords.value = Object.keys(keywordsHash)
                    .sort()
                    .join('\n');
                  localStorage.setItem(keyLocalStorage, JSON.stringify(config));
                },
              },
            },
          ],
        },
        {
          tag: 'div',
          children: [
            { tag: 'textarea', cols: 16, rows: 8, value: config.Keywords },
          ],
        },
      ],
    }));
  }
})(window, document);
