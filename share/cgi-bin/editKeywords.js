import { prepareElement } from 'https://www.takeash.net/js/modules/PrepareElement.mjs';
import { ApiResult } from './modules/ApiResult.js';

const d = document;
const selectKeywords = d.getElementById('selectKeywords');
const inputKey = d.getElementById('inputKey');
const textareaNot = d.getElementById('textareaNot');

selectKeywords.addEventListener('change', (event) => {
  const opt = selectKeywords.selectedOptions[0];
  inputKey.value = opt.textContent;
  textareaNot.value = opt.dataset.not;
});

[
  [
    'buttonAdd',
    async (event) => {
      const key = inputKey.value = inputKey.value.trim();
      const not = textareaNot.value = textareaNot.value.trim();
      selectKeywords.value = key;
      if (selectKeywords.selectedIndex >= 0) {
        const opt = selectKeywords.selectedOptions[0];
        opt.dataset.not = not;
      } else {
        selectKeywords.add(prepareElement({
          tag: 'option',
          dataset: { not: not, },
          textContent: key,
        }));
        selectKeywords.value = key;
      }
      await call('Add', key, not);
    }
  ],
  [
    'buttonRemove',
    async (event) => {
      const key = inputKey.value = inputKey.value.trim();
      removeOption(key);
      await call('Remove', key);
    }
  ],
].forEach(button => {
  d.getElementById(button[0]).addEventListener('click', button[1]);
});

JSON.parse(d.getElementById('Keywords').value)
  .forEach(kw => {
    selectKeywords.add(prepareElement({
      tag: 'option',
      dataset: { not: kw.Not, },
      textContent: kw.Key,
    }));
  });

function removeOption(key) {
  selectKeywords.value = key;
  if (selectKeywords.selectedIndex >= 0) {
    selectKeywords.remove(selectKeywords.selectedIndex);
  }
}

async function call(command, key, not = '') {
  const data = new FormData();
  [
    ['Command', command],
    ['Key', key],
    ['Not', not],
  ].forEach(item => data.append(item[0], item[1]));
  const response = await fetch(location, {
    method: 'POST',
    body: data,
  });
  const result = await response.json();
  console.log(new ApiResult(result));
}
