const d = document;

[
  [
    'buttonEraseId',
    (event) => { d.getElementById('inputID').value = ''; }
  ],
  [
    'buttonEraseExtra',
    (event) => {
      const textArea = d.getElementById('textareaExtra');
      textArea.value = textArea.value.replace(/([^=\n]+)=([^\n]*)/g, '$1=');
    }
  ],
  [
    'buttonEraseProperties',
    (event) => {
      Array.from(event.target.parentNode.parentNode.querySelectorAll('textarea, input[type="text"]'))
        .forEach(input => { input.value = ''; });
    }
  ],
].forEach(button => {
  d.getElementById(button[0]).addEventListener('click', button[1]);
});
